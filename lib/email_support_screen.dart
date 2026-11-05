
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EmailSupportScreen extends StatelessWidget {
  const EmailSupportScreen({super.key});

  static const String supportEmail =
      'support@ruraltelemedicine.example';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text(
          'Email Support',
          style: TextStyle(fontWeight: FontWeight.bold),
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

            const Text(
              'We are here to help!',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            const Text(
              'For assistance with appointments, video consultations, '
              'prescriptions or other app-related issues, contact our support team.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 28),

            const Text(
              'Our Support Email',
              style: TextStyle(
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
                      Clipboard.setData(
                        const ClipboardData(text: supportEmail),
                      );

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Email address copied'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Note: This is a temporary development address. '
              'It cannot receive emails.',
              style: TextStyle(
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
