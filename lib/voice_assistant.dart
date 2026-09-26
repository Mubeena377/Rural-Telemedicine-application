import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceAssistant {
  final stt.SpeechToText _speech = stt.SpeechToText();

  Future<bool> initialize() async {
    return await _speech.initialize();
  }

  Future<void> listen({
  required Function(String command) onResult,
}) async {
  await _speech.listen(
    onResult: (result) {
      print('VOICE RESULT: ${result.recognizedWords}');
      print('FINAL RESULT: ${result.finalResult}');

      if (result.recognizedWords.isNotEmpty) {
        onResult(result.recognizedWords);
      }
    },
  );
}

  Future<void> stop() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}