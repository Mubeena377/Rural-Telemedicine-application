import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'signature_pad_screen.dart';
// ============================================================
// CREATE PRESCRIPTION SCREEN
// ============================================================

class DoctorCreatePrescriptionScreen
    extends StatefulWidget {
  // The ID of the doctor writing the prescription.
  // It is optional (the "?" means it can be empty) so that
  // the screen still opens from places we haven't updated yet.
  final int? doctorId;

  const DoctorCreatePrescriptionScreen({
    super.key,
    this.doctorId, // Receives the doctor ID when the screen is opened
  });

  @override
  State<DoctorCreatePrescriptionScreen> createState() =>
      _DoctorCreatePrescriptionScreenState();
}

class _DoctorCreatePrescriptionScreenState
    extends State<DoctorCreatePrescriptionScreen> {
  final TextEditingController patientController =
      TextEditingController();

  final TextEditingController diagnosisController =
      TextEditingController();

  final TextEditingController medicineController =
      TextEditingController();

  final TextEditingController dosageController =
      TextEditingController();

  final TextEditingController frequencyController =
      TextEditingController();

  final TextEditingController durationController =
      TextEditingController();

  final TextEditingController instructionsController =
      TextEditingController();

  final List<Map<String, String>> medicines = [];

  bool signatureAdded = false;

    // The doctor's saved consultations, loaded from the server.
  // A prescription must belong to one of these.
  List<Map<String, dynamic>> consultations = [];

  // The consultation the doctor picked for this prescription
  Map<String, dynamic>? selectedConsultation;

  // True while the list is being loaded (used to show a spinner)
  bool loadingConsultations = false;

  // Holds an error message if loading fails
  String? consultationsError;

  // True while the prescription is being sent to the server
      bool savingPrescription = false;

  // The doctor's saved signature picture (null = not drawn yet)
  Uint8List? signatureBytes;

  // True while the saved signature is being loaded
  bool loadingSignature = false;

  // initState runs once, when the screen first opens
  @override
  void initState() {
    super.initState();
        loadConsultations(); // Start loading the list right away
    loadSignature(); // Also load the doctor's saved signature
  }

  // Asks the server for this doctor's saved consultations
  Future<void> loadConsultations() async {
    // widget.doctorId is the ID passed in from the previous screen
    final doctorId = widget.doctorId;

    // If no ID was passed, we cannot load anything
    if (doctorId == null) {
      setState(() {
        consultationsError =
            'Doctor information is missing. Please open this screen again from the dashboard.';
      });
      return;
    }

    // Show the spinner and clear any old error
    setState(() {
      loadingConsultations = true;
      consultationsError = null;
    });

    // Call the server function that already exists in api_service.dart
    final result = await ApiService.getDoctorConsultationHistory(doctorId);

    // If the user left this screen while waiting, stop here
    if (!mounted) return;

    if (result['status'] == 'success') {
      // Save the list so the screen can show it
      setState(() {
        consultations = List<Map<String, dynamic>>.from(
          result['consultations'],
        );
        loadingConsultations = false;
      });
    } else {
      // Show the error message from the server
      setState(() {
        consultationsError =
            result['message'] ?? 'Failed to load consultations.';
        loadingConsultations = false;
      });
    }
  }

  @override
  void dispose() {
    patientController.dispose();
    diagnosisController.dispose();
    medicineController.dispose();
    dosageController.dispose();
    frequencyController.dispose();
    durationController.dispose();
    instructionsController.dispose();
    super.dispose();
  }

  void addMedicine() {
    if (medicineController.text.trim().isEmpty ||
        dosageController.text.trim().isEmpty ||
        frequencyController.text.trim().isEmpty ||
        durationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please complete the medicine details.',
          ),
        ),
      );
      return;
    }

    setState(() {
      medicines.add({
        'medicine': medicineController.text.trim(),
        'dosage': dosageController.text.trim(),
        'frequency':
            frequencyController.text.trim(),
        'duration':
            durationController.text.trim(),
        'instructions':
            instructionsController.text.trim(),
      });

      medicineController.clear();
      dosageController.clear();
      frequencyController.clear();
      durationController.clear();
      instructionsController.clear();
    });
  }

  void removeMedicine(int index) {
    setState(() {
      medicines.removeAt(index);
    });
  }

    Future<void> oldAddDigitalSignature() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Digital Signature'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.draw_outlined,
                size: 55,
                color: Color(0xFF3F6FA8),
              ),
              SizedBox(height: 15),
              Text(
                'Signature capture will allow the doctor to sign the prescription digitally.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'For the current frontend POC, the signature is represented as a verified digital signature.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Add Signature'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      setState(() {
        signatureAdded = true;
      });
    }
  }

    // Loads the doctor's saved signature from the server.
  // If one exists, it is used automatically.
  Future<void> loadSignature() async {
    final doctorId = widget.doctorId;

    // Without an ID we cannot load anything
    if (doctorId == null) return;

    setState(() {
      loadingSignature = true;
    });

    try {
      // Ask the server (function we added in api_service.dart)
      final saved = await ApiService.getDoctorSignature(doctorId);

      // If the doctor left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        if (saved != null) {
          // Turn the saved text back into a picture
          signatureBytes = base64Decode(saved);
          // A saved signature counts as "signature added"
          signatureAdded = true;
        }
        loadingSignature = false;
      });
    } catch (e) {
      if (!mounted) return;

      // If loading fails, the doctor can still draw a new signature
      setState(() {
        loadingSignature = false;
      });
    }
  }

  // Opens the signature pad. The drawn signature is saved on the
  // server, so the doctor only has to draw it once.
  Future<void> addDigitalSignature() async {
    final doctorId = widget.doctorId;

    // Without an ID we cannot save the signature
    if (doctorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Doctor information is missing. Please open this screen again from the dashboard.',
          ),
        ),
      );
      return;
    }

    // Open the pad. It gives back the picture when the doctor taps Save.
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (context) => const SignaturePadScreen(),
      ),
    );

    // The doctor went back without saving
    if (bytes == null) return;

    if (!mounted) return;

    // Send the picture to the server (as text)
    final result = await ApiService.saveDoctorSignature(
      doctorId: doctorId,
      signatureBase64: base64Encode(bytes),
    );

    if (!mounted) return;

    // The server refused: show its message and keep the old signature
    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] ?? 'Failed to save signature.',
          ),
        ),
      );
      return;
    }

    // Saved! Show it on this screen
    setState(() {
      signatureBytes = bytes;
      signatureAdded = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signature saved.'),
      ),
    );
  }
  Future<void> issuePrescription() async {
    if (patientController.text.trim().isEmpty ||
        diagnosisController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter patient and diagnosis details.',
          ),
        ),
      );
      return;
    }

    if (medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add at least one medicine.',
          ),
        ),
      );
      return;
    }

    if (!signatureAdded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add the doctor digital signature.',
          ),
        ),
      );
      return;
    }

    // ----------------------------------------------------
    // SAVE TO THE SERVER
    // ----------------------------------------------------

    // A prescription must belong to a saved consultation
    // and needs to know which doctor is writing it
    final doctorId = widget.doctorId;
    final consultation = selectedConsultation;

    if (doctorId == null || consultation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a consultation first.',
          ),
        ),
      );
      return;
    }

    // Ignore extra taps while a save is already in progress
    if (savingPrescription) return;

    setState(() {
      savingPrescription = true;
    });

    // Send everything to the Flask server (api_service.dart function)
    final result = await ApiService.savePrescription(
      doctorId: doctorId,
      consultationId: consultation['consultation_id'] as int,
      medicines: medicines, // The list built with "Add Medicine"
    );

    // If the doctor left this screen while waiting, stop here
    if (!mounted) return;

    setState(() {
      savingPrescription = false;
    });

    // If the server refused, show its message and stay on this screen
    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message'] ?? 'Failed to save prescription.',
          ),
        ),
      );
      return;
    }

    // Saved! The code below (the success popup) runs next.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Prescription Issued',
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_outlined,
                size: 60,
                color: Colors.green,
              ),
              SizedBox(height: 15),
              Text(
                'The prescription has been digitally signed and issued successfully.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Widget inputField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        alignLabelWithHint: maxLines > 1,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Create Prescription',
        ),
        backgroundColor:
            const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [

            // ==================================================
            // PATIENT DETAILS
            // ==================================================

            const Text(
              'Patient Details',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),

            const SizedBox(height: 15),

                        // ----------------------------------------------
            // CONSULTATION CHOOSER
            // The doctor picks one of their saved consultations.
            // ----------------------------------------------
            if (loadingConsultations)
              // Still loading: show a small spinner
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (consultationsError != null)
              // Loading failed: show the message and a Retry button
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    consultationsError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  TextButton.icon(
                    onPressed: loadConsultations, // Try loading again
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              )
            else if (consultations.isEmpty)
              // Loaded fine, but the doctor has no saved consultations
              const Text(
                'No saved consultations found. Please save the consultation notes first, then write the prescription.',
                style: TextStyle(color: Colors.grey),
              )
            else
              // Loaded fine: show the dropdown list
              DropdownButtonFormField<int>(
                isExpanded: true, // Use the full width so text fits
                // The currently picked consultation (null = nothing picked)
                value: selectedConsultation?['consultation_id'] as int?,
                decoration: InputDecoration(
                  labelText: 'Select Consultation',
                  prefixIcon: const Icon(Icons.person_outline),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                // One list entry per saved consultation
                items: consultations.map((consultation) {
                  return DropdownMenuItem<int>(
                    value: consultation['consultation_id'] as int,
                    child: Text(
                      '${consultation['patient_name']} • '
                      '${consultation['appointment_date']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                // Runs when the doctor picks an entry
                onChanged: (pickedId) {
                  // Find the full consultation that matches the picked ID
                  final picked = consultations.firstWhere(
                    (consultation) =>
                        consultation['consultation_id'] == pickedId,
                  );

                  setState(() {
                    selectedConsultation = picked;
                    // Fill the two fields the rest of the screen uses
                    patientController.text =
                        (picked['patient_name'] ?? '').toString();
                    diagnosisController.text =
                        (picked['diagnosis'] ?? '').toString();
                  });
                },
              ),

            const SizedBox(height: 14),

            inputField(
              label: 'Diagnosis',
              hint: 'Enter diagnosis',
              icon: Icons
                  .medical_information_outlined,
              controller: diagnosisController,
            ),

            const SizedBox(height: 25),

            // ==================================================
            // MEDICINE DETAILS
            // ==================================================

            const Text(
              'Medicine Details',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),

            const SizedBox(height: 15),

            inputField(
              label: 'Medicine Name',
              hint: 'Example: Paracetamol',
              icon: Icons.medication_outlined,
              controller: medicineController,
            ),

            const SizedBox(height: 14),

            inputField(
              label: 'Dosage',
              hint: 'Example: 500 mg',
              icon: Icons.science_outlined,
              controller: dosageController,
            ),

            const SizedBox(height: 14),

            inputField(
              label: 'Frequency',
              hint: 'Example: Twice daily',
              icon: Icons.schedule_outlined,
              controller: frequencyController,
            ),

            const SizedBox(height: 14),

            inputField(
              label: 'Duration',
              hint: 'Example: 3 days',
              icon: Icons.timer_outlined,
              controller: durationController,
            ),

            const SizedBox(height: 14),

            inputField(
              label: 'Instructions',
              hint:
                  'Example: Take after food',
              icon: Icons.notes_outlined,
              controller: instructionsController,
              maxLines: 2,
            ),

            const SizedBox(height: 15),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: addMedicine,
                icon: const Icon(Icons.add),
                label: const Text(
                  'Add Medicine',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ==================================================
            // ADDED MEDICINES
            // ==================================================

            if (medicines.isNotEmpty) ...[
              const Text(
                'Added Medicines',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF26384A),
                ),
              ),
              const SizedBox(height: 10),

              ...List.generate(
                medicines.length,
                (index) {
                  final medicine =
                      medicines[index];

                  return Card(
                    margin:
                        const EdgeInsets.only(
                      bottom: 10,
                    ),
                    elevation: 1,
                    child: Padding(
                      padding:
                          const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          const Icon(
                            Icons
                                .medication_outlined,
                            color:
                                Color(0xFF3F6FA8),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Text(
                                  medicine[
                                      'medicine']!,
                                  style:
                                      const TextStyle(
                                    fontSize: 15,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),
                                const SizedBox(
                                    height: 5),
                                Text(
                                  '${medicine['dosage']} • ${medicine['frequency']} • ${medicine['duration']}',
                                  style:
                                      const TextStyle(
                                    fontSize: 12,
                                    color:
                                        Colors.grey,
                                  ),
                                ),
                                if (medicine[
                                        'instructions']!
                                    .isNotEmpty) ...[
                                  const SizedBox(
                                      height: 5),
                                  Text(
                                    medicine[
                                        'instructions']!,
                                    style:
                                        const TextStyle(
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              removeMedicine(
                                index,
                              );
                            },
                            icon: const Icon(
                              Icons
                                  .delete_outline,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 15),
            ],

            // ==================================================
            // DIGITAL SIGNATURE
            // ==================================================

            const Text(
              'Digital Signature',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),

            const SizedBox(height: 15),

            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(16),
                border: Border.all(
                  color:
                      const Color(0xFFDCE5EE),
                ),
              ),
              child: Column(
                children: [
                                    // Show the doctor's real signature if there is one.
                  // While it is loading, show a small spinner.
                  // Otherwise show an icon.
                  if (signatureBytes != null)
                    Container(
                      height: 80,
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFDCE5EE),
                        ),
                      ),
                      // Image.memory shows a picture stored in memory
                      child: Image.memory(
                        signatureBytes!,
                        fit: BoxFit.contain,
                      ),
                    )
                  else if (loadingSignature)
                    const SizedBox(
                      height: 45,
                      width: 45,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  else
                    const Icon(
                      Icons.draw_outlined,
                      size: 45,
                      color: Color(0xFF3F6FA8),
                    ),
                  
                  const SizedBox(height: 10),
                  Text(
                    signatureAdded
                        ? 'Doctor Signature Added'
                        : 'Doctor Signature Required',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          FontWeight.bold,
                      color: signatureAdded
                          ? Colors.green
                          : const Color(
                              0xFF26384A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    signatureAdded
                        ? 'Prescription is ready to be digitally signed and issued.'
                        : 'Add your digital signature before issuing the prescription.',
                    textAlign:
                        TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: OutlinedButton.icon(
                      onPressed:
                          addDigitalSignature,
                      icon: Icon(
                        signatureAdded
                            ? Icons.edit_outlined
                            : Icons.draw_outlined,
                      ),
                      label: Text(
                        signatureAdded
                            ? 'Change Signature'
                            : 'Add Digital Signature',
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ==================================================
            // ISSUE PRESCRIPTION
            // ==================================================

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                    issuePrescription,
                icon: const Icon(
                  Icons.verified_outlined,
                ),
                label: const Text(
                  'Sign & Issue Prescription',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF3F6FA8),
                  foregroundColor:
                      Colors.white,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                            14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}


