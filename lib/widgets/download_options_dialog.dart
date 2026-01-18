import 'package:flutter/material.dart';
import '../providers/download_provider.dart';

class DownloadOptionsDialog extends StatefulWidget {
  final VideoInfo videoInfo;
  final String videoUrl;

  const DownloadOptionsDialog({
    super.key,
    required this.videoInfo,
    required this.videoUrl,
  });

  @override
  State<DownloadOptionsDialog> createState() => _DownloadOptionsDialogState();
}

class _DownloadOptionsDialogState extends State<DownloadOptionsDialog> {
  VideoFormat? _selectedFormat;
  bool _downloadAsAudio = false;

  @override
  void initState() {
    super.initState();
    final formats = widget.videoInfo.formats
        .where((f) => f.hasVideo && f.hasAudio)
        .toList();
    if (formats.isNotEmpty) {
      _selectedFormat = formats.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formats = widget.videoInfo.formats
        .where((f) => f.hasVideo && f.hasAudio)
        .toList();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.download_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'خيارات التحميل',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Video Title
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.videoInfo.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 20),

            // Download Type Toggle
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _downloadAsAudio
                        ? Icons.music_note_rounded
                        : Icons.videocam_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _downloadAsAudio ? 'تحميل كصوت' : 'تحميل كفيديو',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _downloadAsAudio
                              ? 'MP3 - جودة صوت عالية'
                              : 'MP4 - مع فيديو وصوت',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _downloadAsAudio,
                    onChanged: (value) {
                      setState(() {
                        _downloadAsAudio = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Quality Selector (only for video)
            if (!_downloadAsAudio && formats.isNotEmpty) ...[
              Text(
                'اختر الجودة:',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonFormField<VideoFormat>(
                  value: _selectedFormat,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: formats.map((f) {
                    String qualityLabel = f.quality;
                    if (qualityLabel.contains('p')) {
                      qualityLabel = qualityLabel;
                    } else if (qualityLabel == 'best') {
                      qualityLabel = 'أفضل جودة';
                    } else {
                      qualityLabel = '$qualityLabel - ${f.container.toUpperCase()}';
                    }

                    return DropdownMenuItem(
                      value: f,
                      child: Row(
                        children: [
                          Icon(
                            _getQualityIcon(f.quality),
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(qualityLabel),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedFormat = val;
                    });
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Download Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  final provider = Provider.of<DownloadProvider>(context, listen: false);
                  Navigator.of(context).pop();
                  
                  if (_downloadAsAudio) {
                    provider.downloadAudio(url: widget.videoUrl);
                  } else if (_selectedFormat != null) {
                    provider.downloadVideo(
                      url: widget.videoUrl,
                      qualityOrItag: _selectedFormat!.itag,
                    );
                  }
                },
                icon: Icon(
                  _downloadAsAudio
                      ? Icons.music_note_rounded
                      : Icons.download_rounded,
                ),
                label: Text(
                  _downloadAsAudio ? 'تحميل الصوت' : 'تحميل الفيديو',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getQualityIcon(String quality) {
    if (quality.contains('4K') || quality.contains('2160')) {
      return Icons.high_quality_rounded;
    } else if (quality.contains('1080')) {
      return Icons.hd_rounded;
    } else if (quality.contains('720')) {
      return Icons.video_settings_rounded;
    } else {
      return Icons.video_library_rounded;
    }
  }
}

