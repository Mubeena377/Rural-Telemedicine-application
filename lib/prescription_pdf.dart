import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:convert';

// ============================================================
// PRESCRIPTION PDF
// Builds a PDF from a prescription and opens the Android
// screen where the user can save it, print it or share it.
// ============================================================

// Turns any value into text (and an empty text if it is null)
String _text(dynamic value) => (value ?? '').toString();

// One table cell: a little padding around a piece of text
pw.Widget _cell(String text, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

// The main function. Give it one prescription (the same map the
// server sends) and it creates and shows the PDF.
Future<void> downloadPrescriptionPdf(
  Map<String, dynamic> prescription,
) async {
  // The empty PDF document we will fill
  final doc = pw.Document();

  // The medicines inside this prescription
  final medicines = List<Map<String, dynamic>>.from(
    prescription['medicines'] ?? [],
  );

  // Pick out the details (any missing detail becomes empty text)
  final doctorName = _text(prescription['doctor_name']);
  final specialization = _text(prescription['specialization']);
  final patientName = _text(prescription['patient_name']);
  final date = _text(prescription['prescription_date']);
  final diagnosis = _text(prescription['diagnosis']);
  final notes = _text(prescription['notes']);
  final prescriptionId = _text(prescription['prescription_id']);

  // The doctor's signature arrives as text. Turn it back into a picture
  // (stays empty if there is no signature or it cannot be read).
  final signatureText = _text(prescription['doctor_signature']);
  pw.MemoryImage? signatureImage;

  if (signatureText.isNotEmpty) {
    try {
      signatureImage = pw.MemoryImage(base64Decode(signatureText));
    } catch (e) {
      // A broken signature should not stop the PDF from being created
      signatureImage = null;
    }
  } 

  // The colour used for headings (same blue as the app)
  const blue = PdfColor.fromInt(0xFF3F6FA8);

  // MultiPage automatically continues onto a second page if needed
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        // ----- Title -----
        pw.Text(
          'Medical Prescription',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: blue,
          ),
        ),
        pw.Text(
          'Rural Telemedicine Platform',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: blue),
        pw.SizedBox(height: 10),

        // ----- Details (a line is skipped if it has no value) -----
        if (prescriptionId.isNotEmpty)
          pw.Text('Prescription No: $prescriptionId'),
        if (date.isNotEmpty) pw.Text('Date: $date'),
        if (doctorName.isNotEmpty)
          pw.Text(
            specialization.isEmpty
                ? 'Doctor: $doctorName'
                : 'Doctor: $doctorName ($specialization)',
          ),
        if (patientName.isNotEmpty) pw.Text('Patient: $patientName'),
        if (diagnosis.isNotEmpty) pw.Text('Diagnosis: $diagnosis'),

        pw.SizedBox(height: 18),

        // ----- Medicines table -----
        pw.Text(
          'Medicines',
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            color: blue,
          ),
        ),
        pw.SizedBox(height: 8),

        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey500),
          // How wide each column is compared with the others
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(1.6),
            3: const pw.FlexColumnWidth(1.3),
            4: const pw.FlexColumnWidth(2.5),
          },
          children: [
            // The grey header row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _cell('Medicine', bold: true),
                _cell('Dose', bold: true),
                _cell('Frequency', bold: true),
                _cell('Duration', bold: true),
                _cell('Instructions', bold: true),
              ],
            ),

            // One row for every medicine
            ...medicines.map((medicine) {
              final days = _text(medicine['duration_days']);

              return pw.TableRow(
                children: [
                  _cell(_text(medicine['medicine'])),
                  _cell(_text(medicine['dosage'])),
                  _cell(_text(medicine['frequency'])),
                  _cell(days.isEmpty ? '' : '$days days'),
                  _cell(_text(medicine['instructions'])),
                ],
              );
            }),
          ],
        ),

        // ----- Doctor's notes (only if there are any) -----
        if (notes.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text('Notes: $notes'),
        ],

        pw.SizedBox(height: 30),

        // ----- Doctor's signature (on the right side) -----
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            // "min" makes the column only as tall as its content
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // The signature picture (only if the doctor has one)
              if (signatureImage != null)
                pw.Image(signatureImage, height: 60),

              // A thin line to sign above
              pw.Container(
                width: 150,
                height: 1,
                color: PdfColors.grey600,
              ),
              pw.SizedBox(height: 4),

              // The doctor's name and specialization under the line
              pw.Text(
                doctorName.isEmpty ? 'Doctor' : doctorName,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (specialization.isNotEmpty)
                pw.Text(
                  specialization,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
            ],
          ),
        ),

        pw.SizedBox(height: 24),

        // ----- Footer -----
        pw.Text(
          'This is a computer-generated prescription issued through '
          'the Rural Telemedicine Platform.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    ),
  );

    // Open Android's share sheet. The patient taps WhatsApp (or any other
  // app), Drive, Bluetooth and so on, and the PDF file is sent or saved.
  await Printing.sharePdf(
    bytes: await doc.save(), // The finished PDF as bytes
    filename: 'prescription_$prescriptionId.pdf', // Name of the file
  );
}