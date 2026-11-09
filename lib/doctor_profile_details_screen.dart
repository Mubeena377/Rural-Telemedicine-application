import 'package:flutter/material.dart';

import 'api_service.dart';

// ============================================================
// DOCTOR PROFILE SCREEN
// Shows the doctor's real details from the server, and lets the
// doctor choose the languages they can speak with patients.
// ============================================================

class DoctorProfileDetailsScreen extends StatefulWidget {
  final int doctorId;

  const DoctorProfileDetailsScreen({
    super.key,
    required this.doctorId,
  });

  @override
  State<DoctorProfileDetailsScreen> createState() =>
      _DoctorProfileDetailsScreenState();
}

class _DoctorProfileDetailsScreenState
    extends State<DoctorProfileDetailsScreen> {
  // The doctor's details from the server
  Map<String, dynamic>? profile;

  // Every language the doctor can choose from (sent by the server)
  List<String> allLanguages = [];

  // The languages ticked on the screen right now
  Set<String> selected = {};

  // The languages saved on the server (to know if something changed)
  Set<String> saved = {};

  // True while loading (shows a spinner)
  bool isLoading = true;

  // True while the languages are being saved
  bool isSaving = false;

  // Holds an error message if loading fails
  String? errorMessage;

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadProfile(); // Start loading right away
  }

  // Loads the profile from the server
  Future<void> loadProfile() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final result = await ApiService.getDoctorProfile(widget.doctorId);

    // If the doctor left this screen while waiting, stop here
    if (!mounted) return;

    if (result['success'] == true) {
      final loaded = Map<String, dynamic>.from(result['profile']);
      final languages = List<String>.from(loaded['languages'] ?? []);

      setState(() {
        profile = loaded;
        allLanguages = List<String>.from(result['all_languages'] ?? []);
        selected = languages.toSet();
        saved = languages.toSet();
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
        errorMessage =
            (result['message'] ?? 'Failed to load the profile').toString();
      });
    }
  }

  // True if the doctor ticked or unticked something since the last save
  bool get hasChanges =>
      selected.length != saved.length || !selected.containsAll(saved);

  // Shows a short message at the bottom of the screen
  void showMessage(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  // Saves the chosen languages on the server
  Future<void> saveLanguages() async {
    if (selected.isEmpty) {
      showMessage('Please choose at least one language.', error: true);
      return;
    }

    setState(() => isSaving = true);

    final result = await ApiService.saveDoctorLanguages(
      doctorId: widget.doctorId,
      languages: selected.toList(),
    );

    if (!mounted) return;

    setState(() => isSaving = false);

    if (result['success'] == true) {
      setState(() => saved = Set<String>.from(selected));
      showMessage('Languages saved.');
    } else {
      showMessage(
        (result['message'] ?? 'Failed to save the languages').toString(),
        error: true,
      );
    }
  }

  // One line of information: a small icon, a title and the value
  Widget infoRow(IconData icon, String title, dynamic value) {
    final text = (value == null || value.toString().isEmpty)
        ? 'Not available'
        : value.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: const Color(0xFF3F6FA8)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF26384A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // A white box with a heading and some content inside
  Widget sectionBox(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF26384A),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  // The language buttons and the Save button
  Widget languageBox() {
    return sectionBox('Languages I can speak', [
      const Text(
        'Tap all the languages you can speak with patients.',
        style: TextStyle(fontSize: 13, color: Colors.grey),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: allLanguages.map((language) {
          return FilterChip(
            label: Text(language),
            selected: selected.contains(language),
            onSelected: (value) {
              setState(() {
                if (value) {
                  selected.add(language);
                } else {
                  selected.remove(language);
                }
              });
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton(
          // Only works when something changed and nothing is being saved
          onPressed: (hasChanges && !isSaving) ? saveLanguages : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F6FA8),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Save Languages',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ),
    ]);
  }

  // The whole profile
  Widget content() {
    final data = profile!;
    final years = data['experience_years'];

    return RefreshIndicator(
      onRefresh: loadProfile,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),
          const Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: Color(0xFFEAF2FA),
              child: Icon(
                Icons.medical_services_outlined,
                size: 50,
                color: Color(0xFF3F6FA8),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              (data['full_name'] ?? '').toString(),
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              (data['specialization'] ?? '').toString(),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),
          sectionBox('Professional Information', [
            infoRow(Icons.badge_outlined, 'Medical Registration Number',
                data['license_number']),
            infoRow(Icons.school_outlined, 'Qualification',
                data['qualification']),
            infoRow(Icons.medical_information_outlined, 'Specialization',
                data['specialization']),
            infoRow(Icons.work_outline, 'Years of Experience',
                years == null ? null : '$years years'),
          ]),
          const SizedBox(height: 18),
          sectionBox('Contact Information', [
            infoRow(Icons.phone_outlined, 'Phone Number', data['phone']),
          ]),
          const SizedBox(height: 18),
          languageBox(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // Decides what to show: spinner, error, or the profile
  Widget buildBody() {
    // 1. Still loading
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. Loading failed: message and Retry button
    if (errorMessage != null || profile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              errorMessage ?? 'Could not load the profile.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: loadProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // 3. Loaded
    return content();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text('Doctor Profile'),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: buildBody(),
    );
  }
}