import 'app_language.dart';

// ============================================================
// TEXT FOR THE NEWER SCREENS
// Each screen keeps its own table of translations in its own file:
//   { 'English text': { 'hi_IN': '...', 'kn_IN': '...', ... } }
// "tt" finds the text in the chosen language. If a language is
// missing, the English text is shown, so nothing ever breaks.
// ============================================================

String tt(Map<String, Map<String, String>> table, String text) {
  return table[text]?[appLanguage.value] ?? text;
}