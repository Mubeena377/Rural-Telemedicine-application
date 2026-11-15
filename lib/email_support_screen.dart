import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_text.dart';
import 'email_support_texts.dart';

// Finds a text in the chosen language (English if it is missing).
// It starts with _ so it belongs only to this file.
String _t(String text) => tt(emailSupportTexts, text);

class EmailSupportScreen extends StatelessWidget {
  const EmailSupportScreen({super.key});

  // The address itself is not translated
  static const String supportEmail =
      'support@ruraltelemedicine.example';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(
          _t('Email Support'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              size: 55,
              color: Colors.teal,
            ),
            const SizedBox(height: 18),

            Text(
              _t('We are here to help!'),
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            Text(
              _t(
                'For assistance with appointments, video consultations, prescriptions or other app-related issues, contact our support team.',
              ),
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 28),

            Text(
              _t('Our Support Email'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.teal.shade100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.email_outlined, color: Colors.teal),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      supportEmail,
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy_rounded,
                      color: Colors.teal,
                    ),
                    onPressed: () {
                      // Copy the address to the clipboard
                      Clipboard.setData(
                        const ClipboardData(text: supportEmail),
                      );

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_t('Email address copied')),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Text(
              _t(
                'Note: This is a temporary development address. It cannot receive emails.',
              ),
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}