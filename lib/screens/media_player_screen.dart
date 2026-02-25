import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';

class MediaPlayerScreen extends StatefulWidget {
  final DownloadedFile file;

  const MediaPlayerScreen({super.key, required this.file});

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final provider = context.read<DownloadProvider>();
      final fileUrl = '${provider.baseUrl}${widget.file.urlPath}';

      _videoController = VideoPlayerController.networkUrl(Uri.parse(fileUrl));
      await _videoController!.initialize();

      if (widget.file.type == 'video') {
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: true,
          looping: false,
          aspectRatio: _videoController!.value.aspectRatio,
          allowFullScreen: true,
          allowMuting: true,
          showControls: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: Theme.of(context).colorScheme.primary,
            handleColor: Theme.of(context).colorScheme.primary,
            backgroundColor: Colors.grey,
            bufferedColor: Colors.grey.shade300,
          ),
        );
      } else {
        // For audio, we start playing automatically
        _videoController!.play();
        _videoController!.addListener(_onAudioControllerUpdate);
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'فشل في تحميل الملف: $e';
        });
      }
    }
  }

  void _onAudioControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withOpacity(0.1),
              Colors.black.withOpacity(0.9),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.file.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.share_rounded, color: Colors.white),
                      onPressed: () {
                        Provider.of<DownloadProvider>(context, listen: false)
                            .shareFile(widget.file);
                      },
                    ),
                  ],
                ),
              ),

              // Player
              Expanded(
                child: Center(
                  child: _error != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 64,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('رجوع'),
                            ),
                          ],
                        )
                      : !_isInitialized
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'جاري التحميل...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            )
                          : widget.file.type == 'video'
                              ? Chewie(controller: _chewieController!)
                              : _buildAudioPlayer(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioPlayer(ThemeData theme) {
    if (_videoController == null) return const SizedBox();

    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    final isPlaying = _videoController!.value.isPlaying;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Audio Art
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: isPlaying ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 500),
            builder: (context, value, child) {
              return Container(
                width: 200 + (value * 20),
                height: 200 + (value * 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.3 + (value * 0.2)),
                      blurRadius: 30 + (value * 10),
                      spreadRadius: 10 + (value * 5),
                    ),
                  ],
                ),
                child: Icon(
                  isPlaying ? Icons.music_note_rounded : Icons.pause_rounded,
                  size: 100,
                  color: Colors.white,
                ),
              );
            },
          ),
          const SizedBox(height: 48),

          // File Name
          Text(
            widget.file.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 32),

          // Progress Slider
          Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                ),
                child: Slider(
                  value: position.inMilliseconds.toDouble(),
                  max: duration.inMilliseconds.toDouble(),
                  onChanged: (value) {
                    _videoController!.seekTo(Duration(milliseconds: value.toInt()));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 32),
                onPressed: () {
                  final newPos = position - const Duration(seconds: 10);
                  _videoController!.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
                },
              ),
              const SizedBox(width: 24),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: theme.colorScheme.primary,
                    size: 40,
                  ),
                  onPressed: () {
                    if (isPlaying) {
                      _videoController!.pause();
                    } else {
                      _videoController!.play();
                    }
                  },
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 32),
                onPressed: () {
                  final newPos = position + const Duration(seconds: 10);
                  _videoController!.seekTo(newPos > duration ? duration : newPos);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}
