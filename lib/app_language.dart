import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// APP LANGUAGE
// The language the patient or doctor chose (en_IN, hi_IN, kn_IN,
// ta_IN, te_IN, ml_IN, mr_IN or bn_IN). It lives in its own file so
// that every screen can read it without importing main.dart.
// The choice is now also saved on the phone, so it is remembered
// the next time the app opens.
// ============================================================

// The language the app is showing right now. Screens listen to this.
final ValueNotifier<String> appLanguage = ValueNotifier<String>('en_IN');

// The key name used to store the language on the phone.
const String _languageKey = 'app_language';

// The 8 languages the app supports. Used to ignore a bad saved value.
const List<String> supportedLanguageCodes = [
  'en_IN', 'hi_IN', 'kn_IN', 'ta_IN', 'te_IN', 'ml_IN', 'mr_IN', 'bn_IN',
];

String get selectedLanguage => appLanguage.value;

set selectedLanguage(String value) {
  appLanguage.value = value;
}

// Call this ONCE when the app starts, before runApp().
// It reads the saved language and then starts saving every change.
Future<void> loadSavedLanguage() async {
  try {
    // Open the phone's small storage.
    final prefs = await SharedPreferences.getInstance();

    // Read the saved language (null if the patient never chose one).
    final saved = prefs.getString(_languageKey);

    // Use it only if it is one of our 8 languages.
    if (saved != null && supportedLanguageCodes.contains(saved)) {
      appLanguage.value = saved;
    }

    // From now on, save the language every time it changes.
    appLanguage.addListener(() {
      prefs.setString(_languageKey, appLanguage.value);
    });
  } catch (e) {
    // If storage fails, the app still works. It just forgets the choice.
    debugPrint('Could not load saved language: $e');
  }
}