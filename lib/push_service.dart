import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'video_call_screen.dart';

// ============================================================
// PUSH NOTIFICATIONS
// - asks the patient for permission to show notifications
// - sends this phone's token to the server
// - opens the video call when the patient taps "Your doctor is ready"
// ============================================================

// A key that lets us open screens from outside any widget.
// It is connected to the app in main.dart.
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>();

// True once Firebase started correctly
bool pushReady = false;

// Makes sure we listen for token changes only once
bool _tokenListenerAdded = false;

// Completes when push setup has finished (successfully or not)
final Completer<void> _initDone = Completer<void>();

// Waits (at most 15 seconds) for push setup to finish
Future<void> _waitForPush() async {
  await _initDone.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () {},
  );
}

// The notification that opened the app when it was fully closed
RemoteMessage? _launchMessage;

// ------------------------------------------------------------
// Starts Firebase. It is called once, from main().
// If anything goes wrong, the app still works without push.
// ------------------------------------------------------------
Future<void> initPush(
  FlutterLocalNotificationsPlugin localPlugin,
) async {
  try {
    // Starts Firebase (uses android/app/google-services.json)
    await Firebase.initializeApp();

    // The "channel" is the group of notification settings Android uses.
    // Its name must match the channel_id the server sends.
    const channel = AndroidNotificationChannel(
      'consultation_alerts',
      'Consultation alerts',
      description: 'Tells you when your doctor starts the consultation',
      importance: Importance.max,
    );

    await localPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Asks the patient: "Allow notifications?" (Android 13 and newer)
        // Asks the patient: "Allow notifications?" (Android 13 and newer).
    // No "await" here on purpose: the app must start right away and not
    // wait for the patient to answer the popup.
    FirebaseMessaging.instance.requestPermission();

    // The patient tapped a notification while the app was in the background
    FirebaseMessaging.onMessageOpenedApp.listen(_openCallFromMessage);

    // The patient tapped a notification while the app was fully closed.
    // We keep it, and the home screen opens the call once it is ready.
    _launchMessage = await FirebaseMessaging.instance.getInitialMessage();

    pushReady = true;
  } catch (e) {
    print('Push setup failed: $e');
  } finally {
    // Tell the functions that wait for push that setup is finished
    if (!_initDone.isCompleted) _initDone.complete();
  }
}

// ------------------------------------------------------------
// Opens the video call for a "doctor is ready" notification
// ------------------------------------------------------------
Future<void> _openCallFromMessage(RemoteMessage message) async {
  // Only handle our own kind of notification
  if (message.data['type'] != 'ConsultationStarted') return;

  // The server sends the appointment number as text
  final appointmentId = int.tryParse(
    (message.data['appointment_id'] ?? '').toString(),
  );

  if (appointmentId == null) return;

  // The patient ID was saved on the phone when the patient logged in
  final prefs = await SharedPreferences.getInstance();
  final patientId = prefs.getInt('patientId');

  if (patientId == null) return;

  // The app's navigator (it can be empty if the app is not ready yet)
  final navigator = appNavigatorKey.currentState;

  if (navigator == null) return;

  navigator.push(
    MaterialPageRoute(
      builder: (context) => VideoCallScreen(
        appointmentId: appointmentId,
        participantId: patientId,
        participantRole: 'patient',
      ),
    ),
  );
}

// ------------------------------------------------------------
// Called by the patient home screen when it opens: if the app was
// started by tapping a notification, open that video call now.
// ------------------------------------------------------------
Future<void> openLaunchNotificationIfAny() async {
  final message = _launchMessage;

  if (message == null) return;

  // Use it only once
  _launchMessage = null;

  await _openCallFromMessage(message);
}

// ------------------------------------------------------------
// Sends this phone's token to the server for the logged-in patient.
// Called by the patient home screen when it opens.
// ------------------------------------------------------------
Future<void> registerPatientPushToken() async {
  // Do nothing if Firebase did not start
  await _waitForPush();
  if (!pushReady) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getInt('patientId');

    if (patientId == null) return;

    // This phone's token (null if Firebase cannot give one yet)
    final token = await FirebaseMessaging.instance.getToken();

    if (token == null) return;

    await ApiService.saveDeviceToken(
      patientId: patientId,
      token: token,
    );

    // Firebase sometimes changes the token. Send the new one too.
    if (!_tokenListenerAdded) {
      _tokenListenerAdded = true;

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        ApiService.saveDeviceToken(
          patientId: patientId,
          token: newToken,
        );
      });
    }
  } catch (e) {
    print('Could not register push token: $e');
  }
}

// ------------------------------------------------------------
// Sends this phone's token to the server for the logged-in doctor.
// Called automatically from doctor_session.dart.
// ------------------------------------------------------------
Future<void> registerDoctorPushToken(int doctorId) async {
  // Do nothing if Firebase did not start
  await _waitForPush();
  if (!pushReady) return;

  try {
    // This phone's token (null if Firebase cannot give one yet)
    final token = await FirebaseMessaging.instance.getToken();

    if (token == null) return;

    await ApiService.saveDoctorDeviceToken(
      doctorId: doctorId,
      token: token,
    );
  } catch (e) {
    print('Could not register doctor push token: $e');
  }
}

// ------------------------------------------------------------
// Tells the server to forget this phone. Used when someone logs
// out, so the phone stops receiving that person's notifications.
// ------------------------------------------------------------
Future<void> forgetThisPhone() async {
  // Do nothing if Firebase did not start
  await _waitForPush();
  if (!pushReady) return;

  try {
    final token = await FirebaseMessaging.instance.getToken();

    if (token == null) return;

    await ApiService.deleteDeviceToken(token);
  } catch (e) {
    print('Could not forget this phone: $e');
  }
}