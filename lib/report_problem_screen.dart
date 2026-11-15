import 'package:flutter/material.dart';

import 'app_text.dart';
import 'report_problem_texts.dart';

// Finds a text in the chosen language (English if it is missing).
// It starts with _ so it belongs only to this file.
String _t(String text) => tt(reportProblemTexts, text);

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() =>
      _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final TextEditingController subjectController =
      TextEditingController();

  final TextEditingController descriptionController =
      TextEditingController();

  // The chosen category is always kept in ENGLISH, so it does not
  // depend on the language when the report is sent to a server later.
  // Only the text shown on the screen is translated.
  String selectedCategory = 'Technical Issue';

  final List<String> categories = [
    'Technical Issue',
    'Appointment Problem',
    'Video Consultation',
    'Prescription Problem',
    'Emergency SOS',
    'Other',
  ];

  @override
  void dispose() {
    subjectController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  void submitReport() {
    if (subjectController.text.trim().isEmpty ||
        descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Please fill in all fields.')),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            'Your report has been prepared. Submission service is not connected yet.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(
          _t('Report a Problem'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.report_problem_outlined,
              size: 50,
              color: Colors.teal,
            ),
            const SizedBox(height: 15),

            Text(
              _t('Tell us what went wrong'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              _t('Describe the issue so our team can understand how to help.'),
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),

            Text(
              _t('Problem Category'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              // The newer Flutter name for the starting value
              initialValue: selectedCategory,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: categories.map((category) {
                return DropdownMenuItem(
                  // The value stays English, the shown text is translated
                  value: category,
                  child: Text(_t(category)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    selectedCategory = value;
                  });
                }
              },
            ),

            const SizedBox(height: 20),

            Text(
              _t('Subject'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: subjectController,
              decoration: InputDecoration(
                hintText: _t('Enter problem subject'),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              _t('Description'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            TextField(
              controller: descriptionController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: _t('Explain the problem in detail...'),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _t('Submit Report'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}