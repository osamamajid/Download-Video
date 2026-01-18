const express = require('express');
const cors = require('cors');
const fs = require('fs-extra');
const path = require('path');
const ytdl = require('@distube/ytdl-core');
const ffmpeg = require('fluent-ffmpeg');
const { exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Create directories
const DOWNLOADS_DIR = path.join(__dirname, 'downloads');
const VIDEOS_DIR = path.join(DOWNLOADS_DIR, 'videos');
const AUDIOS_DIR = path.join(DOWNLOADS_DIR, 'audios');

[DOWNLOADS_DIR, VIDEOS_DIR, AUDIOS_DIR].forEach(dir => {
  fs.ensureDirSync(dir);
});

// Serve downloaded files
app.use('/downloads', express.static(DOWNLOADS_DIR));

// Detect platform from URL
function detectPlatform(url) {
  if (url.includes('youtube.com') || url.includes('youtu.be')) {
    return 'youtube';
  } else if (url.includes('facebook.com') || url.includes('fb.com') || url.includes('fb.watch')) {
    return 'facebook';
  } else if (url.includes('twitter.com') || url.includes('x.com')) {
    return 'twitter';
  } else if (url.includes('instagram.com')) {
    return 'instagram';
  } else if (url.includes('tiktok.com')) {
    return 'tiktok';
  } else if (url.includes('linkedin.com')) {
    return 'linkedin';
  } else if (url.includes('vimeo.com')) {
    return 'vimeo';
  }
  return 'other';
}

// Get video info using yt-dlp (for all platforms)
async function getVideoInfoWithYtDlp(url) {
  try {
    // Check if yt-dlp is installed
    try {
      await execAsync('yt-dlp --version');
    } catch {
      throw new Error('yt-dlp غير مثبت. يرجى تثبيته من https://github.com/yt-dlp/yt-dlp');
    }

    const command = `yt-dlp --dump-json --no-warnings "${url}"`;
    const { stdout } = await execAsync(command);
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
    console.error('yt-dlp error:', error);
    throw error;
  }
}

// Get video info
app.post('/api/video/info', async (req, res) => {
  try {
    const { url } = req.body;
    
    if (!url) {
      return res.status(400).json({ error: 'URL is required' });
    }

    const platform = detectPlatform(url);

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

        return res.json({
          title: info.videoDetails.title,
          thumbnail: info.videoDetails.thumbnails[0]?.url || info.videoDetails.thumbnails[info.videoDetails.thumbnails.length - 1]?.url,
          duration: info.videoDetails.lengthSeconds,
          formats: formats,
          platform: 'youtube'
        });
      } catch (error) {
        console.error('YouTube ytdl-core error, trying yt-dlp:', error);
        // Fallback to yt-dlp if ytdl-core fails
        const info = await getVideoInfoWithYtDlp(url);
        return res.json(info);
      }
    }

    // Use yt-dlp for all other platforms
    try {
      const info = await getVideoInfoWithYtDlp(url);
      return res.json(info);
    } catch (error) {
      console.error('Error getting video info:', error);
      throw new Error(`فشل في جلب معلومات الفيديو: ${error.message}`);
    }

  } catch (error) {
    console.error('Error getting video info:', error);
    res.status(500).json({ error: error.message });
  }
});

// Download video using yt-dlp
async function downloadWithYtDlp(url, outputPath, quality = 'best') {
  try {
    // Check if yt-dlp is installed
    try {
      await execAsync('yt-dlp --version');
    } catch {
      throw new Error('yt-dlp غير مثبت');
    }

    let command = `yt-dlp -f "${quality}" -o "${outputPath}" --no-warnings "${url}"`;
    
    // If quality is an itag, use it directly
    if (quality === 'best' || quality === 'worst') {
      command = `yt-dlp -f "${quality}" -o "${outputPath}" --no-warnings "${url}"`;
    } else {
      command = `yt-dlp -f "${quality}" -o "${outputPath}" --no-warnings "${url}"`;
    }

    await execAsync(command);
    return true;
  } catch (error) {
    console.error('yt-dlp download error:', error);
    throw error;
  }
}

// Download video
app.post('/api/video/download', async (req, res) => {
  try {
    const { url, quality, format } = req.body;
    
    if (!url) {
      return res.status(400).json({ error: 'URL is required' });
    }

    const platform = detectPlatform(url);
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
      console.error('Error getting title:', error);
    }

    const timestamp = Date.now();
    const ext = format || 'mp4';
    outputPath = path.join(VIDEOS_DIR, `${title}_${timestamp}.${ext}`);

    // Download based on platform
    if (platform === 'youtube' && ytdl.validateURL(url)) {
      try {
        const info = await ytdl.getInfo(url, {
          requestOptions: {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }
          }
        });
        
        let selectedFormat;
        if (quality) {
          selectedFormat = info.formats.find(f => 
            f.qualityLabel === quality || f.itag === parseInt(quality)
          );
        }
        
        if (!selectedFormat) {
          selectedFormat = info.formats
            .filter(f => f.hasVideo && f.hasAudio && f.container === 'mp4')
            .sort((a, b) => {
              const aQuality = parseInt(a.qualityLabel) || 0;
              const bQuality = parseInt(b.qualityLabel) || 0;
              return bQuality - aQuality;
            })[0];
        }
        
        if (!selectedFormat) {
          selectedFormat = info.formats
            .filter(f => f.hasVideo)
            .sort((a, b) => {
              const aQuality = parseInt(a.qualityLabel) || 0;
              const bQuality = parseInt(b.qualityLabel) || 0;
              return bQuality - aQuality;
            })[0];
        }

        if (!selectedFormat) {
          return res.status(400).json({ error: 'لا توجد جودة متاحة للتحميل' });
        }

        const videoStream = ytdl(url, { 
          format: selectedFormat,
          quality: 'highest',
          filter: 'audioandvideo'
        });
        
        const writeStream = fs.createWriteStream(outputPath);
        
        videoStream.pipe(writeStream);
        
        videoStream.on('progress', (chunkLength, downloaded, total) => {
          const percent = (downloaded / total) * 100;
          console.log(`Download progress: ${percent.toFixed(2)}%`);
        });

        videoStream.on('error', (error) => {
          console.error('Video stream error:', error);
          if (!res.headersSent) {
            res.status(500).json({ error: `خطأ في تحميل الفيديو: ${error.message}` });
          }
        });

        writeStream.on('finish', () => {
          if (!res.headersSent) {
            res.json({
              success: true,
              file: path.basename(outputPath),
              path: `/downloads/videos/${path.basename(outputPath)}`,
              size: fs.statSync(outputPath).size
            });
          }
        });

        writeStream.on('error', (error) => {
          console.error('Write stream error:', error);
          if (!res.headersSent) {
            res.status(500).json({ error: `خطأ في حفظ الملف: ${error.message}` });
          }
        });

        return; // Don't continue to yt-dlp
      } catch (error) {
        console.error('YouTube ytdl-core download error, trying yt-dlp:', error);
        // Fallback to yt-dlp
      }
    }

    // Use yt-dlp for all platforms (including YouTube fallback)
    try {
      const qualityParam = quality || 'best';
      await downloadWithYtDlp(url, outputPath, qualityParam);
      
      if (fs.existsSync(outputPath)) {
        res.json({
          success: true,
          file: path.basename(outputPath),
          path: `/downloads/videos/${path.basename(outputPath)}`,
          size: fs.statSync(outputPath).size
        });
      } else {
        res.status(500).json({ error: 'فشل في تحميل الفيديو' });
      }
    } catch (error) {
      console.error('Download error:', error);
      res.status(500).json({ error: `خطأ في التحميل: ${error.message}` });
    }

  } catch (error) {
    console.error('Error downloading video:', error);
    res.status(500).json({ error: error.message });
  }
});

// Download audio only
app.post('/api/audio/download', async (req, res) => {
  try {
    const { url } = req.body;
    
    if (!url) {
      return res.status(400).json({ error: 'URL is required' });
    }

    const platform = detectPlatform(url);
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
      console.error('Error getting title:', error);
    }

    // Use yt-dlp for audio (works for all platforms)
    try {
      const finalOutputPath = path.join(AUDIOS_DIR, `${title}_${timestamp}.mp3`);
      const command = `yt-dlp -f "bestaudio" -x --audio-format mp3 -o "${finalOutputPath}" --no-warnings "${url}"`;
      
      await execAsync(command);
      
      if (fs.existsSync(finalOutputPath)) {
        res.json({
          success: true,
          file: path.basename(finalOutputPath),
          path: `/downloads/audios/${path.basename(finalOutputPath)}`,
          size: fs.statSync(finalOutputPath).size
        });
      } else {
        // Try alternative format
        const altCommand = `yt-dlp -f "bestaudio" -x --audio-format m4a -o "${tempPath}" --no-warnings "${url}"`;
        await execAsync(altCommand);
        
        if (fs.existsSync(tempPath)) {
          // Convert to MP3 using ffmpeg
          ffmpeg(tempPath)
            .toFormat('mp3')
            .audioBitrate(128)
            .on('end', () => {
              try {
                fs.removeSync(tempPath);
                if (!res.headersSent && fs.existsSync(outputPath)) {
                  res.json({
                    success: true,
                    file: path.basename(outputPath),
                    path: `/downloads/audios/${path.basename(outputPath)}`,
                    size: fs.statSync(outputPath).size
                  });
                }
              } catch (err) {
                console.error('Error cleaning up temp file:', err);
              }
            })
            .on('error', (err) => {
              console.error('FFmpeg error:', err);
              if (fs.existsSync(tempPath)) {
                const fallbackPath = outputPath.replace('.mp3', '.m4a');
                fs.moveSync(tempPath, fallbackPath);
                if (!res.headersSent) {
                  res.json({
                    success: true,
                    file: path.basename(fallbackPath),
                    path: `/downloads/audios/${path.basename(fallbackPath)}`,
                    size: fs.statSync(fallbackPath).size
                  });
                }
              }
            })
            .save(outputPath);
        } else {
          res.status(500).json({ error: 'فشل في تحميل الصوت' });
        }
      }
    } catch (error) {
      console.error('Audio download error:', error);
      
      // Fallback to ytdl-core for YouTube only
      if (platform === 'youtube' && ytdl.validateURL(url)) {
        try {
          const info = await ytdl.getInfo(url);
          const audioFormat = ytdl.chooseFormat(info.formats, { 
            quality: 'highestaudio',
            filter: 'audioonly'
          });
          
          if (!audioFormat) {
            return res.status(400).json({ error: 'لا يوجد تنسيق صوت متاح' });
          }

          const audioStream = ytdl(url, { 
            format: audioFormat,
            quality: 'highestaudio',
            filter: 'audioonly'
          });
          const writeStream = fs.createWriteStream(tempPath);
          
          audioStream.pipe(writeStream);
          
          audioStream.on('error', (error) => {
            console.error('Audio stream error:', error);
            if (!res.headersSent) {
              res.status(500).json({ error: `خطأ في تحميل الصوت: ${error.message}` });
            }
          });

          writeStream.on('finish', () => {
            if (!fs.existsSync(tempPath)) {
              if (!res.headersSent) {
                return res.status(500).json({ error: 'فشل في تحميل الملف المؤقت' });
              }
              return;
            }
            
            ffmpeg(tempPath)
              .toFormat('mp3')
              .audioBitrate(128)
              .on('end', () => {
                try {
                  fs.removeSync(tempPath);
                  if (!res.headersSent && fs.existsSync(outputPath)) {
                    res.json({
                      success: true,
                      file: path.basename(outputPath),
                      path: `/downloads/audios/${path.basename(outputPath)}`,
                      size: fs.statSync(outputPath).size
                    });
                  }
                } catch (err) {
                  console.error('Error cleaning up temp file:', err);
                }
              })
              .on('error', (err) => {
                console.error('FFmpeg error:', err);
                try {
                  const fallbackPath = outputPath.replace('.mp3', '.m4a');
                  if (fs.existsSync(tempPath)) {
                    fs.moveSync(tempPath, fallbackPath);
                    if (!res.headersSent) {
                      res.json({
                        success: true,
                        file: path.basename(fallbackPath),
                        path: `/downloads/audios/${path.basename(fallbackPath)}`,
                        size: fs.statSync(fallbackPath).size
                      });
                    }
                  }
                } catch (moveErr) {
                  console.error('Error moving temp file:', moveErr);
                  if (!res.headersSent) {
                    res.status(500).json({ error: 'فشل في تحويل الصوت' });
                  }
                }
              })
              .save(outputPath);
          });

          writeStream.on('error', (error) => {
            console.error('Write stream error:', error);
            if (!res.headersSent) {
              res.status(500).json({ error: `خطأ في حفظ الملف: ${error.message}` });
            }
          });
        } catch (error) {
          if (!res.headersSent) {
            res.status(500).json({ error: `خطأ في تحميل الصوت: ${error.message}` });
          }
        }
      } else {
        if (!res.headersSent) {
          res.status(500).json({ error: `خطأ في تحميل الصوت: ${error.message}` });
        }
      }
    }

  } catch (error) {
    console.error('Error downloading audio:', error);
    res.status(500).json({ error: error.message });
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
    console.error('Error getting files:', error);
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
    console.error('Error deleting file:', error);
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
  console.log('Supported platforms: YouTube, Facebook, Twitter/X, Instagram, TikTok, LinkedIn, Vimeo, and more!');
});
