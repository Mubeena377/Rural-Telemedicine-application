import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'app_text.dart';
import 'patient_reports_texts.dart';
import 'report_file_picker.dart';
import 'report_viewer_screen.dart';

// Finds a text in the chosen language (English if it is missing).
// It starts with _ so it belongs only to this file.
String _t(String text) => tt(patientReportsTexts, text);

// ============================================================
// PATIENT REPORTS SCREEN
// The patient's lab results and scans. The patient can upload a
// PDF or a picture, open a report, or delete it.
// ============================================================

class PatientReportsScreen extends StatefulWidget {
  const PatientReportsScreen({super.key});

  @override
  State<PatientReportsScreen> createState() => _PatientReportsScreenState();
}

class _PatientReportsScreenState extends State<PatientReportsScreen> {
  // The logged-in patient (read from the phone when the screen opens)
  int? patientId;

  // The reports loaded from the server
  List<Map<String, dynamic>> reports = [];

  // True while loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // The kinds of report. "type" is the exact word the server expects.
  // "label" is the English text; it is translated when it is shown.
  final List<Map<String, dynamic>> reportTypes = const [
    {
      'type': 'Lab',
      'label': 'Lab test',
      'icon': Icons.science_outlined,
      'color': Colors.teal,
    },
    {
      'type': 'Imaging',
      'label': 'X-ray / Scan',
      'icon': Icons.document_scanner_outlined,
      'color': Colors.indigo,
    },
    {
      'type': 'Other',
      'label': 'Other',
      'icon': Icons.description_outlined,
      'color': Colors.blueGrey,
    },
  ];

  // Finds the details of a report type
  Map<String, dynamic> typeInfo(String type) {
    return reportTypes.firstWhere(
      (item) => item['type'] == type,
      orElse: () => reportTypes.last, // Unknown type: use "Other"
    );
  }

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadReports(); // Start loading right away
  }

  // Shows a short message at the bottom of the screen
  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Loads the patient's reports from the server
  Future<void> loadReports() async {
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
              _t('Patient information not found. Please log in again.');
        });
        return;
      }

      // Ask the server (function we added in api_service.dart)
      final list = await ApiService.getPatientReports(id);

      // If the patient left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        patientId = id;
        reports = list;
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
  // UPLOADING
  // ----------------------------------------------------------

  // "C:\folder\scan.pdf" or "/folder/scan.pdf" -> "scan.pdf"
  String fileNameOf(String path) {
    return path.replaceAll('\\', '/').split('/').last;
  }

  // The title used when the patient leaves it empty,
  // for example "Lab report, 28 Oct".
  // It stays in English on purpose: it is saved on the server and
  // the doctor reads it.
  String defaultTitle(String type) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    final today = DateTime.now();
    final label = type == 'Lab'
        ? 'Lab report'
        : type == 'Imaging'
            ? 'X-ray / Scan'
            : 'Report';

    return '$label, ${today.day} ${months[today.month - 1]}';
  }

  // Opens the upload form at the bottom of the screen
  Future<void> showUploadSheet() async {
    final id = patientId;
    if (id == null) return;

    // These values live only while the form is open
    String? filePath; // The file the patient chose
    String type = 'Lab';
    String title = '';
    bool saving = false;
    String? error;

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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('Upload a report'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF26384A),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Step 1: choose the file
                    OutlinedButton.icon(
                      onPressed: () async {
                        final path = await pickReportFilePath();

                        // The patient closed the chooser without a file
                        if (path == null) return;

                        setSheetState(() {
                          filePath = path;
                        });
                      },
                      icon: Icon(
                        filePath == null
                            ? Icons.attach_file
                            : Icons.check_circle,
                        color: filePath == null ? null : Colors.green,
                      ),
                      label: Text(
                        filePath == null
                            ? _t('Choose a PDF or a photo')
                            : fileNameOf(filePath!),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _t('Tip: take a photo of a paper report with your camera first, then choose it here.'),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // Step 2: what kind of report is it? (picture buttons)
                    Row(
                      children: reportTypes.map((item) {
                        final itemType = item['type'] as String;
                        final color = item['color'] as Color;
                        final chosen = type == itemType;

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                setSheetState(() {
                                  type = itemType;
                                });
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: chosen
                                      ? color.withOpacity(0.15)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: chosen
                                        ? color
                                        : const Color(0xFFDCE5EE),
                                    width: chosen ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      item['icon'] as IconData,
                                      size: 34,
                                      color: color,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _t(item['label'] as String),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Step 3: an optional title
                    TextField(
                      onChanged: (value) => title = value,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: _t('Title (optional)'),
                        hintText: _t('Example: Blood test'),
                        prefixIcon: const Icon(Icons.edit_note),
                        filled: true,
                        fillColor: const Color(0xFFF7FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    // A problem with the form (shown in red)
                    if (error != null) ...[
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 8),
                    ],

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        // Disabled while the report is being sent
                        onPressed: saving
                            ? null
                            : () async {
                                if (filePath == null) {
                                  setSheetState(() {
                                    error = _t('Please choose a file first.');
                                  });
                                  return;
                                }

                                setSheetState(() {
                                  saving = true;
                                  error = null;
                                });

                                // Send it to the server
                                final result = await ApiService.uploadReport(
                                  patientId: id,
                                  filePath: filePath!,
                                  reportType: type,
                                  description: title.trim().isEmpty
                                      ? defaultTitle(type)
                                      : title.trim(),
                                );

                                // The screen may have been closed meanwhile
                                if (!mounted) return;

                                // The server refused: show why and keep the form
                                if (result['success'] != true) {
                                  setSheetState(() {
                                    saving = false;
                                    error = (result['message'] ??
                                            _t('Could not upload the report.'))
                                        .toString();
                                  });
                                  return;
                                }

                                // Saved: close the form and reload the list
                                Navigator.pop(sheetContext);
                                showMessage(_t('Report uploaded.'));
                                loadReports();
                              },
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(
                          saving ? _t('Uploading...') : _t('Upload'),
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
              ),
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------------
  // OPENING AND DELETING
  // ----------------------------------------------------------

  // Opens one report in the viewer
  void openReport(Map<String, dynamic> report) {
    final id = patientId;
    if (id == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportViewerScreen(
          title: (report['description'] ?? 'Report').toString(),
          fileKind: (report['file_kind'] ?? 'image').toString(),
          // How the viewer gets the file from the server
          loadFile: () => ApiService.getReportFile(
            patientId: id,
            reportId: report['report_id'] as int,
          ),
        ),
      ),
    );
  }

  // Asks first, then deletes one report
  Future<void> deleteReport(Map<String, dynamic> report) async {
    final id = patientId;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_t('Delete this report?')),
          content: Text((report['description'] ?? '').toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('Cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_t('Delete')),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final result = await ApiService.deleteReport(
      patientId: id,
      reportId: report['report_id'] as int,
    );

    if (!mounted) return;

    if (result['success'] != true) {
      showMessage((result['message'] ?? _t('Could not delete.')).toString());
      return;
    }

    showMessage(_t('Report deleted.'));
    loadReports();
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('My Reports'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _t('Keep your test results and scans in one place.'),
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
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
            child: const Icon(Icons.folder_open, size: 40, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // The card for one report
  Widget reportCard(Map<String, dynamic> report) {
    final info = typeInfo((report['report_type'] ?? 'Other').toString());
    final color = info['color'] as Color;
    final isPdf = report['file_kind'] == 'pdf';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      // InkWell gives the ripple effect when tapped
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openReport(report),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withOpacity(0.12),
                child: Icon(info['icon'] as IconData, color: color, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (report['description'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          isPdf ? Icons.picture_as_pdf : Icons.image,
                          size: 14,
                          color: isPdf ? Colors.red : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_t(info['label'] as String)} • ${report['report_date'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: _t('Delete'),
                onPressed: () => deleteReport(report),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A friendly message with a big icon (used when the list is empty)
  Widget emptyMessage() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5EE)),
      ),
      child: Column(
        children: [
          const Icon(Icons.upload_file, size: 56, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            _t('No reports yet.\nTap "Upload" to add a test result or a scan.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Decides what to show: spinner, error, or the list
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
                onPressed: loadReports,
                icon: const Icon(Icons.refresh),
                label: Text(_t('Retry')),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Loaded: show the reports (pull down to refresh)
    return RefreshIndicator(
      onRefresh: loadReports,
      child: ListView(
        // Extra space at the bottom so the button never hides a card
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          banner(),
          const SizedBox(height: 16),
          if (reports.isEmpty)
            emptyMessage()
          else
            ...reports.map(reportCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(_t('My Reports')),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showUploadSheet,
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: Text(_t('Upload')),
      ),
      body: buildBody(),
    );
  }
}