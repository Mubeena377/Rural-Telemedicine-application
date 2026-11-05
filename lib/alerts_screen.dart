import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'alerts_text.dart'; // tx() shows text in the chosen language


// ============================================================
// ALERTS SCREEN
// Opens from "Alerts" in the profile. It shows:
//  - four switches that decide which push notifications arrive
//  - the list of past notifications (unread ones are marked)
// All fixed text goes through tx(), so it follows the chosen language.
// ============================================================

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  // The logged-in patient (read from the phone when the screen opens)
  int? patientId;

  // Data loaded from the server
  List<Map<String, dynamic>> notifications = [];

  // The four switches (true = push notifications on)
  Map<String, bool> settings = {
    'appointments': true,
    'reminders': true,
    'prescriptions': true,
    'orders': true,
  };

  // True while loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // The four switches: the word the server expects, and how each
  // one looks on the screen. The title and subtitle are kept in English
  // here and translated with tx() when they are drawn.
  final List<Map<String, dynamic>> switchInfo = const [
    {
      'key': 'appointments',
      'title': 'Appointment updates',
      'subtitle': 'Requests, accepted or rejected, cancelled, doctor is ready',
      'icon': Icons.event_available,
      'color': Color(0xFF3F6FA8),
    },
    {
      'key': 'reminders',
      'title': 'Reminders',
      'subtitle': 'Before an appointment, and follow-up dates',
      'icon': Icons.alarm,
      'color': Colors.orange,
    },
    {
      'key': 'prescriptions',
      'title': 'Prescriptions',
      'subtitle': 'When a doctor issues a prescription',
      'icon': Icons.medication,
      'color': Colors.teal,
    },
    {
      'key': 'orders',
      'title': 'Medicine orders',
      'subtitle': 'When your order is confirmed, sent or delivered',
      'icon': Icons.local_shipping,
      'color': Colors.purple,
    },
  ];

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadAll(); // Start loading right away
  }

  // Shows a short message at the bottom of the screen
  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Loads the notifications and the switches from the server
  Future<void> loadAll() async {
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
          // Kept in English here; it is translated when it is drawn
          errorMessage =
              'Patient information not found. Please log in again.';
        });
        return;
      }

      // Ask the server for both at the same time
      final list = await ApiService.getAllNotifications(id);
      final loadedSettings = await ApiService.getNotificationSettings(id);

      // If the patient left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        patientId = id;
        notifications = list;
        settings = loadedSettings;
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

  // The patient flips one switch
  Future<void> changeSwitch(String key, bool value) async {
    final id = patientId;
    if (id == null) return;

    // Show the new position right away
    setState(() {
      settings[key] = value;
    });

    final saved = await ApiService.saveNotificationSetting(
      patientId: id,
      category: key,
      enabled: value,
    );

    if (!mounted) return;

    // The server did not save it: put the switch back
    if (!saved) {
      setState(() {
        settings[key] = !value;
      });
      showMessage(tx('Could not save this setting. Please try again.'));
    }
  }

  // Marks every notification as read
  Future<void> markAllRead() async {
    final id = patientId;
    if (id == null) return;

    await ApiService.markAllNotificationsRead(id);

    if (!mounted) return;

    // Show them as read on the screen straight away
    setState(() {
      notifications = notifications
          .map((item) => {...item, 'is_read': true})
          .toList();
    });
  }

  // The icon and colour for each kind of notification
  Map<String, dynamic> typeInfo(String type) {
    switch (type) {
      case 'AppointmentRequest':
        return {'icon': Icons.event_note, 'color': Colors.blue};
      case 'AppointmentAccepted':
        return {'icon': Icons.event_available, 'color': Colors.green};
      case 'AppointmentRejected':
        return {'icon': Icons.event_busy, 'color': Colors.red};
      case 'AppointmentCancelled':
        return {'icon': Icons.cancel_outlined, 'color': Colors.red};
      case 'ConsultationStarted':
        return {'icon': Icons.videocam, 'color': Colors.green};
      case 'AppointmentReminder':
        return {'icon': Icons.alarm, 'color': Colors.orange};
      case 'FollowUpReminder':
        return {'icon': Icons.event_repeat, 'color': Colors.orange};
      case 'PrescriptionIssued':
        return {'icon': Icons.medication, 'color': Colors.teal};
      case 'OrderStatus':
        return {'icon': Icons.local_shipping, 'color': Colors.purple};
      default:
        return {'icon': Icons.notifications, 'color': Colors.blueGrey};
    }
  }

  // ----------------------------------------------------------
  // SMALL BUILDING BLOCKS
  // ----------------------------------------------------------

  // A section title with an icon (and an optional button on the right)
  Widget sectionHeader(String title, IconData icon, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF3F6FA8), size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // One switch row
  Widget switchTile(Map<String, dynamic> info) {
    final key = info['key'] as String;
    final color = info['color'] as Color;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        secondary: CircleAvatar(
          radius: 24,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(info['icon'] as IconData, color: color, size: 26),
        ),
        // The title is translated into the chosen language
        title: Text(
          tx(info['title'] as String),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        // The small line under the title is translated too
        subtitle: Text(
          tx(info['subtitle'] as String),
          style: const TextStyle(fontSize: 12),
        ),
        value: settings[key] ?? true,
        onChanged: (value) => changeSwitch(key, value),
      ),
    );
  }

  // One notification in the list
  // (the title and message come from the server, so they stay as sent)
  Widget notificationCard(Map<String, dynamic> item) {
    final info = typeInfo((item['type'] ?? '').toString());
    final color = info['color'] as Color;
    final unread = item['is_read'] != true;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: unread ? 3 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(info['icon'] as IconData, color: color, size: 28),
        ),
        title: Text(
          (item['title'] ?? '').toString(),
          style: TextStyle(
            fontWeight: unread ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((item['message'] ?? '').toString()),
              const SizedBox(height: 4),
              Text(
                (item['created_at'] ?? '').toString(),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        // A small blue dot marks the unread ones
        trailing: unread
            ? const Icon(Icons.circle, size: 12, color: Color(0xFF3F6FA8))
            : null,
      ),
    );
  }

  // A friendly message with a big icon (used when the list is empty)
  Widget emptyMessage(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5EE)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 46, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Everything that is shown once the data has loaded
  Widget content() {
    final hasUnread = notifications.any((item) => item['is_read'] != true);

    return RefreshIndicator(
      onRefresh: loadAll, // Pull down to refresh
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ----- The blue banner -----
          Container(
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
                // No "const" here any more, because the text is translated
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tx('Alerts'),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tx('Choose which notifications you receive.'),
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70),
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
                  child: const Icon(
                    Icons.notifications_active,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // ----- The four switches -----
          sectionHeader(tx('Push notifications'), Icons.tune),
          ...switchInfo.map(switchTile),

          // ----- The list of notifications -----
          sectionHeader(
            tx('Recent notifications'),
            Icons.history,
            trailing: hasUnread
                ? TextButton(
                    onPressed: markAllRead,
                    child: Text(tx('Mark all as read')),
                  )
                : null,
          ),

          if (notifications.isEmpty)
            emptyMessage(
              Icons.notifications_none,
              tx('No notifications yet. They will appear here.'),
            )
          else
            ...notifications.map(notificationCard),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Decides what to show: spinner, error, or the content
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
              // tx() translates the messages we wrote ourselves; any other
              // error text from the server is shown as it is
              Text(
                tx(errorMessage!),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: loadAll,
                icon: const Icon(Icons.refresh),
                label: Text(tx('Retry')),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Loaded: show everything
    return content();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(tx('Alerts')),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: buildBody(),
    );
  }
}