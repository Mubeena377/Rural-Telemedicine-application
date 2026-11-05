import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

// ============================================================
// REPORT VIEWER SCREEN
// Opens one report (a lab result or a scan).
//  - a picture is shown big, and can be zoomed with two fingers
//  - a PDF is shown page by page (it can also be shared or printed)
// It receives a function that loads the file, so the same screen
// works for the patient and for the doctor.
// ============================================================

class ReportViewerScreen extends StatefulWidget {
  final String title; // The report's title
  final String fileKind; // "pdf" or "image"
  final Future<Uint8List> Function() loadFile; // How to get the file

  const ReportViewerScreen({
    super.key,
    required this.title,
    required this.fileKind,
    required this.loadFile,
  });

  @override
  State<ReportViewerScreen> createState() => _ReportViewerScreenState();
}

class _ReportViewerScreenState extends State<ReportViewerScreen> {
  // The downloaded file (empty until it has loaded)
  Uint8List? bytes;

  // True while the file is downloading
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    load(); // Start downloading right away
  }

  // Downloads the file from the server
  Future<void> load() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await widget.loadFile();

      // If the user left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        bytes = data;
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

  // Decides what to show: spinner, error, picture or PDF
  Widget buildBody() {
    // 1. Still downloading
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. Downloading failed: message and Retry button
    if (errorMessage != null || bytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                errorMessage ?? 'Could not open the report.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final data = bytes!;

    // 3. A PDF
    if (widget.fileKind == 'pdf') {
      return PdfPreview(
        build: (format) async => data,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: '${widget.title}.pdf',
      );
    }

    // 4. A picture (InteractiveViewer lets the user zoom and move it)
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 5,
      child: Center(
        child: Image.memory(
          data,
          fit: BoxFit.contain,
          // If the file is not a real picture, show a message
          errorBuilder: (context, error, stackTrace) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This file could not be shown as a picture.',
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: buildBody(),
    );
  }
}