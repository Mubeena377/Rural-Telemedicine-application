import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

// ============================================================
// RESPONDER LOGIN SCREEN
// One screen for both the ambulance team and the hospital.
// It works in three steps, like the patient and doctor logins:
//   1. SEND OTP: checks that the phone number is registered
//   2. VERIFY:   the test OTP is 123456
//   3. LOGIN:    opens the dashboard
// After login the phone remembers them, so the app opens straight
// to their dashboard the next time.
// ============================================================

class ResponderLoginScreen extends StatefulWidget {
  // "Ambulance" or "Hospital"
  final String type;

  // Gives back the dashboard to open after login. main.dart supplies
  // it, so this file does not need to import main.dart.
  final Widget Function() dashboardBuilder;

  // Gives back the registration screen (for "New here? Register")
  final Widget Function() registrationBuilder;

  const ResponderLoginScreen({
    super.key,
    required this.type,
    required this.dashboardBuilder,
    required this.registrationBuilder,
  });

  @override
  State<ResponderLoginScreen> createState() => _ResponderLoginScreenState();
}

class _ResponderLoginScreenState extends State<ResponderLoginScreen> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController otpController = TextEditingController();

  // True while the phone number is being checked (shows a spinner)
  bool isLoading = false;

  // Step 1 done: the phone number is registered and the OTP was "sent"
  bool otpSent = false;

  // Step 2 done: the OTP was entered correctly
  bool otpVerified = false;

  // The account details the server gave back in step 1
  Map<String, dynamic>? responder;

  bool get isAmbulance => widget.type == 'Ambulance';

  // Red for ambulance, green for hospital (like their dashboards)
  Color get themeColor => isAmbulance ? Colors.red : Colors.green;

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  // Shows a short message at the bottom of the screen
  void showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  // If the phone number is changed, the steps start again
  void resetSteps() {
    if (otpSent || otpVerified) {
      setState(() {
        otpSent = false;
        otpVerified = false;
        responder = null;
        otpController.clear();
      });
    }
  }

  // STEP 1: checks with the server that this phone number is registered
  Future<void> sendOtp() async {
    final phone = phoneController.text.trim();

    if (phone.length != 10) {
      showMessage('Please enter a valid 10-digit phone number.');
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/responders/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'type': widget.type, 'phone': phone}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 && data['status'] == 'success') {
        setState(() {
          responder = Map<String, dynamic>.from(data['responder']);
          otpSent = true;
          otpVerified = false;
        });
        showMessage('OTP sent. Test OTP: 123456');
      } else {
        showMessage((data['message'] ?? 'Could not check the number').toString());
      }
    } catch (e) {
      if (!mounted) return;
      showMessage('Connection error. Please try again.');
    }

    if (mounted) setState(() => isLoading = false);
  }

  // STEP 2: checks the OTP (the test OTP is 123456)
  void verifyOtp() {
    if (otpController.text.trim() == '123456') {
      setState(() => otpVerified = true);
      showMessage('Phone number verified.');
    } else {
      showMessage('Incorrect OTP.');
    }
  }

  // Remembers this login on the phone, so the next app start opens
  // the dashboard directly
  Future<void> saveLogin(Map<String, dynamic> account, String phone) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(
      'responderId',
      int.parse(account['responder_id'].toString()),
    );
    await prefs.setString('responderType', widget.type);

    if (isAmbulance) {
      await prefs.setBool('ambulanceRegistered', true);
      await prefs.setString(
        'ambulanceTeamName',
        (account['name'] ?? '').toString(),
      );
      await prefs.setString('ambulancePhone', phone);
      await prefs.setString(
        'ambulanceNumber',
        (account['vehicle_number'] ?? '').toString(),
      );
      await prefs.setString(
        'ambulanceDriverName',
        (account['contact_person'] ?? '').toString(),
      );
    } else {
      await prefs.setBool('hospitalRegistered', true);
    }
  }

  // STEP 3: saves the login and opens the dashboard
  Future<void> login() async {
    final account = responder;

    if (!otpVerified || account == null) {
      showMessage('Please verify your phone number first.');
      return;
    }

    await saveLogin(account, phoneController.text.trim());

    if (!mounted) return;

    // Open the dashboard and forget the screens behind it
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => widget.dashboardBuilder()),
      (route) => false,
    );
  }

  // The OTP box with its Verify button (shown after step 1)
  Widget otpRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: otpController,
            enabled: !otpVerified,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'OTP',
              prefixIcon: const Icon(Icons.lock_outline),
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            // After a successful check the button is switched off
            onPressed: otpVerified ? null : verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(otpVerified ? 'Verified' : 'Verify'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('${widget.type} Login'),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 44,
              backgroundColor: themeColor.withOpacity(0.12),
              child: Icon(
                isAmbulance ? Icons.local_shipping : Icons.local_hospital,
                size: 46,
                color: themeColor,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isAmbulance ? 'Ambulance Team' : 'Hospital',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Login with the phone number you registered with',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 28),

            // The phone number
            TextField(
              controller: phoneController,
              enabled: !isLoading,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              // Changing the number starts the steps again
              onChanged: (_) => resetSteps(),
              decoration: InputDecoration(
                labelText: 'Phone number',
                prefixIcon: const Icon(Icons.phone_outlined),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // STEP 1 button, until the OTP was sent
            if (!otpSent)
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: isLoading ? null : sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'SEND OTP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

            // STEP 2 and 3, after the OTP was sent
            if (otpSent) ...[
              otpRow(),
              const SizedBox(height: 6),
              // Test OTP hint (delete this line when a real OTP is added)
              const Text(
                'Test OTP: 123456',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  // Switched on only after the OTP is verified
                  onPressed: otpVerified ? login : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'LOGIN',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 14),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => widget.registrationBuilder(),
                        ),
                      );
                    },
              child: Text(
                isAmbulance
                    ? 'New ambulance team? Register here'
                    : 'New hospital? Register here',
              ),
            ),
          ],
        ),
      ),
    );
  }
}