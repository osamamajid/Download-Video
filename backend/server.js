const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const winston = require('winston');
const fs = require('fs-extra');
const path = require('path');
const crypto = require('crypto');
const ytdl = require('@distube/ytdl-core');
const ffmpeg = require('fluent-ffmpeg');
const ffmpegPath = require('ffmpeg-static');
const YTDlpWrap = require('yt-dlp-wrap').default;
const ytDlpWrap = new YTDlpWrap();
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

// Set ffmpeg path
ffmpeg.setFfmpegPath(ffmpegPath);

const app = express();
const PORT = process.env.PORT || 3000;

// Structured Logging
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' }),
  ],
});

if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: winston.format.combine(
      winston.format.colorize(),
      winston.format.simple()
    ),
  }));
}

// Rate limiting
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // Limit each IP to 100 requests per windowMs
  message: {
    error: 'تجاوزت الحد المسموح من الطلبات. يرجى المحاولة لاحقاً.',
    errorEn: 'Too many requests, please try again later.'
  }
});

const downloadLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 20, // Limit each IP to 20 downloads per hour
  message: {
    error: 'تجاوزت الحد المسموح من التحميلات. يرجى المحاولة لاحقاً.',
    errorEn: 'Too many downloads, please try again later.'
  }
});

// Store download progress
const downloadsProgress = new Map();

// Middleware
const corsOptions = {
  origin: process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',') : '*',
  methods: ['GET', 'POST', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization']
};

app.use(cors(corsOptions));
app.use(express.json());
app.use(express.static('public'));

// Helper for standardized error responses
function sendError(res, statusCode, messageAr, messageEn, detail = null) {
  logger.error(`${messageEn}: ${detail || ''}`);
  res.status(statusCode).json({
    error: messageAr,
    errorEn: messageEn,
    detail: detail
  });
}

// Create directories
const DOWNLOADS_DIR = path.join(__dirname, 'downloads');
const VIDEOS_DIR = path.join(DOWNLOADS_DIR, 'videos');
const AUDIOS_DIR = path.join(DOWNLOADS_DIR, 'audios');

[DOWNLOADS_DIR, VIDEOS_DIR, AUDIOS_DIR].forEach(dir => {
  fs.ensureDirSync(dir);
});

// Serve downloaded files
app.use('/downloads', express.static(DOWNLOADS_DIR));

// Allowed platforms and their regex patterns
const ALLOWED_PLATFORMS = [
  { name: 'youtube', regex: /^(https?:\/\/)?(www\.|m\.)?(youtube\.com|youtu\.be)\/.+$/ },
  { name: 'facebook', regex: /^(https?:\/\/)?(www\.)?(facebook\.com|fb\.com|fb\.watch)\/.+$/ },
  { name: 'twitter', regex: /^(https?:\/\/)?(www\.)?(twitter\.com|x\.com)\/.+$/ },
  { name: 'instagram', regex: /^(https?:\/\/)?(www\.)?instagram\.com\/.+$/ },
  { name: 'tiktok', regex: /^(https?:\/\/)?(www\.)?tiktok\.com\/.+$/ },
  { name: 'linkedin', regex: /^(https?:\/\/)?(www\.)?linkedin\.com\/.+$/ },
  { name: 'vimeo', regex: /^(https?:\/\/)?(www\.)?vimeo\.com\/.+$/ },
];

function detectPlatform(url) {
  if (!url || typeof url !== 'string') return 'other';
  for (const platform of ALLOWED_PLATFORMS) {
    if (platform.regex.test(url)) {
      return platform.name;
    }
  }
  return 'other';
}

// Get video info using yt-dlp (for all platforms)
async function getVideoInfoWithYtDlp(url) {
  try {
    const stdout = await ytDlpWrap.execPromise([
      '--dump-json',
      '--no-warnings',
      '--force-ipv4',
      url
    ]);
    const info = JSON.parse(stdout);

    const formats = [];
    if (info.formats) {
      info.formats.forEach(format => {
        if (format.vcodec !== 'none' || format.acodec !== 'none') {
          formats.push({
            itag: format.format_id || format.format,
            quality: format.resolution || format.height + 'p' || format.quality || 'unknown',
            container: format.ext || 'mp4',
            hasVideo: format.vcodec !== 'none',
            hasAudio: format.acodec !== 'none',
            filesize: format.filesize || 0,
            url: format.url || url
          });
        }
      });
    }

    return {
      title: info.title || 'بدون عنوان',
      thumbnail: info.thumbnail || info.thumbnails?.[0]?.url,
      duration: info.duration || 0,
      formats: formats.length > 0 ? formats : [{
        itag: 'best',
        quality: 'أفضل جودة',
        container: info.ext || 'mp4',
        hasVideo: true,
        hasAudio: true,
        filesize: info.filesize || 0,
        url: url
      }],
      platform: detectPlatform(url)
    };
  } catch (error) {
    logger.error('yt-dlp error:', error);
    throw error;
  }
}

// Get video info
app.post('/api/video/info', apiLimiter, async (req, res) => {
  try {
    const { url } = req.body;
    
    if (!url) {
      return sendError(res, 400, 'الرابط مطلوب', 'URL is required');
    }

    const platform = detectPlatform(url);
    if (platform === 'other') {
      return sendError(res, 400, 'هذا الرابط غير مدعوم أو غير صالح', 'This URL is not supported or invalid');
    }

    // Use ytdl-core for YouTube (faster and more reliable)
    if (platform === 'youtube' && ytdl.validateURL(url)) {
      try {
        const info = await ytdl.getInfo(url, {
          requestOptions: {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }
          }
        });
        
        const formats = info.formats
          .filter(format => format.hasVideo || format.hasAudio)
          .map(format => ({
            itag: format.itag,
            quality: format.qualityLabel || format.audioQuality || format.quality || 'unknown',
            container: format.container || 'mp4',
            hasVideo: format.hasVideo || false,
            hasAudio: format.hasAudio || false,
            filesize: format.contentLength || 0,
            url: format.url
          }));

        logger.info(`Fetched YouTube info for: ${url}`);
        return res.json({
          title: info.videoDetails.title,
          thumbnail: info.videoDetails.thumbnails[0]?.url || info.videoDetails.thumbnails[info.videoDetails.thumbnails.length - 1]?.url,
          duration: info.videoDetails.lengthSeconds,
          formats: formats,
          platform: 'youtube'
        });
      } catch (error) {
        logger.error('YouTube ytdl-core error, trying yt-dlp:', error);
        // Fallback to yt-dlp if ytdl-core fails
        const info = await getVideoInfoWithYtDlp(url);
        return res.json(info);
      }
    }

    // Use yt-dlp for all other platforms
    try {
      const info = await getVideoInfoWithYtDlp(url);
      logger.info(`Fetched info for: ${url}`);
      return res.json(info);
    } catch (error) {
      return sendError(res, 500, 'فشل في جلب معلومات الفيديو', 'Failed to fetch video information', error.message);
    }

  } catch (error) {
    sendError(res, 500, 'حدث خطأ غير متوقع', 'An unexpected error occurred', error.message);
  }
});

// Download video using yt-dlp
async function downloadWithYtDlp(url, outputPath, quality = 'best') {
  try {
    await ytDlpWrap.execPromise([
      '-f', quality,
      '-o', outputPath,
      '--no-warnings',
      '--force-ipv4',
      url
    ]);
    return true;
  } catch (error) {
    logger.error('yt-dlp download error:', error);
    throw error;
  }
}

// Download video
app.post('/api/video/download', downloadLimiter, async (req, res) => {
  const { url, quality, format } = req.body;

  if (!url) {
    return sendError(res, 400, 'الرابط مطلوب', 'URL is required');
  }

  const platform = detectPlatform(url);
  if (platform === 'other') {
    return sendError(res, 400, 'هذا الرابط غير مدعوم أو غير صالح', 'This URL is not supported or invalid');
  }

  const downloadId = crypto.randomUUID();
  downloadsProgress.set(downloadId, { progress: 0, status: 'starting', platform });

  logger.info(`Starting download: ${downloadId} for ${url}`);
  res.json({ downloadId });

  // Start download in background
  (async () => {
    try {
      let title = 'video';
      let outputPath;

      // Get video title first
      try {
        if (platform === 'youtube' && ytdl.validateURL(url)) {
          const info = await ytdl.getInfo(url);
          title = info.videoDetails.title.replace(/[^a-z0-9]/gi, '_').substring(0, 100);
        } else {
          const info = await getVideoInfoWithYtDlp(url);
          title = info.title.replace(/[^a-z0-9]/gi, '_').substring(0, 100);
        }
      } catch (error) {
        logger.error('Error getting title:', error);
      }

      const timestamp = Date.now();
      const ext = format || 'mp4';
      outputPath = path.join(VIDEOS_DIR, `${title}_${timestamp}.${ext}`);

      // Use yt-dlp for all platforms as it is more reliable than ytdl-core
      try {
        const qualityParam = quality || 'best';
        downloadsProgress.set(downloadId, { progress: 10, status: 'downloading', platform });
        await downloadWithYtDlp(url, outputPath, qualityParam);
        
        if (fs.existsSync(outputPath)) {
          downloadsProgress.set(downloadId, {
            progress: 100,
            status: 'finished',
            file: path.basename(outputPath),
            path: `/downloads/videos/${path.basename(outputPath)}`,
            size: fs.statSync(outputPath).size,
            platform
          });
        } else {
          downloadsProgress.set(downloadId, { status: 'error', error: 'فشل في تحميل الفيديو', platform });
        }
      } catch (error) {
        logger.error(`Download error for ${downloadId}: ${error.message}`);
        downloadsProgress.set(downloadId, { status: 'error', error: error.message, platform });
      }
    } catch (error) {
      logger.error(`Error in background download ${downloadId}: ${error.message}`);
      downloadsProgress.set(downloadId, { status: 'error', error: error.message, platform });
    }
  })();
});

// Download audio only
app.post('/api/audio/download', downloadLimiter, async (req, res) => {
  const { url } = req.body;

  if (!url) {
    return sendError(res, 400, 'الرابط مطلوب', 'URL is required');
  }

  const platform = detectPlatform(url);
  if (platform === 'other') {
    return sendError(res, 400, 'هذا الرابط غير مدعوم أو غير صالح', 'This URL is not supported or invalid');
  }

  const downloadId = crypto.randomUUID();
  downloadsProgress.set(downloadId, { progress: 0, status: 'starting', platform });

  logger.info(`Starting audio download: ${downloadId} for ${url}`);
  res.json({ downloadId });

  // Start download in background
  (async () => {
    try {
      let title = 'audio';
      const timestamp = Date.now();
      const outputPath = path.join(AUDIOS_DIR, `${title}_${timestamp}.mp3`);
      const tempPath = path.join(AUDIOS_DIR, `temp_${timestamp}.m4a`);

      // Get title
      try {
        if (platform === 'youtube' && ytdl.validateURL(url)) {
          const info = await ytdl.getInfo(url);
          title = info.videoDetails.title.replace(/[^a-z0-9]/gi, '_').substring(0, 100);
        } else {
          const info = await getVideoInfoWithYtDlp(url);
          title = info.title.replace(/[^a-z0-9]/gi, '_').substring(0, 100);
        }
      } catch (error) {
        logger.error('Error getting title:', error);
      }

      // Use yt-dlp for audio (works for all platforms)
      try {
        const finalOutputPath = path.join(AUDIOS_DIR, `${title}_${timestamp}.mp3`);
        downloadsProgress.set(downloadId, { progress: 10, status: 'downloading', platform });

        await ytDlpWrap.execPromise([
          '-f', 'bestaudio',
          '-x',
          '--audio-format', 'mp3',
          '-o', finalOutputPath,
          '--no-warnings',
          '--force-ipv4',
          url
        ]);

        if (fs.existsSync(finalOutputPath)) {
          downloadsProgress.set(downloadId, {
            progress: 100,
            status: 'finished',
            file: path.basename(finalOutputPath),
            path: `/downloads/audios/${path.basename(finalOutputPath)}`,
            size: fs.statSync(finalOutputPath).size,
            platform
          });
          return;
        } else {
          // Try alternative format
          await ytDlpWrap.execPromise([
            '-f', 'bestaudio',
            '-x',
            '--audio-format', 'm4a',
            '-o', tempPath,
            '--no-warnings',
            '--force-ipv4',
            url
          ]);
          
          if (fs.existsSync(tempPath)) {
            // Convert to MP3 using ffmpeg
            ffmpeg(tempPath)
              .toFormat('mp3')
              .audioBitrate(128)
              .on('end', () => {
                try {
                  fs.removeSync(tempPath);
                  if (fs.existsSync(outputPath)) {
                    downloadsProgress.set(downloadId, {
                      progress: 100,
                      status: 'finished',
                      file: path.basename(outputPath),
                      path: `/downloads/audios/${path.basename(outputPath)}`,
                      size: fs.statSync(outputPath).size,
                      platform
                    });
                  }
                } catch (err) {
                  logger.error('Error cleaning up temp file:', err);
                }
              })
              .on('error', (err) => {
                logger.error('FFmpeg error:', err);
                if (fs.existsSync(tempPath)) {
                  const fallbackPath = outputPath.replace('.mp3', '.m4a');
                  fs.moveSync(tempPath, fallbackPath);
                  downloadsProgress.set(downloadId, {
                    progress: 100,
                    status: 'finished',
                    file: path.basename(fallbackPath),
                    path: `/downloads/audios/${path.basename(fallbackPath)}`,
                    size: fs.statSync(fallbackPath).size,
                    platform
                  });
                }
              })
              .save(outputPath);
            return;
          }
        }
      } catch (error) {
        logger.error('Audio download error:', error);
      }

      // yt-dlp fallback failed or already tried
      const currentStatus = downloadsProgress.get(downloadId);
      if (currentStatus && currentStatus.status !== 'finished') {
        downloadsProgress.set(downloadId, { status: 'error', error: 'فشل في تحميل الصوت', platform });
      }
    } catch (error) {
      logger.error(`Error in background audio download ${downloadId}: ${error.message}`);
      downloadsProgress.set(downloadId, { status: 'error', error: error.message, platform });
    }
  })();
});

// Get download progress
app.get('/api/progress/:id', (req, res) => {
  const { id } = req.params;
  const progress = downloadsProgress.get(id);
  if (progress) {
    res.json(progress);
    // If finished or error, we might want to remove it after some time
    if (progress.status === 'finished' || progress.status === 'error') {
      setTimeout(() => downloadsProgress.delete(id), 60000);
    }
  } else {
    res.status(404).json({ error: 'Download not found' });
  }
});

// Get all downloaded files
app.get('/api/files', async (req, res) => {
  try {
    const videos = fs.readdirSync(VIDEOS_DIR).map(file => {
      const filePath = path.join(VIDEOS_DIR, file);
      const stats = fs.statSync(filePath);
      return {
        name: file,
        type: 'video',
        size: stats.size,
        date: stats.mtime,
        path: `/downloads/videos/${file}`
      };
    });

    const audios = fs.readdirSync(AUDIOS_DIR).map(file => {
      const filePath = path.join(AUDIOS_DIR, file);
      const stats = fs.statSync(filePath);
      return {
        name: file,
        type: 'audio',
        size: stats.size,
        date: stats.mtime,
        path: `/downloads/audios/${file}`
      };
    });

    res.json({
      videos: videos.sort((a, b) => b.date - a.date),
      audios: audios.sort((a, b) => b.date - a.date)
    });

  } catch (error) {
    logger.error('Error getting files:', error);
    res.status(500).json({ error: error.message });
  }
});

// Delete file
app.delete('/api/files/:type/:filename', async (req, res) => {
  try {
    const { type, filename } = req.params;
    const dir = type === 'video' ? VIDEOS_DIR : AUDIOS_DIR;
    const filePath = path.join(dir, filename);

    if (fs.existsSync(filePath)) {
      fs.removeSync(filePath);
      res.json({ success: true, message: 'File deleted' });
    } else {
      res.status(404).json({ error: 'File not found' });
    }

  } catch (error) {
    logger.error('Error deleting file:', error);
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  logger.info(`Server running on http://localhost:${PORT}`);
  logger.info('Supported platforms: YouTube, Facebook, Twitter/X, Instagram, TikTok, LinkedIn, Vimeo, and more!');
});
