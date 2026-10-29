import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted app-wide appearance. The entire MaterialApp is rebuilt on change,
/// including auth/wizard screens; not just the Account tab.
class DmAppearance extends ChangeNotifier {
  static final DmAppearance instance = DmAppearance._();
  DmAppearance._();
  bool dark = false;
  String language = 'en';
  bool largeText = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    dark = prefs.getBool('dm_dark_v9') ?? false;
    language = prefs.getString('dm_language_v9') ?? 'en';
    largeText = prefs.getBool('dm_large_text_v9') ?? false;
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    dark = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dm_dark_v9', value);
  }

  Future<void> setLanguage(String value) async {
    language = value == 'hi' ? 'hi' : 'en';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dm_language_v9', language);
  }

  Future<void> setLargeText(bool value) async {
    largeText = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dm_large_text_v9', value);
  }
}

String dmLocal(String english, String hindi) =>
    DmAppearance.instance.language == 'hi' ? hindi : english;
