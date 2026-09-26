import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:5000';

  // Test Flask connection
  static Future<String> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/health'),
      );

      if (response.statusCode == 200) {
        return response.body;
      } else {
        return 'Server error: ${response.statusCode}';
      }
    } catch (e) {
      return 'Connection error: $e';
    }
  }

  // Register patient
  static Future<Map<String, dynamic>> registerPatient({
    required String fullName,
    required String dateOfBirth,
    required String gender,
    required String address,
    required String phone,
    required String emergencyContactName,
    required String emergencyContactPhone,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/patients'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'full_name': fullName,
          'date_of_birth': dateOfBirth,
          'gender': gender,
          'address': address,
          'phone': phone,
          'emergency_contact_name': emergencyContactName,
          'emergency_contact_phone': emergencyContactPhone,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          ...data,
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Registration failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  // Analyze triage
  static Future<Map<String, dynamic>> analyzeTriage({
    required int patientId,
    required String symptoms,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/triage'),
      );

      request.fields['patient_id'] = patientId.toString();
      request.fields['symptoms'] = symptoms;

      final streamedResponse = await request.send();

      final response = await http.Response.fromStream(
        streamedResponse,
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {
          'success': true,
          ...data,
        };
      }

      return {
        'success': false,
        'message': data['message'] ?? 'Triage analysis failed',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }
  static Future<Map<String, dynamic>> activateSOS({
  required int patientId,
  required double latitude,
  required double longitude,
}) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/sos'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'patient_id': patientId,
        'latitude': latitude,
        'longitude': longitude,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return {
        'success': true,
        ...data,
      };
    }

    return {
      'success': false,
      'message': data['message'] ?? 'SOS activation failed',
    };
  } catch (e) {
    return {
      'success': false,
      'message': 'Connection error: $e',
    };
  }
}
static Future<Map<String, dynamic>> cancelSOS({
  required int sosId,
}) async {
  try {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/sos/$sosId/cancel'),
      headers: {
        'Content-Type': 'application/json',
      },
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {
        'success': true,
        ...data,
      };
    }

    return {
      'success': false,
      'message': data['message'] ?? 'Failed to cancel SOS',
    };
  } catch (e) {
    return {
      'success': false,
      'message': 'Connection error: $e',
    };
  }
}
static Future<Map<String, dynamic>> updateSOSStatus({
  required int sosId,
  required String status,
}) async {
  try {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/sos/$sosId/status'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'status': status,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {
        'success': true,
        ...data,
      };
    }

    return {
      'success': false,
      'message': data['message'] ?? 'Failed to update SOS status',
    };
  } catch (e) {
    return {
      'success': false,
      'message': 'Connection error: $e',
    };
  }
}
static Future<List<Map<String, dynamic>>> getDoctors() async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/doctors'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(data['doctors']);
    }

    throw Exception(
      data['message'] ?? 'Failed to load doctors',
    );
  } catch (e) {
    throw Exception('Connection error: $e');
  }
}
static Future<Map<String, dynamic>> createAppointment({
  required int patientId,
  required int doctorId,
  required String appointmentDate,
  required String startTime,
  required String endTime,
  required String consultationMode,
  String? reasonForVisit,
}) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/appointments'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'patient_id': patientId,
        'doctor_id': doctorId,
        'appointment_date': appointmentDate,
        'start_time': startTime,
        'end_time': endTime,
        'consultation_mode': consultationMode,
        'reason_for_visit': reasonForVisit,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return {
        'success': true,
        ...data,
      };
    }

    return {
      'success': false,
      'message': data['message'] ??
          'Failed to create appointment',
    };
  } catch (e) {
    return {
      'success': false,
      'message': 'Connection error: $e',
    };
  }
}
static Future<List<Map<String, dynamic>>> getAppointments(
    int patientId) async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/appointments/$patientId'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(
        data['appointments'],
      );
    }

    throw Exception(
      data['message'] ?? 'Failed to load appointments',
    );
  } catch (e) {
    throw Exception('Connection error: $e');
  }
}
static Future<Map<String, dynamic>> cancelAppointment({
  required int appointmentId,
}) async {
  try {
    final response = await http.put(
      Uri.parse('$baseUrl/api/appointments/$appointmentId/cancel'),
      headers: {
        'Content-Type': 'application/json',
      },
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {
        'success': true,
        ...data,
      };
    }

    return {
      'success': false,
      'message': data['message'] ?? 'Failed to cancel appointment',
    };
  } catch (e) {
    return {
      'success': false,
      'message': 'Connection error: $e',
    };
  }
}
}