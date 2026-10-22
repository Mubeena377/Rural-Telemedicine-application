import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'prescription_pdf.dart';
import 'order_medicine_screen.dart';
// ============================================================
// PATIENT PRESCRIPTIONS SCREEN
// Shows the prescriptions doctors have issued to the patient.
// ============================================================

class PatientPrescriptionsScreen extends StatefulWidget {
  // True when the screen is opened from the "Order Medicine" card.
  // It is false by default, so "My Prescriptions" stays unchanged.
  final bool orderMode;

  const PatientPrescriptionsScreen({
    super.key,
    this.orderMode = false,
  });

  @override
  State<PatientPrescriptionsScreen> createState() =>
      _PatientPrescriptionsScreenState();
}

class _PatientPrescriptionsScreenState
    extends State<PatientPrescriptionsScreen> {
  // The prescriptions loaded from the server
  List<Map<String, dynamic>> prescriptions = [];

  // True while the list is loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadPrescriptions(); // Start loading right away
  }

  // Loads this patient's prescriptions from the server
  Future<void> loadPrescriptions() async {
    // Show the spinner and clear any old error
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // The patient ID was saved on the phone when the patient logged in
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getInt('patientId');

      // No saved ID means the patient is not logged in
      if (patientId == null) {
        if (!mounted) return;
        setState(() {
          isLoading = false;
          errorMessage =
              'Patient information not found. Please log in again.';
        });
        return;
      }

      // Ask the server (function we added in api_service.dart)
      final data = await ApiService.getPatientPrescriptions(patientId);

      // If the patient left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        prescriptions = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // Builds the short text line for one medicine, e.g.
  // "200mg • twice daily • 3 days"
  String medicineSummary(Map<String, dynamic> medicine) {
    final parts = <String>[];

    if (medicine['dosage'] != null) {
      parts.add(medicine['dosage'].toString());
    }
    if (medicine['frequency'] != null) {
      parts.add(medicine['frequency'].toString());
    }
    if (medicine['duration_days'] != null) {
      parts.add('${medicine['duration_days']} days');
    }

    return parts.join(' • ');
  }

  // Builds the card for one prescription
  Widget prescriptionCard(Map<String, dynamic> prescription) {
    // The list of medicines inside this prescription
    final medicines = List<Map<String, dynamic>>.from(
      prescription['medicines'] ?? [],
    );

    final notes = (prescription['notes'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Doctor name and specialization
            Text(
              prescription['doctor_name']?.toString() ?? 'Doctor',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              prescription['specialization']?.toString() ?? '',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),

            const SizedBox(height: 10),

            // Date of the prescription
            Text(
              'Date: ${prescription['prescription_date']}',
              style: const TextStyle(fontSize: 13),
            ),

            // Diagnosis (only shown if the doctor wrote one)
            if ((prescription['diagnosis'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Diagnosis: ${prescription['diagnosis']}',
                style: const TextStyle(fontSize: 13),
              ),
            ],

            const Divider(height: 24),

            const Text(
              'Medicines',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // One block per medicine
            ...medicines.map((medicine) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.medication_outlined,
                      color: Color(0xFF3F6FA8),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medicine['medicine']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            medicineSummary(medicine),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          // Instructions (only if the doctor wrote some)
                          if ((medicine['instructions'] ?? '')
                              .toString()
                              .isNotEmpty)
                            Text(
                              medicine['instructions'].toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            // Extra notes from the doctor (only if there are any)
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Notes: $notes',
                style: const TextStyle(fontSize: 12),
              ),
            ],

            const SizedBox(height: 12),

                        // Button that opens the order screen for this prescription
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Open the order screen and pass this prescription to it
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrderMedicineScreen(
                        prescription: prescription,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.local_pharmacy),
                label: const Text('Order Medicines'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F6FA8),
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Button that creates the PDF for this prescription
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    // Build the PDF and open the save/print/share screen
                    await downloadPrescriptionPdf(prescription);
                  } catch (e) {
                    // If something goes wrong, tell the patient
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not create the PDF.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.download_outlined),
                label: const Text('Share / Save PDF'),
              ),
            ),
            
          ],
        ),
      ),
    );
  }

  // Decides what to show in the middle of the screen
  Widget buildBody() {
    // 1. Still loading: spinner
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. Loading failed: message and Retry button
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: loadPrescriptions,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Loaded, but there are no prescriptions yet
    if (prescriptions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medication_outlined, size: 60, color: Colors.grey),
            SizedBox(height: 14),
            Text(
              'No prescriptions yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    // 4. Show the list (pull down to refresh)
      // In order mode the list gets one extra item at the top:
    // a short message telling the patient what to do
    final extra = widget.orderMode ? 1 : 0;

    return RefreshIndicator(
      onRefresh: loadPrescriptions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: prescriptions.length + extra,
        itemBuilder: (context, index) {
          // The first item is the message (order mode only)
          if (widget.orderMode && index == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Choose a prescription, then tap "Order Medicines" on it.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF26384A),
                ),
              ),
            );
          }

          // The other items are the prescriptions
          // (we skip the message item when counting)
          return prescriptionCard(prescriptions[index - extra]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
                // Shows a different title when opened for ordering
        title: Text(
          widget.orderMode ? 'Order Medicines' : 'My Prescriptions',
        ),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: buildBody(),
    );
  }
}