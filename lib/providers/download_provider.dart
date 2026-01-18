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
        throw Exception('فشل في جلب معلومات الفيديو');
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
        throw Exception('فشل تحميل الفيديو');
      }

      await refreshFiles();
    } catch (e) {
      error = e.toString();
    } finally {
      downloading = false;
      progress = 0;
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
        throw Exception('فشل تحميل الصوت');
      }

      await refreshFiles();
    } catch (e) {
      error = e.toString();
    } finally {
      downloading = false;
      progress = 0;
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
      }
    } catch (_) {}
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


