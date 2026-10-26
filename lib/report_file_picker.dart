import 'package:file_picker/file_picker.dart';

// ============================================================
// REPORT FILE PICKER
// Opens the phone's file chooser so the patient can pick a PDF
// or a picture. Gives back the file's path on the phone, or null
// if the patient closed the chooser without picking anything.
// ============================================================

Future<String?> pickReportFilePath() async {
  try {
    // Open the chooser, showing only PDF and picture files.
    // In this version the result is the list of chosen files itself.
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    // The patient closed the chooser without picking a file
    if (result.isEmpty) return null;

    // The path of the chosen file on the phone
    return result.first.path;
  } catch (e) {
    // Closing the chooser (or a problem inside it) counts as "nothing chosen"
    print('File picker closed or failed: $e');
    return null;
  }
}