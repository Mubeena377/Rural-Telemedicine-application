import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// DOCTOR SESSION
// Remembers on the phone that a doctor is logged in, so the app
// can open the doctor dashboard directly next time.
// ============================================================

class DoctorSession {
  // Saves the doctor's details after login or registration
  static Future<void> save({
    required int doctorId,
    required String doctorName,
    required String doctorSpecialization,
    required String doctorQualification,
    required int doctorExperience,
    required String doctorAvailability,
  }) async {
    // SharedPreferences is the phone's small storage for settings
    final prefs = await SharedPreferences.getInstance();

    // This flag says "a doctor is logged in"
    await prefs.setBool('doctorLoggedIn', true);

    // The details the dashboard needs
    await prefs.setInt('doctorId', doctorId);
    await prefs.setString('doctorName', doctorName);
    await prefs.setString('doctorSpecialization', doctorSpecialization);
    await prefs.setString('doctorQualification', doctorQualification);
    await prefs.setInt('doctorExperience', doctorExperience);
    await prefs.setString('doctorAvailability', doctorAvailability);
  }

  // Reads the saved doctor. Returns null if no doctor is logged in.
  static Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();

    // No flag means nobody is logged in
    if (!(prefs.getBool('doctorLoggedIn') ?? false)) return null;

    // Without an ID we cannot open the dashboard
    final doctorId = prefs.getInt('doctorId');
    if (doctorId == null) return null;

    return {
      'doctorId': doctorId,
      'doctorName': prefs.getString('doctorName') ?? '',
      'doctorSpecialization': prefs.getString('doctorSpecialization') ?? '',
      'doctorQualification': prefs.getString('doctorQualification') ?? '',
      'doctorExperience': prefs.getInt('doctorExperience') ?? 0,
      'doctorAvailability': prefs.getString('doctorAvailability') ?? 'Y',
    };
  }

  // Forgets the doctor (used by the logout button)
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('doctorLoggedIn');
    await prefs.remove('doctorId');
    await prefs.remove('doctorName');
    await prefs.remove('doctorSpecialization');
    await prefs.remove('doctorQualification');
    await prefs.remove('doctorExperience');
    await prefs.remove('doctorAvailability');
  }
}