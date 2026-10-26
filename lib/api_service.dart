import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
   // ----------------------------------------------------------
  // WHERE THE SERVER IS
  // useRealPhones = true  -> real phones use your computer's address
  // useRealPhones = false -> the emulator uses its special address
  // If your computer's Wi-Fi address changes, change computerAddress
  // (find it in the Flask terminal: "Running on http://192...").
  // ----------------------------------------------------------
  static const bool useRealPhones = false;
  static const String computerAddress = '192.168.88.16';

  static const String baseUrl = useRealPhones
      ? 'http://$computerAddress:5000'
      : 'http://10.0.2.2:5000';
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
   
  // Retrieves the patient's latest details directly from the backend database.
  // The patientId is the ID returned by the backend during registration.
  static Future<Map<String, dynamic>> getPatientDetails({
    required int patientId,
  }) async {
    try {
      // Send a GET request to the patient details endpoint.
      final response = await http.get(
        Uri.parse('$baseUrl/api/patients/$patientId'),
        headers: {
          'Accept': 'application/json',
        },
      );

      // Decode the backend's JSON response.
      final data = jsonDecode(response.body);

      // Return the patient data when the request succeeds.
      if (response.statusCode == 200 &&
          data['status'] == 'success') {
        return {
          'success': true,
          'patient': data['patient'],
        };
      }

      // Return the backend error if the patient was not found.
      return {
        'success': false,
        'message': data is Map
            ? data['message'] ?? 'Unable to retrieve patient details'
            : 'Unable to retrieve patient details',
      };
    } catch (e) {
      // Handle network errors or invalid JSON responses.
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

static Future<Map<String, dynamic>> updateEmergencyContact({
  required int patientId,
  required String contactName,
  required String contactPhone,
}) async {
  try {
    final response = await http.put(
      Uri.parse(
        '$baseUrl/api/patients/$patientId/emergency-contact',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'emergency_contact_name': contactName.trim(),
        'emergency_contact_phone': contactPhone.trim(),
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 &&
        data['status'] == 'success') {
      return {
        'success': true,
        'message': data['message'] ?? 'Emergency contact updated successfully',
      };
    }

    return {
      'success': false,
      'message': data is Map
          ? data['message'] ?? 'Unable to update emergency contact'
          : 'Unable to update emergency contact',
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
static Future<Map<String, dynamic>> registerDoctor({
  required String fullName,
  required String phone,
  required String registrationNumber,
  required String qualification,
  required int specializationId,
  required int experienceYears,
  int? hospitalId,
}) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/doctors/register'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'full_name': fullName,
        'phone': phone,
        'registration_number': registrationNumber,
        'qualification': qualification,
        'specialization_id': specializationId,
        'experience_years': experienceYears,
        if (hospitalId != null) 'hospital_id': hospitalId,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return data;
    }

    return {
      'status': 'error',
      'message': data['message'] ?? 'Doctor registration failed',
    };
  } catch (e) {
    return {
      'status': 'error',
      'message': 'Connection error: $e',
    };
  }
}
static Future<Map<String, dynamic>> checkDoctorPhone({
  required String phone,
}) async {
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/api/doctors/login'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'phone': phone,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data;
    }

    return {
      'status': 'error',
      'message': data['message'] ?? 'Doctor account not found',
    };
  } catch (e) {
    return {
      'status': 'error',
      'message': 'Connection error: $e',
    };
  }
}
static Future<Map<String, dynamic>> getDoctorAppointments(
  int doctorId,
) async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/doctors/$doctorId/appointments'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data;
    }

    return {
      'status': 'error',
      'message': data['message'] ?? 'Failed to load appointments',
    };
  } catch (e) {
    return {
      'status': 'error',
      'message': 'Connection error: $e',
    };
  }
}
static Future<Map<String, dynamic>> completeDoctorAppointment({
  required int doctorId,
  required int appointmentId,
}) async {
  try {
    final response = await http.put(
      Uri.parse(
        '$baseUrl/api/doctors/$doctorId/appointments/$appointmentId/complete',
      ),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data;
    }

    return {
      'status': 'error',
      'message': data['message'] ?? 'Failed to complete appointment.',
    };
  } catch (e) {
    return {
      'status': 'error',
      'message': 'Connection error: $e',
    };
  }
}

static Future<Map<String, dynamic>> saveConsultation({
  required int appointmentId,
  required String consultationType,
  required String chiefComplaint,
  required String diagnosis,
  required String notes,
  required String advice,
  String? followUpDate,
}) async {
  try {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/api/doctors/appointments/$appointmentId/consultation',
      ),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'consultation_type': consultationType,
        'chief_complaint': chiefComplaint,
        'diagnosis': diagnosis,
        'notes': notes,
        'advice': advice,
        'follow_up_date': followUpDate,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      return data;
    }

    return {
      'status': 'error',
      'message': data['message'] ?? 'Failed to save consultation.',
    };
  } catch (e) {
    return {
      'status': 'error',
      'message': 'Connection error: $e',
    };
  }
}
static Future<List<Map<String, dynamic>>> getDoctorConsultations(
  int doctorId,
) async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/doctors/$doctorId/consultations'),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['status'] == 'success') {
      return List<Map<String, dynamic>>.from(
        data['consultations'],
      );
    }

    throw Exception(data['message'] ?? 'Failed to load consultations.');
  } catch (e) {
    throw Exception('Unable to load consultations: $e');
  }
}

static Future<Map<String, dynamic>> getDoctorConsultationHistory(
  int doctorId,
) async {
  try {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/api/doctors/$doctorId/consultation-history',
      ),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return data;
    } else {
      return {
        'status': 'error',
        'message': data['message'] ?? 'Failed to load consultation history',
      };
    }
  } catch (e) {
    return {
      'status': 'error',
      'message': e.toString(),
    };
  }
}

  // Generate Agora video call token
  static Future<Map<String, dynamic>> getAgoraVideoToken({
    required int appointmentId,
    required int participantId,
    required String participantRole,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/appointments/$appointmentId/video-token',
      ).replace(
        queryParameters: {
          'participant_id': participantId.toString(),
          'participant_role': participantRole,
        },
      );

      final response = await http.get(uri);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          data['status'] == 'success') {
        return {
          'success': true,
          ...data,
        };
      }

      return {
        'success': false,
        'message': data['message'] ??
            'Failed to generate Agora video token',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }
  
  // Check whether a patient account exists
  static Future<Map<String, dynamic>> checkPatientPhone({
    required String phone,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/patients/check-phone',
      ).replace(
        queryParameters: {'phone': phone},
      );

      final response = await http.get(uri);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          data['status'] == 'success') {
        return {
          'status': 'success',
          'patient': data['patient'],
          'message': data['message'],
        };
      }

      return {
        'status': 'error',
        'message': data['message'] ??
            'Patient account not found.',
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': 'Connection error: $e',
      };
    }
  }
    // ============================================================
  // SAVE PRESCRIPTION
  // Sends a prescription written by the doctor to the Flask server.
  // ============================================================
  static Future<Map<String, dynamic>> savePrescription({
    required int doctorId,
    required int consultationId,
    required List<Map<String, String>> medicines,
    String? notes,
  }) async {
    try {
      // POST request to the new /api/prescriptions route
      final response = await http.post(
        Uri.parse('$baseUrl/api/prescriptions'),
        headers: {
          'Content-Type': 'application/json',
        },
        // Convert our Dart data into JSON text for the server
        body: jsonEncode({
          'doctor_id': doctorId,
          'consultation_id': consultationId,
          'notes': notes,
          'medicines': medicines,
        }),
      );

      // Convert the server's JSON reply back into a Dart map
      final data = jsonDecode(response.body);

      // 201 means the server created the prescription
      if (response.statusCode == 201) {
        return {
          'success': true,
          ...data,
        };
      }

      // Any other status means the server refused or failed
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to save prescription',
      };
    } catch (e) {
      // No internet, server not running, and similar problems
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  // ============================================================
  // GET PATIENT PRESCRIPTIONS
  // Loads every prescription that belongs to one patient.
  // ============================================================
  static Future<List<Map<String, dynamic>>> getPatientPrescriptions(
    int patientId,
  ) async {
    try {
      // GET request to the new /api/patients/<id>/prescriptions route
      final response = await http.get(
        Uri.parse('$baseUrl/api/patients/$patientId/prescriptions'),
      );

      final data = jsonDecode(response.body);

      // 200 means the list was loaded successfully
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          data['prescriptions'],
        );
      }

      // Server replied with an error message
      throw Exception(
        data['message'] ?? 'Failed to load prescriptions',
      );
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }
  
  // ============================================================
  // GET DOCTOR PRESCRIPTIONS
  // Loads every prescription written by one doctor.
  // ============================================================
  static Future<List<Map<String, dynamic>>> getDoctorPrescriptions(
    int doctorId,
  ) async {
    try {
      // GET request to the /api/doctors/<id>/prescriptions route
      final response = await http.get(
        Uri.parse('$baseUrl/api/doctors/$doctorId/prescriptions'),
      );

      // Convert the server's JSON reply into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the list was loaded successfully
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          data['prescriptions'],
        );
      }

      // The server replied with an error message
      throw Exception(
        data['message'] ?? 'Failed to load prescriptions',
      );
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }
  
  // ============================================================
  // PLACE MEDICINE ORDER
  // Orders the medicines of one prescription.
  // ============================================================
  static Future<Map<String, dynamic>> placeMedicineOrder({
    required int patientId,
    required int prescriptionId,
    required String deliveryAddress,
    required String paymentMethod, // COD, Card, UPI or Wallet
  }) async {
    try {
      // POST request to the /api/medicine-orders route
      final response = await http.post(
        Uri.parse('$baseUrl/api/medicine-orders'),
        headers: {
          'Content-Type': 'application/json',
        },
        // Convert our Dart data into JSON text for the server
        body: jsonEncode({
          'patient_id': patientId,
          'prescription_id': prescriptionId,
          'delivery_address': deliveryAddress,
          'payment_method': paymentMethod,
        }),
      );

      // Convert the server's JSON reply back into a Dart map
      final data = jsonDecode(response.body);

      // 201 means the server created the order
      if (response.statusCode == 201) {
        return {
          'success': true,
          ...data,
        };
      }

      // Any other status means the server refused or failed
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to place the order',
      };
    } catch (e) {
      // No internet, server not running, and similar problems
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }
  
  // ============================================================
  // GET PATIENT MEDICINE ORDERS
  // Loads every medicine order a patient has placed.
  // Used for "Your Orders" and "Track Your Order".
  // ============================================================
  static Future<List<Map<String, dynamic>>> getPatientMedicineOrders(
    int patientId,
  ) async {
    try {
      // GET request to the /api/patients/<id>/medicine-orders route
      final response = await http.get(
        Uri.parse('$baseUrl/api/patients/$patientId/medicine-orders'),
      );

      // Convert the server's JSON reply into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the list was loaded successfully
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          data['orders'],
        );
      }

      // The server replied with an error message
      throw Exception(
        data['message'] ?? 'Failed to load orders',
      );
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }
 
  // ============================================================
  // GET DOCTOR SIGNATURE
  // Returns the saved signature (as base64 text), or null if the
  // doctor has not drawn one yet.
  // ============================================================
  static Future<String?> getDoctorSignature(int doctorId) async {
    try {
      // GET request to the /api/doctors/<id>/signature route
      final response = await http.get(
        Uri.parse('$baseUrl/api/doctors/$doctorId/signature'),
      );

      // Convert the server's JSON reply into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the request worked (the signature may still be empty)
      if (response.statusCode == 200) {
        final signature = data['signature'];

        // Treat an empty signature the same as no signature
        if (signature == null || signature.toString().isEmpty) {
          return null;
        }

        return signature.toString();
      }

      // The server replied with an error message
      throw Exception(
        data['message'] ?? 'Failed to load signature',
      );
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  // ============================================================
  // SAVE DOCTOR SIGNATURE
  // Sends the drawn signature (as base64 text) to the server.
  // ============================================================
  static Future<Map<String, dynamic>> saveDoctorSignature({
    required int doctorId,
    required String signatureBase64,
  }) async {
    try {
      // PUT request to the /api/doctors/<id>/signature route
      final response = await http.put(
        Uri.parse('$baseUrl/api/doctors/$doctorId/signature'),
        headers: {
          'Content-Type': 'application/json',
        },
        // Convert our Dart data into JSON text for the server
        body: jsonEncode({
          'signature': signatureBase64,
        }),
      );

      // Convert the server's JSON reply back into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the signature was saved
      if (response.statusCode == 200) {
        return {
          'success': true,
          ...data,
        };
      }

      // Any other status means the server refused or failed
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to save signature',
      };
    } catch (e) {
      // No internet, server not running, and similar problems
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  } 
  
  // ============================================================
  // GET PATIENT HEALTH RECORD
  // Loads the patient's consultation history and saved records
  // (allergies, conditions, immunizations, surgeries).
  // ============================================================
  static Future<Map<String, dynamic>> getPatientHealthRecord(
    int patientId,
  ) async {
    try {
      // GET request to the /api/patients/<id>/health-record route
      final response = await http.get(
        Uri.parse('$baseUrl/api/patients/$patientId/health-record'),
      );

      // Convert the server's JSON reply into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the record was loaded successfully
      if (response.statusCode == 200) {
        return data;
      }

      // The server replied with an error message
      throw Exception(
        data['message'] ?? 'Failed to load health record',
      );
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  // ============================================================
  // ADD MEDICAL RECORD
  // Saves one allergy, condition, immunization, surgery or other note.
  // ============================================================
  static Future<Map<String, dynamic>> addMedicalRecord({
    required int patientId,
    required String recordType, // Allergy, Condition, Immunization, Surgery, Other
    required String description,
    String? recordDate, // Optional, like 2026-10-22
  }) async {
    try {
      // POST request to the /api/patients/<id>/medical-records route
      final response = await http.post(
        Uri.parse('$baseUrl/api/patients/$patientId/medical-records'),
        headers: {
          'Content-Type': 'application/json',
        },
        // Convert our Dart data into JSON text for the server
        body: jsonEncode({
          'record_type': recordType,
          'description': description,
          'record_date': recordDate,
        }),
      );

      // Convert the server's JSON reply back into a Dart map
      final data = jsonDecode(response.body);

      // 201 means the record was created
      if (response.statusCode == 201) {
        return {
          'success': true,
          ...data,
        };
      }

      // Any other status means the server refused or failed
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to add the record',
      };
    } catch (e) {
      // No internet, server not running, and similar problems
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }

  // ============================================================
  // DELETE MEDICAL RECORD
  // Removes one saved record of the patient.
  // ============================================================
  static Future<Map<String, dynamic>> deleteMedicalRecord({
    required int patientId,
    required int recordId,
  }) async {
    try {
      // DELETE request to the /api/patients/<id>/medical-records/<id> route
      final response = await http.delete(
        Uri.parse(
          '$baseUrl/api/patients/$patientId/medical-records/$recordId',
        ),
      );

      // Convert the server's JSON reply back into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the record was deleted
      if (response.statusCode == 200) {
        return {
          'success': true,
          ...data,
        };
      }

      // Any other status means the server refused or failed
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to delete the record',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }
  
  // ============================================================
  // GET DOCTOR PATIENTS
  // Loads the patients who have an appointment with this doctor.
  // ============================================================
  static Future<List<Map<String, dynamic>>> getDoctorPatients(
    int doctorId,
  ) async {
    try {
      // GET request to the /api/doctors/<id>/patients route
      final response = await http.get(
        Uri.parse('$baseUrl/api/doctors/$doctorId/patients'),
      );

      // Convert the server's JSON reply into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the list was loaded successfully
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          data['patients'],
        );
      }

      // The server replied with an error message
      throw Exception(
        data['message'] ?? 'Failed to load patients',
      );
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  // ============================================================
  // GET PATIENT RECORD FOR DOCTOR
  // Loads one patient's profile, consultations and saved notes.
  // The server refuses if the doctor has no appointment with them.
  // ============================================================
  static Future<Map<String, dynamic>> getPatientRecordForDoctor({
    required int doctorId,
    required int patientId,
  }) async {
    try {
      // GET request to the /api/doctors/<id>/patients/<id>/record route
      final response = await http.get(
        Uri.parse(
          '$baseUrl/api/doctors/$doctorId/patients/$patientId/record',
        ),
      );

      // Convert the server's JSON reply into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the record was loaded successfully
      if (response.statusCode == 200) {
        return data;
      }

      // The server replied with an error message
      throw Exception(
        data['message'] ?? 'Failed to load the patient record',
      );
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }
  
  // ============================================================
  // GET PENDING NOTIFICATIONS
  // Asks the server whether the doctor has started a consultation
  // for this patient (unread notices from the last 30 minutes).
  // ============================================================
  static Future<List<Map<String, dynamic>>> getPendingNotifications(
    int patientId,
  ) async {
    try {
      // GET request to the .../notifications/pending route
      final response = await http.get(
        Uri.parse('$baseUrl/api/patients/$patientId/notifications/pending'),
      );

      // Convert the server's JSON reply into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the list was loaded successfully
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(
          data['notifications'],
        );
      }

      // The server replied with an error message
      throw Exception(
        data['message'] ?? 'Failed to load notifications',
      );
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  // ============================================================
  // MARK NOTIFICATION AS READ
  // So the same notice does not pop up again.
  // ============================================================
  static Future<void> markNotificationRead({
    required int patientId,
    required int notificationId,
  }) async {
    try {
      // PUT request to the .../notifications/<id>/read route
      await http.put(
        Uri.parse(
          '$baseUrl/api/patients/$patientId/notifications/$notificationId/read',
        ),
      );
    } catch (e) {
      // If this fails, the notice may show again later.
      // That is not serious, so we only print it.
      print('Could not mark notification as read: $e');
    }
  }
  
  // ============================================================
  // SAVE DEVICE TOKEN
  // Tells the server which phone belongs to this patient, so the
  // server can send push notifications to it.
  // ============================================================
  static Future<void> saveDeviceToken({
    required int patientId,
    required String token, // The phone's Firebase token
  }) async {
    try {
      // POST request to the .../device-token route
      await http.post(
        Uri.parse('$baseUrl/api/patients/$patientId/device-token'),
        headers: {
          'Content-Type': 'application/json',
        },
        // Convert our Dart data into JSON text for the server
        body: jsonEncode({
          'token': token,
        }),
      );
    } catch (e) {
      // If this fails, the push will not arrive, but the app still works.
      // We try again the next time the patient opens the home screen.
      print('Could not save device token: $e');
    }
  }
  
  // ============================================================
  // SAVE DOCTOR DEVICE TOKEN
  // Tells the server which phone belongs to this doctor, so the
  // server can send push notifications to it.
  // ============================================================
  static Future<void> saveDoctorDeviceToken({
    required int doctorId,
    required String token, // The phone's Firebase token
  }) async {
    try {
      // POST request to the .../doctors/<id>/device-token route
      await http.post(
        Uri.parse('$baseUrl/api/doctors/$doctorId/device-token'),
        headers: {
          'Content-Type': 'application/json',
        },
        // Convert our Dart data into JSON text for the server
        body: jsonEncode({
          'token': token,
        }),
      );
    } catch (e) {
      // If this fails, the push will not arrive, but the app still works.
      // We try again the next time the doctor opens the app.
      print('Could not save doctor device token: $e');
    }
  }

  // ============================================================
  // DELETE DEVICE TOKEN
  // Used when someone logs out, so the phone stops receiving
  // that person's notifications.
  // ============================================================
  static Future<void> deleteDeviceToken(String token) async {
    try {
      // DELETE request to the /api/device-token route
      await http.delete(
        Uri.parse('$baseUrl/api/device-token'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token': token,
        }),
      );
    } catch (e) {
      print('Could not delete device token: $e');
    }
  }
  
  // ============================================================
  // RESPOND TO APPOINTMENT
  // The doctor accepts or rejects a booking that is waiting.
  // The patient is notified by the server.
  // ============================================================
  static Future<Map<String, dynamic>> respondToAppointment({
    required int doctorId,
    required int appointmentId,
    required bool accept, // true = accept, false = reject
  }) async {
    try {
      // PUT request to the .../appointments/<id>/respond route
      final response = await http.put(
        Uri.parse(
          '$baseUrl/api/doctors/$doctorId/appointments/$appointmentId/respond',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        // Convert our Dart data into JSON text for the server
        body: jsonEncode({
          'decision': accept ? 'accept' : 'reject',
        }),
      );

      // Convert the server's JSON reply back into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the answer was saved
      if (response.statusCode == 200) {
        return {
          'success': true,
          ...data,
        };
      }

      // Any other status means the server refused or failed
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to answer the appointment',
      };
    } catch (e) {
      // No internet, server not running, and similar problems
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }
  
  // ============================================================
  // GET FREE SLOTS
  // Loads the free time slots of a doctor on one date. The server
  // hides slots that are booked or already in the past, and days
  // when the doctor does not work.
  // ============================================================
  static Future<Map<String, dynamic>> getFreeSlots({
    required int doctorId,
    required String date, // Like 2026-10-26
  }) async {
    try {
      // GET request to the .../slots?date=... route
      final uri = Uri.parse('$baseUrl/api/doctors/$doctorId/slots')
          .replace(queryParameters: {'date': date});

      final response = await http.get(uri);

      // Convert the server's JSON reply into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the slots were loaded (the list can be empty)
      if (response.statusCode == 200) {
        return {
          'success': true,
          'slots': List<String>.from(data['slots'] ?? []),
          'message': (data['message'] ?? '').toString(),
        };
      }

      // The server replied with an error message
      return {
        'success': false,
        'slots': <String>[],
        'message': data['message'] ?? 'Failed to load the time slots',
      };
    } catch (e) {
      // No internet, server not running, and similar problems
      return {
        'success': false,
        'slots': <String>[],
        'message': 'Connection error: $e',
      };
    }
  }

  // ============================================================
  // GET DOCTOR SCHEDULE
  // Loads the doctor's saved working days, hours and days off.
  // Returns null if the doctor has not saved a schedule yet.
  // ============================================================
  static Future<Map<String, dynamic>?> getDoctorSchedule(
    int doctorId,
  ) async {
    try {
      // GET request to the .../schedule route
      final response = await http.get(
        Uri.parse('$baseUrl/api/doctors/$doctorId/schedule'),
      );

      // Convert the server's JSON reply into a Dart map
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // "schedule" is null when nothing has been saved yet.
        // We also pass on the doctor's "available" switch.
        return {
          'schedule': data['schedule'] == null
              ? null
              : Map<String, dynamic>.from(data['schedule']),
          'is_available': data['is_available'] != false,
        };
      }

      // The server replied with an error message
      throw Exception(
        data['message'] ?? 'Failed to load the schedule',
      );
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  // ============================================================
  // SAVE DOCTOR SCHEDULE
  // Saves the doctor's working days, hours, slot length and days off.
  // ============================================================
  static Future<Map<String, dynamic>> saveDoctorSchedule({
    required int doctorId,
    required List<int> workingDays, // 1 = Monday ... 7 = Sunday
    required String startTime, // Like 09:00
    required String endTime, // Like 17:00
    required int slotMinutes, // Like 30
    required List<String> daysOff, // Like 2026-12-25
    bool isAvailable = true, // The "available for consultations" switch
  }) async {
    try {
      // PUT request to the .../schedule route
      final response = await http.put(
        Uri.parse('$baseUrl/api/doctors/$doctorId/schedule'),
        headers: {
          'Content-Type': 'application/json',
        },
        // Convert our Dart data into JSON text for the server
        body: jsonEncode({
          'working_days': workingDays,
          'start_time': startTime,
          'end_time': endTime,
          'slot_minutes': slotMinutes,
          'days_off': daysOff,
          'is_available': isAvailable,
        }),
      );

      // Convert the server's JSON reply back into a Dart map
      final data = jsonDecode(response.body);

      // 200 means the schedule was saved
      if (response.statusCode == 200) {
        return {
          'success': true,
          ...data,
        };
      }

      // Any other status means the server refused or failed
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to save the schedule',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Connection error: $e',
      };
    }
  }
}