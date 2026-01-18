import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _keyDefaultQuality = 'default_quality';
  static const String _keyDownloadPath = 'download_path';
  static const String _keyDarkMode = 'dark_mode';
  static const String _keyAutoDetectLinks = 'auto_detect_links';

  String _defaultQuality = 'best';
  String? _downloadPath;
  bool _darkMode = false;
  bool _autoDetectLinks = true;

  String get defaultQuality => _defaultQuality;
  String? get downloadPath => _downloadPath;
  bool get darkMode => _darkMode;
  bool get autoDetectLinks => _autoDetectLinks;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _defaultQuality = prefs.getString(_keyDefaultQuality) ?? 'best';
    _downloadPath = prefs.getString(_keyDownloadPath);
    _darkMode = prefs.getBool(_keyDarkMode) ?? false;
    _autoDetectLinks = prefs.getBool(_keyAutoDetectLinks) ?? true;
    notifyListeners();
  }

  Future<void> setDefaultQuality(String quality) async {
    _defaultQuality = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultQuality, quality);
    notifyListeners();
  }

  Future<void> setDownloadPath(String? path) async {
    _downloadPath = path;
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await prefs.setString(_keyDownloadPath, path);
    } else {
      await prefs.remove(_keyDownloadPath);
    }
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, value);
    notifyListeners();
  }

  Future<void> setAutoDetectLinks(bool value) async {
    _autoDetectLinks = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoDetectLinks, value);
    notifyListeners();
  }
}

