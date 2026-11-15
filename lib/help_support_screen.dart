import 'package:flutter/material.dart';
import 'email_support_screen.dart';
import 'call_support_screen.dart';
import 'report_problem_screen.dart';
import 'help_support_text.dart'; // tx() shows text in the chosen language

// ============================================================
// HELP AND SUPPORT SCREEN
// Every fixed sentence goes through tx(), so it follows the language
// the patient chose. Layout and buttons are unchanged.
// ============================================================

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),

      appBar: AppBar(
        title: Text(
          tx('Help & Support'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 21,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // SUPPORT HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.teal.shade400,
                    Colors.teal.shade700,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.support_agent_rounded,
                    color: Colors.white,
                    size: 42,
                  ),

                  const SizedBox(height: 14),

                  Text(
                    tx('How can we help you?'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    tx('We are here to help you use Rural Telemedicine.'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 26),

            Text(
              tx('Frequently Asked Questions'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF263238),
              ),
            ),

            const SizedBox(height: 12),

            _faqTile(
              tx('How can I book an appointment?'),
              tx('Open the appointment section, choose an available doctor and select your preferred time.'),
            ),

            _faqTile(
              tx('How do I join a video consultation?'),
              tx('Open your scheduled appointment and tap the video consultation option.'),
            ),

            _faqTile(
              tx('Where can I view my prescriptions?'),
              tx('Open the Prescriptions section in your patient account.'),
            ),

            _faqTile(
              tx('How can I use Emergency SOS?'),
              tx('Open the Emergency section and follow the instructions to request emergency assistance.'),
            ),

            const SizedBox(height: 26),

            Text(
              tx('Contact Support'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF263238),
              ),
            ),

            const SizedBox(height: 12),
            _supportTile(
              icon: Icons.email_outlined,
              title: tx('Email Support'),
              subtitle: tx('Get help through email'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EmailSupportScreen(),
                  ),
                );
              },
            ),
            _supportTile(
              icon: Icons.phone_outlined,
              title: tx('Call Support'),
              subtitle: tx('Speak with our support team'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CallSupportScreen(),
                  ),
                );
              },
            ),

            _supportTile(
              icon: Icons.report_problem_outlined,
              title: tx('Report a Problem'),
              subtitle: tx('Tell us about an issue with the app'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ReportProblemScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // One question that opens to show its answer
  static Widget _faqTile(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconColor: Colors.teal,
        collapsedIconColor: Colors.grey,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // One row in the Contact Support list
  static Widget _supportTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF0)),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.teal, size: 27),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        onTap: onTap,
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 15,
        ),
      ),
    );
  }
}