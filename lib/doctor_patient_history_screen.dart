import 'package:flutter/material.dart';
import 'api_service.dart';

// ============================================================
// DOCTOR PATIENT HISTORY SCREEN
// Shows one patient's record to a doctor:
//  - the patient's details
//  - a red warning if the patient has allergies
//  - allergies, conditions and other notes the patient added
//  - the consultations this doctor carried out
// ============================================================

class DoctorPatientHistoryScreen extends StatefulWidget {
  final int doctorId; // The logged-in doctor
  final int patientId; // The patient to show
  final String patientName; // Shown in the top bar while loading

  const DoctorPatientHistoryScreen({
    super.key,
    required this.doctorId,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<DoctorPatientHistoryScreen> createState() =>
      _DoctorPatientHistoryScreenState();
}

class _DoctorPatientHistoryScreenState
    extends State<DoctorPatientHistoryScreen> {
  // Data loaded from the server
  Map<String, dynamic> patient = {};
  List<Map<String, dynamic>> consultations = [];
  List<Map<String, dynamic>> records = [];

  // True while loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // An icon and a colour for each kind of saved note
  final Map<String, IconData> typeIcons = const {
    'Allergy': Icons.warning_amber_rounded,
    'Condition': Icons.health_and_safety_outlined,
    'Immunization': Icons.vaccines,
    'Surgery': Icons.healing,
    'Other': Icons.note_alt_outlined,
  };

  final Map<String, Color> typeColors = const {
    'Allergy': Colors.red,
    'Condition': Colors.blue,
    'Immunization': Colors.green,
    'Surgery': Colors.purple,
    'Other': Colors.blueGrey,
  };

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadRecord(); // Start loading right away
  }

  // Loads the patient's record from the server
  Future<void> loadRecord() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Ask the server (function we added in api_service.dart).
      // The server refuses if this doctor has no appointment with the patient.
      final data = await ApiService.getPatientRecordForDoctor(
        doctorId: widget.doctorId,
        patientId: widget.patientId,
      );

      // If the doctor left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        patient = Map<String, dynamic>.from(data['patient'] ?? {});
        consultations = List<Map<String, dynamic>>.from(
          data['consultations'] ?? [],
        );
        records = List<Map<String, dynamic>>.from(
          data['records'] ?? [],
        );
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

  // ----------------------------------------------------------
  // SMALL BUILDING BLOCKS
  // ----------------------------------------------------------

  // The blue banner with the patient's name, age, gender and phone
  Widget banner() {
    final age = patient['age'];
    final gender = (patient['gender'] ?? '').toString();

    // Build a line like "25 years • Female"
    final details = <String>[];
    if (age != null) details.add('$age years');
    if (gender.isNotEmpty) details.add(gender);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF3F6FA8), Color(0xFF5FA8D3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          // Big round icon on the left
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, size: 40, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (patient['full_name'] ?? widget.patientName).toString(),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details.join(' • '),
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
                if ((patient['phone'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        patient['phone'].toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The red warning box that lists the patient's allergies
  Widget allergyWarning() {
    // Pick the records whose type is "Allergy"
    final allergies = records
        .where((record) => record['record_type'] == 'Allergy')
        .map((record) => (record['description'] ?? '').toString())
        .toList();

    // No allergies: show nothing
    if (allergies.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Allergies reported by the patient',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text(allergies.join(', ')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // A section title with an icon
  Widget sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF3F6FA8), size: 26),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF26384A),
            ),
          ),
        ],
      ),
    );
  }

  // One detail line (hidden if it is empty)
  Widget detailRow(IconData icon, String label, dynamic value) {
    final text = (value ?? '').toString();

    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: const Color(0xFF3F6FA8)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(text, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The card with the patient's personal details
  Widget profileCard() {
    // Build the emergency contact text, for example "Anita (9999999999)"
    final emergencyName = (patient['emergency_contact_name'] ?? '').toString();
    final emergencyPhone =
        (patient['emergency_contact_phone'] ?? '').toString();
    final emergency = [emergencyName, emergencyPhone]
        .where((part) => part.isNotEmpty)
        .join(' • ');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            detailRow(Icons.bloodtype_outlined, 'Blood group',
                patient['blood_group']),
            detailRow(Icons.location_on_outlined, 'Address',
                patient['address']),
            detailRow(Icons.contact_phone_outlined, 'Emergency contact',
                emergency),
          ],
        ),
      ),
    );
  }

  // One saved note (allergy, condition, ...). The doctor can only read it.
  Widget recordCard(Map<String, dynamic> record) {
    final type = (record['record_type'] ?? 'Other').toString();
    final color = typeColors[type] ?? Colors.blueGrey;
    final icon = typeIcons[type] ?? Icons.note_alt_outlined;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          type,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        subtitle: Text((record['description'] ?? '').toString()),
      ),
    );
  }

  // One past consultation (tap to open the details)
  Widget consultationCard(Map<String, dynamic> item) {
    final diagnosis = (item['diagnosis'] ?? '').toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // Removes the default lines inside the expandable tile
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: Colors.teal.withOpacity(0.12),
            child: const Icon(
              Icons.medical_services,
              color: Colors.teal,
              size: 28,
            ),
          ),
          title: Text(
            diagnosis.isEmpty ? 'Consultation' : diagnosis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            (item['appointment_date'] ?? '').toString(),
            style: const TextStyle(fontSize: 12),
          ),
          children: [
            detailRow(Icons.chat_bubble_outline, 'Complaint',
                item['chief_complaint']),
            detailRow(Icons.notes, 'Doctor notes', item['notes']),
            detailRow(Icons.lightbulb_outline, 'Advice', item['advice']),
            detailRow(Icons.event_available, 'Follow-up date',
                item['follow_up_date']),
          ],
        ),
      ),
    );
  }

  // A friendly message with a big icon (used when a list is empty)
  Widget emptyMessage(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5EE)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 46, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Everything that is shown once the data has loaded
  Widget content() {
    return RefreshIndicator(
      onRefresh: loadRecord, // Pull down to refresh
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          banner(),
          allergyWarning(),

          sectionHeader('Patient details', Icons.badge_outlined),
          profileCard(),

          sectionHeader(
            'Allergies, conditions & more',
            Icons.health_and_safety_outlined,
          ),
          if (records.isEmpty)
            emptyMessage(
              Icons.health_and_safety_outlined,
              'The patient has not added any notes yet.',
            )
          else
            ...records.map(recordCard),

          sectionHeader('Your consultations', Icons.history),
          if (consultations.isEmpty)
            emptyMessage(
              Icons.medical_services_outlined,
              'You have not saved a consultation for this patient yet.',
            )
          else
            ...consultations.map(consultationCard),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Decides what to show: spinner, error, or the content
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
                onPressed: loadRecord,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Loaded: show the record
    return content();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(widget.patientName),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: buildBody(),
    );
  }
}