import 'package:flutter/material.dart';
import 'api_service.dart';
import 'doctor_patient_history_screen.dart';


// ============================================================
// DOCTOR PATIENTS SCREEN
// The doctor's list of real patients (people who have an
// appointment with this doctor). Tap a patient to open the record.
// ============================================================

class DoctorPatientsScreen extends StatefulWidget {
  final int doctorId; // The logged-in doctor

  const DoctorPatientsScreen({
    super.key,
    required this.doctorId,
  });

  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> {
  // The patients loaded from the server
  List<Map<String, dynamic>> patients = [];

  // True while loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // What the doctor typed in the search box
  String searchText = '';

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadPatients(); // Start loading right away
  }

  // Loads the doctor's patients from the server
  Future<void> loadPatients() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Ask the server (function we added in api_service.dart)
      final data = await ApiService.getDoctorPatients(widget.doctorId);

      // If the doctor left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        patients = data;
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

  // The patients that match the search box (all of them if it is empty)
  List<Map<String, dynamic>> get shownPatients {
    final text = searchText.trim().toLowerCase();

    if (text.isEmpty) return patients;

    return patients.where((patient) {
      final name = (patient['full_name'] ?? '').toString().toLowerCase();
      final phone = (patient['phone'] ?? '').toString();
      return name.contains(text) || phone.contains(text);
    }).toList();
  }

  // Opens one patient's record
  void openPatient(Map<String, dynamic> patient) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DoctorPatientHistoryScreen(
          doctorId: widget.doctorId,
          patientId: patient['patient_id'] as int,
          patientName: (patient['full_name'] ?? 'Patient').toString(),
        ),
      ),
    );
  }

  // A friendly message with a big icon (used for empty states)
  Widget messageView(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 70, color: Colors.grey),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The card for one patient
  Widget patientCard(Map<String, dynamic> patient) {
    final age = patient['age'];
    final gender = (patient['gender'] ?? '').toString();
    final lastVisit = (patient['last_visit'] ?? '').toString();

    // Build a line like "25 years • Female"
    final details = <String>[];
    if (age != null) details.add('$age years');
    if (gender.isNotEmpty) details.add(gender);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // InkWell gives the ripple effect when tapped
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openPatient(patient),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Big round icon, pink for women and blue for others
              CircleAvatar(
                radius: 30,
                backgroundColor: gender == 'Female'
                    ? const Color(0xFFFCE8EF)
                    : const Color(0xFFEAF2FA),
                child: Icon(
                  gender == 'Female' ? Icons.woman : Icons.person,
                  size: 34,
                  color: gender == 'Female'
                      ? const Color(0xFFC9829B)
                      : const Color(0xFF3F6FA8),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (patient['full_name'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF26384A),
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        details.join(' • '),
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                    if (lastVisit.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.event,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Last appointment: $lastVisit',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // Decides what to show: spinner, error, empty message or the list
  Widget buildBody() {
    // 1. Still loading
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
                onPressed: loadPatients,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // 3. The doctor has no patients yet
    if (patients.isEmpty) {
      return messageView(
        Icons.folder_shared_outlined,
        'No patients yet. Patients appear here after they book an appointment with you.',
      );
    }

    // 4. The list, with a search box above it
    final shown = shownPatients;

    return Column(
      children: [
        // Search box (by name or phone number)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: TextField(
            onChanged: (value) {
              setState(() {
                searchText = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search by name or phone',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        Expanded(
          child: shown.isEmpty
              ? messageView(Icons.search_off, 'No patient matches your search.')
              : RefreshIndicator(
                  onRefresh: loadPatients, // Pull down to refresh
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: shown.length,
                    itemBuilder: (context, index) {
                      return patientCard(shown[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text('Patient Records'),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: buildBody(),
    );
  }
}