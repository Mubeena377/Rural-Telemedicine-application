import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_text.dart'; // gives us the tt() translation helper
import 'patient_details_texts.dart'; // the 8-language texts for this screen

// Short helper: translates one English text for this screen
String _t(String text) => tt(patientDetailsTexts, text);

class PatientDetailsScreen extends StatefulWidget {
  const PatientDetailsScreen({super.key});

  @override
  State<PatientDetailsScreen> createState() =>
      _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  // Stores the patient details returned by the backend database.
  Map<String, dynamic>? patient;

  // Controls the loading indicator.
  bool isLoading = true;

  // Stores an error message if the details cannot be loaded.
  String? errorMessage;

  @override
  void initState() {
    super.initState();

    // Load the patient's details when this screen opens.
    loadPatientDetails();
  }

  // Retrieves the patient ID saved after registration,
  // then fetches the latest details from the backend.
  Future<void> loadPatientDetails() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // The patient ID identifies the patient's database record.
      final patientId = prefs.getInt('patientId');

      if (patientId == null) {
        if (!mounted) return;
        setState(() {
          // Translated message (made on the phone, not by the server)
          errorMessage =
              _t('Patient ID not found. Please register or sign in again.');
          isLoading = false;
        });
        return;
      }

      // Fetch current patient information from the backend.
      final result = await ApiService.getPatientDetails(
        patientId: patientId,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          // Use the database response as the source of truth.
          patient = Map<String, dynamic>.from(result['patient']);
          isLoading = false;
        });
      } else {
        setState(() {
          // A message from the server stays English;
          // our own fallback message is translated.
          errorMessage =
              result['message'] ?? _t('Unable to load patient details.');
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage =
            _t('Something went wrong: {error}').replaceAll('{error}', '$e');
        isLoading = false;
      });
    }
  }

  // Shows a label and its corresponding database value.
  // "label" is already translated by the caller.
  Widget buildDetail(String label, dynamic value, IconData icon) {
    final displayValue =
        value == null || value.toString().trim().isEmpty
            ? _t('Not provided')
            : value.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.teal, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey.shade600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  displayValue,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The gender is saved in English (Male / Female / Other).
    // Here we only translate what is SHOWN. If the text is empty, keep it empty.
    final genderRaw = patient?['gender'];
    final genderShown = (genderRaw == null || genderRaw.toString().trim().isEmpty)
        ? null
        : _t(genderRaw.toString());

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      appBar: AppBar(
        title: Text(_t('My Details')),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          // Allows the user to refresh details from the database.
          IconButton(
            onPressed: isLoading ? null : loadPatientDetails,
            icon: const Icon(Icons.refresh),
            tooltip: _t('Refresh details'),
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_outlined,
                            size: 48,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            errorMessage!,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: loadPatientDetails,
                            icon: const Icon(Icons.refresh),
                            label: Text(_t('Try again')),
                          ),
                        ],
                      ),
                    ),
                  )
                : patient == null
                    ? Center(
                        child: Text(_t('No patient details available.')),
                      )
                    : RefreshIndicator(
                        onRefresh: loadPatientDetails,
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            // Profile heading uses the database name.
                            Container(
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.teal,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 30,
                                    backgroundColor: Colors.white,
                                    child: Icon(
                                      Icons.person,
                                      size: 34,
                                      color: Colors.teal,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          patient!['full_name']?.toString() ??
                                              _t('Patient'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          // "Patient ID: 4" in the chosen language
                                          _t('Patient ID: {id}').replaceAll(
                                            '{id}',
                                            '${patient!['patient_id']}',
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Text(
                              _t('Personal Information'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 14),

                            buildDetail(
                              _t('Full Name'),
                              patient!['full_name'],
                              Icons.person_outline,
                            ),
                            buildDetail(
                              _t('Date of Birth'),
                              patient!['date_of_birth'],
                              Icons.cake_outlined,
                            ),
                            buildDetail(
                              _t('Gender'),
                              genderShown, // translated value
                              Icons.wc_outlined,
                            ),
                            buildDetail(
                              _t('Phone Number'),
                              patient!['phone'],
                              Icons.phone_outlined,
                            ),
                            buildDetail(
                              _t('Address'),
                              patient!['address'],
                              Icons.home_outlined,
                            ),

                            const SizedBox(height: 20),
                            Text(
                              _t('Emergency Contact'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 14),

                            buildDetail(
                              _t('Contact Name'),
                              patient!['emergency_contact_name'],
                              Icons.contact_emergency_outlined,
                            ),
                            buildDetail(
                              _t('Contact Phone'),
                              patient!['emergency_contact_phone'],
                              Icons.phone_in_talk_outlined,
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }
}