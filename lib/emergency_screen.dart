import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_text.dart';
import 'emergency_screen_texts.dart';

// Finds a text in the chosen language (English if it is missing).
// It starts with _ so it belongs only to this file.
String _t(String text) => tt(emergencyScreenTexts, text);

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  // Emergency contact details saved after patient registration.
  String contactName = '';
  String contactRelationship = '';
  String contactPhone = '';

  final TextEditingController contactNameController = TextEditingController();

  final TextEditingController contactPhoneController = TextEditingController();

  bool isSavingContact = false;
  bool hasContactChanges = false;
  // Indicates whether the emergency contact information is loading.
  bool isLoading = true;

  // SOS preference: this setting does not send an actual SOS alert.
  bool shareLocationOnSOS = true;

  @override
  void initState() {
    super.initState();

    // Load saved emergency information when the screen opens.
    loadEmergencyDetails();
  }

  Future<void> loadEmergencyDetails() async {
    // Show the loading state while fetching details.
    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      // Get the registered patient's ID saved during registration.
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getInt('patientId');

      // Retrieve the location-sharing preference from local storage.
      final shareLocation = prefs.getBool('shareLocationOnSOS') ?? true;

      if (patientId == null) {
        if (!mounted) return;

        setState(() {
          contactName = '';
          contactRelationship = '';
          contactPhone = '';
          shareLocationOnSOS = shareLocation;
          isLoading = false;
        });
        return;
      }

      // Fetch the patient's emergency contact from the backend database.
      final result = await ApiService.getPatientDetails(patientId: patientId);

      if (!mounted) return;

      if (result['success'] == true) {
        final patient = result['patient'] as Map<String, dynamic>;
        setState(() {
          contactName = patient['emergency_contact_name']?.toString() ?? '';
          contactPhone = patient['emergency_contact_phone']?.toString() ?? '';

          contactNameController.text = contactName;
          contactPhoneController.text = contactPhone;

          contactRelationship = '';
          shareLocationOnSOS = shareLocation;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message']?.toString() ??
                  _t('Unable to load emergency contact details.'),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Unable to load emergency contact details.')),
        ),
      );
    }
  }

  void checkContactChanges() {
    final nameChanged = contactNameController.text.trim() != contactName;

    final phoneChanged = contactPhoneController.text.trim() != contactPhone;

    final hasChanges = nameChanged || phoneChanged;

    if (hasContactChanges != hasChanges) {
      setState(() {
        hasContactChanges = hasChanges;
      });
    }
  }

  // Save the user's SOS location-sharing preference locally.
  Future<void> saveLocationPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shareLocationOnSOS', value);

    if (!mounted) return;

    setState(() {
      shareLocationOnSOS = value;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('SOS preference saved on this device.'))),
    );
  }

  Future<void> saveEmergencyContact() async {
    final name = contactNameController.text.trim();
    final phone = contactPhoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Please enter the contact name and phone number.')),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getInt('patientId');

    if (patientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Patient ID not found. Please register again.')),
        ),
      );
      return;
    }

    setState(() {
      isSavingContact = true;
    });

    try {
      final result = await ApiService.updateEmergencyContact(
        patientId: patientId,
        contactName: name,
        contactPhone: phone,
      );

      if (!mounted) return;

      setState(() {
        isSavingContact = false;
      });

      if (result['success'] == true) {
        setState(() {
          contactName = name;
          contactPhone = phone;

          contactNameController.text = name;
          contactPhoneController.text = phone;

          hasContactChanges = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('Emergency contact saved successfully.')),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message']?.toString() ??
                  _t('Unable to save emergency contact.'),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSavingContact = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Unable to save emergency contact.'))),
      );
    }
  }

  // Displays one emergency contact detail in a styled card.
  Widget detailCard(String label, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Colors.red.shade700),
        title: Text(label),
        subtitle: Text(value.isEmpty ? _t('Not provided') : value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: Text(_t('Emergency')),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Emergency information heading.
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.health_and_safety_rounded,
                        color: Colors.red,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _t('Your Emergency Plan'),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t('Keep your emergency contact information up to date so it is ready when needed.'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  _t('Emergency Contact'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // Details loaded from the saved registration information.
                TextField(
                  controller: contactNameController,
                  onChanged: (_) => checkContactChanges(),
                  decoration: InputDecoration(
                    labelText: _t('Emergency Contact Name'),
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: contactPhoneController,
                  onChanged: (_) => checkContactChanges(),
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: _t('Emergency Contact Phone'),
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),

                const SizedBox(height: 16),

                if (hasContactChanges) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isSavingContact ? null : saveEmergencyContact,
                      icon: isSavingContact
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        isSavingContact ? _t('Saving...') : _t('Save Changes'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                Text(
                  _t('SOS Settings'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                // Controls the user's preference for location sharing.
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('Share location during SOS')),
                  subtitle: Text(
                    _t('Preference only. Actual location sharing requires SOS functionality to be connected.'),
                  ),
                  value: shareLocationOnSOS,
                  activeColor: Colors.red,
                  onChanged: saveLocationPreference,
                ),

                const SizedBox(height: 12),

                // This button is informational until SOS is connected
                // to a real backend and its response is confirmed.
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _t('SOS is not connected yet. If this is a real emergency in India, call 112.'),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.emergency),
                  label: Text(_t('SOS setup status')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
    );
  }
}