import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

// ============================================================
// SOS ALERT PHONE REGISTRATION (ambulances and hospitals)
// A logged-in ambulance or hospital tells the server which phone
// to send SOS alerts to. At logout the phone is removed again.
// ============================================================

// Gives this phone's token to the server, for the logged-in
// ambulance or hospital. Does nothing if nobody is logged in.
Future<void> registerResponderPhone() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final responderId = prefs.getInt('responderId');

    // Nobody is logged in as an ambulance or hospital
    if (responderId == null) return;

    // The phone's Firebase token
    final token = await FirebaseMessaging.instance.getToken();

    if (token == null) return;

    await ApiService.saveResponderDeviceToken(
      responderId: responderId,
      token: token,
    );
  } catch (e) {
    // If this fails, the SOS alert will not arrive, but the app still works
    debugPrint('Could not register the responder phone: $e');
  }
}

// Removes this phone from the server's alert list. Call it at logout,
// BEFORE the saved responderId is cleared.
Future<void> unregisterResponderPhone() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final responderId = prefs.getInt('responderId');

    if (responderId == null) return;

    final token = await FirebaseMessaging.instance.getToken();

    if (token == null) return;

    await http.delete(
      Uri.parse(
        '${ApiService.baseUrl}/api/responders/$responderId/device-token',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token}),
    );
  } catch (e) {
    debugPrint('Could not remove the responder phone: $e');
  }
}

// An invisible widget. Put it on a dashboard: each time the dashboard
// opens (after login, after registration, or when the app starts),
// it registers the phone for SOS alerts.
class ResponderPhoneRegistrar extends StatefulWidget {
  const ResponderPhoneRegistrar({super.key});

  @override
  State<ResponderPhoneRegistrar> createState() =>
      _ResponderPhoneRegistrarState();
}

class _ResponderPhoneRegistrarState extends State<ResponderPhoneRegistrar> {
  @override
  void initState() {
    super.initState();
    registerResponderPhone();
  }

  @override
  Widget build(BuildContext context) {
    // Shows nothing on the screen
    return const SizedBox.shrink();
  }
}