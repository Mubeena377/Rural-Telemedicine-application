import 'package:flutter/material.dart';
import 'app_language.dart'; // appLanguage: the language the user chose

// ============================================================
// APP POPUP
// One popup used everywhere instead of the message at the bottom.
// It has 4 looks: error (red), warning (orange), success (green)
// and info (blue). The OK button follows the chosen language.
//
// Use it like this:
//   await showAppPopup(
//     context,
//     message: 'Wrong password. Please try again.',
//     type: PopupType.error,
//   );
// ============================================================

// The 4 kinds of popup
enum PopupType { error, warning, success, info }

// The word on the button, in the chosen language
const Map<String, String> _okText = {
  'en_IN': 'OK',
  'hi_IN': 'ठीक है',
  'kn_IN': 'ಸರಿ',
  'ta_IN': 'சரி',
  'te_IN': 'సరే',
  'ml_IN': 'ശരി',
  'mr_IN': 'ठीक आहे',
  'bn_IN': 'ঠিক আছে',
};

// A short default title for each kind, in the chosen language
const Map<PopupType, Map<String, String>> _defaultTitles = {
  PopupType.error: {
    'en_IN': 'Something went wrong',
    'hi_IN': 'कुछ गड़बड़ हो गई',
    'kn_IN': 'ಏನೋ ತಪ್ಪಾಗಿದೆ',
    'ta_IN': 'ஏதோ தவறு நடந்துவிட்டது',
    'te_IN': 'ఏదో తప్పు జరిగింది',
    'ml_IN': 'എന്തോ കുഴപ്പം സംഭവിച്ചു',
    'mr_IN': 'काहीतरी चुकले',
    'bn_IN': 'কিছু একটা ভুল হয়েছে',
  },
  PopupType.warning: {
    'en_IN': 'Please check',
    'hi_IN': 'कृपया जाँच लें',
    'kn_IN': 'ದಯವಿಟ್ಟು ಪರಿಶೀಲಿಸಿ',
    'ta_IN': 'தயவுசெய்து சரிபாருங்கள்',
    'te_IN': 'దయచేసి చూడండి',
    'ml_IN': 'ദയവായി പരിശോധിക്കുക',
    'mr_IN': 'कृपया तपासा',
    'bn_IN': 'অনুগ্রহ করে দেখে নিন',
  },
  PopupType.success: {
    'en_IN': 'Done',
    'hi_IN': 'हो गया',
    'kn_IN': 'ಆಯಿತು',
    'ta_IN': 'முடிந்தது',
    'te_IN': 'అయింది',
    'ml_IN': 'കഴിഞ്ഞു',
    'mr_IN': 'झाले',
    'bn_IN': 'হয়ে গেছে',
  },
  PopupType.info: {
    'en_IN': 'Information',
    'hi_IN': 'जानकारी',
    'kn_IN': 'ಮಾಹಿತಿ',
    'ta_IN': 'தகவல்',
    'te_IN': 'సమాచారం',
    'ml_IN': 'വിവരം',
    'mr_IN': 'माहिती',
    'bn_IN': 'তথ্য',
  },
};

// Picks the right icon and colour for each kind
IconData _iconFor(PopupType type) {
  switch (type) {
    case PopupType.error:
      return Icons.error_outline_rounded;
    case PopupType.warning:
      return Icons.warning_amber_rounded;
    case PopupType.success:
      return Icons.check_circle_outline_rounded;
    case PopupType.info:
      return Icons.info_outline_rounded;
  }
}

Color _colorFor(PopupType type) {
  switch (type) {
    case PopupType.error:
      return Colors.red;
    case PopupType.warning:
      return Colors.orange;
    case PopupType.success:
      return Colors.green;
    case PopupType.info:
      return const Color(0xFF3F6FA8);
  }
}

// Shows the popup and waits until the person taps OK.
//   message  - the text to show (already translated, if needed)
//   title    - optional; a short default title is used if left out
//   type     - error, warning, success or info
Future<void> showAppPopup(
  BuildContext context, {
  required String message,
  String? title,
  PopupType type = PopupType.error,
}) async {
  // If the screen was closed while we were waiting, do nothing
  if (!context.mounted) return;

  final language = appLanguage.value;
  final color = _colorFor(type);

  // The title: the one given, or the default for this kind
  final shownTitle = title ??
      _defaultTitles[type]![language] ??
      _defaultTitles[type]!['en_IN']!;

  await showDialog<void>(
    context: context,
    // A tap outside the popup does not close it, so it is not missed
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The big round icon at the top
            CircleAvatar(
              radius: 32,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(_iconFor(type), color: color, size: 38),
            ),
            const SizedBox(height: 16),

            // The title
            Text(
              shownTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 10),

            // The message
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _okText[language] ?? 'OK',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}