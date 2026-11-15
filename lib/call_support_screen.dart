import 'package:flutter/material.dart';

import 'app_text.dart';
import 'call_support_texts.dart';

// Finds a text in the chosen language (English if it is missing).
// It starts with _ so it belongs only to this file.
String _t(String text) => tt(callSupportTexts, text);

class CallSupportScreen extends StatelessWidget {
  const CallSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(
          _t('Call Support'),
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
              Icons.support_agent_rounded,
              size: 58,
              color: Colors.teal,
            ),

            const SizedBox(height: 18),

            Text(
              _t('Talk to our Support Team'),
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              _t(
                'Need assistance with appointments, video consultations, prescriptions or other app-related issues? We are here to help.',
              ),
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.black54,
              ),
            ),

            const SizedBox(height: 28),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.teal.shade100),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.phone_in_talk_rounded,
                    size: 35,
                    color: Colors.teal,
                  ),

                  const SizedBox(height: 12),

                  Text(
                    _t('Support Phone Number'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _t('Coming Soon'),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.teal.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      // Switched off until a real support number exists
                      onPressed: null,
                      icon: const Icon(Icons.call),
                      label: Text(_t('Call Now')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Center(
              child: Text(
                _t('Our phone support service will be available soon.'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}