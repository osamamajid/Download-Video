import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class VideoInfo {
  final String title;
  final String? thumbnail;
  final int? durationSeconds;
  final List<VideoFormat> formats;

  VideoInfo({
    required this.title,
    required this.thumbnail,
    required this.durationSeconds,
    required this.formats,
  });
}

class VideoFormat {
  final String quality;
  final String container;
  final bool hasVideo;
  final bool hasAudio;
  final String itag;

  VideoFormat({
    required this.quality,
    required this.container,
    required this.hasVideo,
    required this.hasAudio,
    required this.itag,
  });
}

class DownloadedFile {
  final String name;
  final String type; // video | audio
  final int size;
  final DateTime date;
  final String urlPath;

  DownloadedFile({
    required this.name,
    required this.type,
    required this.size,
    required this.date,
    required this.urlPath,
  });
}

class DownloadProvider extends ChangeNotifier {
  // اكتشاف المنصة تلقائياً واستخدام الـ URL المناسب
  String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000'; // للويب
    } else if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000'; // لـ Android emulator
    } else if (Platform.isIOS) {
      return 'http://localhost:3000'; // لـ iOS simulator
    } else {
      return 'http://localhost:3000'; // للـ desktop
    }
    // على جهاز موبايل حقيقي غيّرها إلى IP جهاز الكمبيوتر على نفس الشبكة
    // مثال: 'http://192.168.1.10:3000'
  }

  bool loadingInfo = false;
  bool downloading = false;
  double progress = 0;
  String? error;

  VideoInfo? currentVideo;
  List<DownloadedFile> files = [];

  Future<void> _ensurePermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('تم رفض صلاحية التخزين');
      }
    }
  }

  Future<void> fetchVideoInfo(String url) async {
    error = null;
    loadingInfo = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/video/info'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      );

      if (response.statusCode != 200) {
        try {
          final data = jsonDecode(response.body);
          throw Exception(data['error'] ?? 'فشل في جلب معلومات الفيديو');
        } catch (e) {
          throw Exception('فشل في جلب معلومات الفيديو');
        }
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final formatsJson = (data['formats'] as List?) ?? [];

      currentVideo = VideoInfo(
        title: data['title'] ?? 'بدون عنوان',
        thumbnail: data['thumbnail'] as String?,
        durationSeconds: int.tryParse('${data['duration']}'),
        formats: formatsJson
            .map(
              (f) => VideoFormat(
                quality: '${f['quality']}',
                container: '${f['container'] ?? 'mp4'}',
                hasVideo: f['hasVideo'] == true,
                hasAudio: f['hasAudio'] == true,
                itag: '${f['itag']}',
              ),
            )
            .toList(),
      );
    } catch (e) {
      error = e.toString();
      currentVideo = null;
    } finally {
      loadingInfo = false;
      notifyListeners();
    }
  }

  Future<void> refreshFiles() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/files'));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final videos = (data['videos'] as List? ?? [])
          .map(
            (f) => DownloadedFile(
              name: f['name'],
              type: 'video',
              size: f['size'],
              date: DateTime.parse(f['date']),
              urlPath: f['path'],
            ),
          )
          .toList();

      final audios = (data['audios'] as List? ?? [])
          .map(
            (f) => DownloadedFile(
              name: f['name'],
              type: 'audio',
              size: f['size'],
              date: DateTime.parse(f['date']),
              urlPath: f['path'],
            ),
          )
          .toList();

      files = [...videos, ...audios]
        ..sort((a, b) => b.date.compareTo(a.date));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _pollProgress(
    String downloadId, {
    int retryCount = 0,
    int delaySeconds = 1,
    DateTime? startTime,
  }) async {
    startTime ??= DateTime.now();

    // التحقق من المهلة الزمنية (مثلاً 15 دقيقة كحد أقصى)
    if (DateTime.now().difference(startTime).inMinutes > 15) {
      downloading = false;
      error = 'انتهت المهلة الزمنية للتحميل';
      notifyListeners();
      return;
    }

    if (!downloading) return;

    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/progress/$downloadId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        progress = (data['progress'] ?? 0).toDouble() / 100.0;

        if (data['status'] == 'finished') {
          downloading = false;
          progress = 1.0;
          notifyListeners();
          await Future.delayed(const Duration(milliseconds: 500));
          progress = 0;
          await refreshFiles();
          notifyListeners();
          return;
        } else if (data['status'] == 'error') {
          downloading = false;
          error = data['error'] ?? 'حدث خطأ أثناء التحميل';
          notifyListeners();
          return;
        }

        notifyListeners();
        // نجاح الطلب، العودة لانتظار ثانية واحدة للمرة القادمة
        await Future.delayed(const Duration(seconds: 1));
        _pollProgress(downloadId, startTime: startTime);
      } else {
        // خطأ من الخادم (مثلاً 500 أو 404)
        if (retryCount > 10) {
          downloading = false;
          error = 'فشل الاتصال بالخادم بعد عدة محاولات';
          notifyListeners();
          return;
        }
        // التراجع الأسي (Exponential Backoff)
        int nextDelay = (delaySeconds * 2).clamp(1, 30);
        await Future.delayed(Duration(seconds: nextDelay));
        _pollProgress(downloadId,
            retryCount: retryCount + 1,
            delaySeconds: nextDelay,
            startTime: startTime);
      }
    } catch (e) {
      if (retryCount > 10) {
        downloading = false;
        error = 'خطأ في الشبكة: $e';
        notifyListeners();
        return;
      }
      int nextDelay = (delaySeconds * 2).clamp(1, 30);
      await Future.delayed(Duration(seconds: nextDelay));
      _pollProgress(downloadId,
          retryCount: retryCount + 1,
          delaySeconds: nextDelay,
          startTime: startTime);
    }
  }

  Future<void> downloadVideo({
    required String url,
    required String qualityOrItag,
  }) async {
    await _ensurePermissions();
    downloading = true;
    progress = 0;
    error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/video/download'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'url': url,
          'quality': qualityOrItag,
        }),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'فشل تحميل الفيديو');
      }

      final data = jsonDecode(response.body);
      final downloadId = data['downloadId'];
      if (downloadId != null) {
        _pollProgress(downloadId);
      } else {
        downloading = false;
        await refreshFiles();
        notifyListeners();
      }
    } catch (e) {
      error = e.toString();
      downloading = false;
      notifyListeners();
    }
  }

  Future<void> downloadAudio({required String url}) async {
    await _ensurePermissions();
    downloading = true;
    progress = 0;
    error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/audio/download'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'url': url,
        }),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'فشل تحميل الصوت');
      }

      final data = jsonDecode(response.body);
      final downloadId = data['downloadId'];
      if (downloadId != null) {
        _pollProgress(downloadId);
      } else {
        downloading = false;
        await refreshFiles();
        notifyListeners();
      }
    } catch (e) {
      error = e.toString();
      downloading = false;
      notifyListeners();
    }
  }

  Future<void> deleteFile(DownloadedFile file) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/files/${file.type}/${file.name}'),
      );
      if (response.statusCode == 200) {
        files.removeWhere((f) => f.name == file.name && f.type == file.type);
        notifyListeners();
      } else {
        try {
          final data = jsonDecode(response.body);
          error = data['error'] ?? 'فشل في حذف الملف';
        } catch (_) {
          error = 'فشل في حذف الملف';
        }
        notifyListeners();
      }
    } catch (e) {
      error = 'خطأ في الاتصال: $e';
      notifyListeners();
    }
  }

  Future<void> shareFile(DownloadedFile file) async {
    try {
      // نحمل الملف إلى مجلد مؤقت ثم نشاركه
      final dir = await getTemporaryDirectory();
      final localPath = '${dir.path}/${file.name}';

      final response =
          await http.get(Uri.parse('$baseUrl${file.urlPath}'));
      final localFile = File(localPath);
      await localFile.writeAsBytes(response.bodyBytes);

      await Share.shareXFiles([XFile(localFile.path)], text: file.name);
    } catch (_) {}
  }
}


