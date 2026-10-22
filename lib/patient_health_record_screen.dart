import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'patient_prescriptions_screen.dart';

// ============================================================
// PATIENT HEALTH RECORD SCREEN
// Opens from the "My Health Records" card. It shows:
//  - a summary (number of consultations and saved records)
//  - allergies, conditions, etc. that the patient can add or remove
//  - the consultation history (tap a card to see the details)
//  - a shortcut to the patient's prescriptions
// ============================================================

class PatientHealthRecordScreen extends StatefulWidget {
  const PatientHealthRecordScreen({super.key});

  @override
  State<PatientHealthRecordScreen> createState() =>
      _PatientHealthRecordScreenState();
}

class _PatientHealthRecordScreenState extends State<PatientHealthRecordScreen> {
  // The logged-in patient (read from the phone when the screen opens)
  int? patientId;

  // Data loaded from the server
  List<Map<String, dynamic>> consultations = [];
  List<Map<String, dynamic>> records = [];

  // True while loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // The kinds of record a patient can add, each with its own
  // icon and colour. "type" is the exact word the server expects.
  final List<Map<String, dynamic>> recordTypes = [
    {
      'type': 'Allergy',
      'icon': Icons.warning_amber_rounded,
      'color': Colors.red,
    },
    {
      'type': 'Condition',
      'icon': Icons.health_and_safety_outlined,
      'color': Colors.blue,
    },
    {
      'type': 'Immunization',
      'icon': Icons.vaccines,
      'color': Colors.green,
    },
    {
      'type': 'Surgery',
      'icon': Icons.healing,
      'color': Colors.purple,
    },
    {
      'type': 'Other',
      'icon': Icons.note_alt_outlined,
      'color': Colors.blueGrey,
    },
  ];

  // Finds the icon and colour for a record type
  Map<String, dynamic> typeInfo(String type) {
    return recordTypes.firstWhere(
      (item) => item['type'] == type,
      orElse: () => recordTypes.last, // Unknown type: use "Other"
    );
  }

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadRecord(); // Start loading right away
  }

  // Shows a short message at the bottom of the screen
  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Loads the health record from the server
  Future<void> loadRecord() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // The patient ID was saved on the phone when the patient logged in
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt('patientId');

      if (id == null) {
        if (!mounted) return;
        setState(() {
          isLoading = false;
          errorMessage =
              'Patient information not found. Please log in again.';
        });
        return;
      }

      // Ask the server (function we added in api_service.dart)
      final data = await ApiService.getPatientHealthRecord(id);

      // If the patient left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        patientId = id;
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

  // Opens the small form at the bottom where the patient adds a record
  Future<void> showAddRecordSheet() async {
    final id = patientId;
    if (id == null) return;

    // These values live only while the form is open
    String selectedType = 'Allergy';
    final descriptionController = TextEditingController();
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Lets the form move up with the keyboard
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        // StatefulBuilder lets the form redraw itself when a choice changes
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                // Keeps the form above the keyboard
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add to your health record',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF26384A),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // One big tappable chip for each record type
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: recordTypes.map((item) {
                      final type = item['type'] as String;
                      final color = item['color'] as Color;

                      return ChoiceChip(
                        avatar: Icon(
                          item['icon'] as IconData,
                          size: 20,
                          color: selectedType == type ? Colors.white : color,
                        ),
                        label: Text(type),
                        selected: selectedType == type,
                        selectedColor: color,
                        labelStyle: TextStyle(
                          color: selectedType == type
                              ? Colors.white
                              : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (_) {
                          setSheetState(() {
                            selectedType = type;
                          });
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // What the patient wants to write down
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Example: Allergic to penicillin',
                      filled: true,
                      fillColor: const Color(0xFFF7FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      // Disabled while the record is being saved
                      onPressed: saving
                          ? null
                          : () async {
                              final description =
                                  descriptionController.text.trim();

                              // Nothing was written
                              if (description.isEmpty) {
                                showMessage('Please write a short note.');
                                return;
                              }

                              setSheetState(() {
                                saving = true;
                              });

                              // Send it to the server
                              final result = await ApiService.addMedicalRecord(
                                patientId: id,
                                recordType: selectedType,
                                description: description,
                              );

                              // The screen may have been closed meanwhile
                              if (!mounted) return;

                              // The server refused: show why and keep the form
                              if (result['success'] != true) {
                                setSheetState(() {
                                  saving = false;
                                });
                                showMessage(
                                  result['message'] ?? 'Failed to add.',
                                );
                                return;
                              }

                              // Saved: close the form and reload the list
                              Navigator.pop(sheetContext);
                              showMessage('Added to your health record.');
                              loadRecord();
                            },
                      icon: const Icon(Icons.add),
                      label: Text(
                        saving ? 'Saving...' : 'Add',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3F6FA8),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Asks first, then deletes one record
  Future<void> deleteRecord(Map<String, dynamic> record) async {
    final id = patientId;
    if (id == null) return;

    // Ask for confirmation so nothing is removed by accident
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove this entry?'),
          content: Text((record['description'] ?? '').toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final result = await ApiService.deleteMedicalRecord(
      patientId: id,
      recordId: record['record_id'] as int,
    );

    if (!mounted) return;

    if (result['success'] != true) {
      showMessage(result['message'] ?? 'Failed to remove.');
      return;
    }

    showMessage('Removed.');
    loadRecord(); // Reload the list
  }

  // ----------------------------------------------------------
  // SMALL BUILDING BLOCKS
  // ----------------------------------------------------------

  // The blue banner at the top
  Widget banner() {
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Health Record',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Everything about your health, in one place.',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.folder_shared,
              size: 40,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // One of the two summary boxes (number + label + big icon)
  Widget summaryTile(
    IconData icon,
    Color color,
    String number,
    String label,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCE5EE)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 38, color: color),
            const SizedBox(height: 6),
            Text(
              number,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // A section title with an icon (and an optional button on the right)
  Widget sectionHeader(String title, IconData icon, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF3F6FA8), size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // One saved record (allergy, condition, ...)
  Widget recordCard(Map<String, dynamic> record) {
    final info = typeInfo((record['record_type'] ?? 'Other').toString());
    final color = info['color'] as Color;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(info['icon'] as IconData, color: color, size: 28),
        ),
        title: Text(
          (record['record_type'] ?? '').toString(),
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        subtitle: Text((record['description'] ?? '').toString()),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          tooltip: 'Remove',
          onPressed: () => deleteRecord(record),
        ),
      ),
    );
  }

  // One detail line inside a consultation (hidden if it is empty)
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
            '${item['doctor_name'] ?? ''} • ${item['appointment_date'] ?? ''}',
            style: const TextStyle(fontSize: 12),
          ),
          children: [
            detailRow(Icons.person_outline, 'Doctor',
                '${item['doctor_name'] ?? ''} (${item['specialization'] ?? ''})'),
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

          const SizedBox(height: 16),

          // The two summary boxes
          Row(
            children: [
              summaryTile(
                Icons.medical_services,
                Colors.teal,
                '${consultations.length}',
                'Consultations',
              ),
              const SizedBox(width: 12),
              summaryTile(
                Icons.health_and_safety_outlined,
                Colors.blue,
                '${records.length}',
                'Saved notes',
              ),
            ],
          ),

          // ----- Allergies, conditions and more -----
          sectionHeader(
            'Allergies, conditions & more',
            Icons.health_and_safety_outlined,
            trailing: ElevatedButton.icon(
              onPressed: showAddRecordSheet,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3F6FA8),
                foregroundColor: Colors.white,
              ),
            ),
          ),

          if (records.isEmpty)
            emptyMessage(
              Icons.add_circle_outline,
              'Nothing added yet. Tap "Add" to write down an allergy, a condition or a vaccine.',
            )
          else
            ...records.map(recordCard),

          // ----- Consultation history -----
          sectionHeader('Consultation history', Icons.history),

          if (consultations.isEmpty)
            emptyMessage(
              Icons.medical_services_outlined,
              'No consultations yet. They will appear here after you see a doctor.',
            )
          else
            ...consultations.map(consultationCard),

          // ----- Shortcut to prescriptions -----
          sectionHeader('Prescriptions', Icons.medication),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            // InkWell gives the ripple effect when tapped
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PatientPrescriptionsScreen(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.teal.withOpacity(0.12),
                      child: const Icon(
                        Icons.medication,
                        color: Colors.teal,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Prescriptions',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'View, share or save your prescriptions',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 18),
                  ],
                ),
              ),
            ),
          ),

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
        title: const Text('My Health Records'),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: buildBody(),
    );
  }
}