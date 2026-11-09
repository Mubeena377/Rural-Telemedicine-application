import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ============================================================
// MEDICINE REMINDERS
// Reminders are saved on the phone and fire as scheduled
// notifications, even with no internet and even if the app is
// closed. Each one vibrates the phone for about 15 seconds.
// ============================================================

// One reminder: a medicine, the times of day, and for how long
class MedicineReminder {
  final int id; // A small number that identifies this reminder
  final String name; // For example "Paracetamol 500mg"
  final String note; // For example "after food" (can be empty)
  final List<String> times; // Like ["08:00", "20:30"] (24-hour text)
  final int days; // How many days, or 0 = until the patient stops it
  final String startDate; // The day it was created, like "2026-10-27"
  final bool enabled; // The on/off switch

  const MedicineReminder({
    required this.id,
    required this.name,
    required this.note,
    required this.times,
    required this.days,
    required this.startDate,
    required this.enabled,
  });

  // A copy of this reminder with some values changed
  MedicineReminder copyWith({bool? enabled}) {
    return MedicineReminder(
      id: id,
      name: name,
      note: note,
      times: times,
      days: days,
      startDate: startDate,
      enabled: enabled ?? this.enabled,
    );
  }

  // Turns the reminder into text so it can be saved on the phone
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'times': times,
        'days': days,
        'startDate': startDate,
        'enabled': enabled,
      };

  // Builds a reminder from the saved text
  factory MedicineReminder.fromJson(Map<String, dynamic> json) {
    return MedicineReminder(
      id: json['id'] as int,
      name: (json['name'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      times: List<String>.from(json['times'] ?? []),
      days: json['days'] as int? ?? 0,
      startDate: (json['startDate'] ?? '').toString(),
      enabled: json['enabled'] != false,
    );
  }

  // True when a limited reminder has passed its last dose
  bool isFinished(DateTime now) {
    if (days == 0 || times.isEmpty) return false;

    final start = DateTime.parse(startDate);
    final lastTime = times.last.split(':'); // The latest time of the day

    final end = DateTime(
      start.year,
      start.month,
      start.day + days - 1,
      int.parse(lastTime[0]),
      int.parse(lastTime[1]),
    );

    return now.isAfter(end);
  }
}

class MedicineReminderService {
  // The notification system of the phone. It is the same one that
  // main.dart already started.
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _storageKey = 'medicine_reminders';
  static const String _counterKey = 'medicine_reminder_counter';

  // A NEW channel name on purpose: Android never changes the sound of a
  // channel it already has, so the alarm sound needs a fresh channel.
  static const String channelId = 'medicine_alarm_v2';

  // The most reminders and days we allow, so ids never clash
  static const int maxTimesPerDay = 4;
  static const int maxDays = 60;

  static bool _ready = false;

  // The vibration: 1 second on, half a second off, ten times (about 15 s)
  static Int64List get vibrationPattern {
    final pattern = <int>[0];

    for (var i = 0; i < 10; i++) {
      pattern.add(1000);
      pattern.add(500);
    }

    return Int64List.fromList(pattern);
  }

  // How the notification looks and behaves
  static NotificationDetails _details() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Medicine alarm',
        channelDescription: 'Reminds you to take your medicine',
        importance: Importance.max,
        priority: Priority.high,

        // Play our own 10-second alarm file (res/raw/medicine_alarm.mp3).
        // Write the name without the .mp3
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('medicine_alarm'),

        // Use the phone's ALARM volume, like a real alarm clock
        audioAttributesUsage: AudioAttributesUsage.alarm,

        // No vibration, sound only
        enableVibration: false,

        category: AndroidNotificationCategory.alarm,
      ),
    );
  }

  // Gets everything ready. It is safe to call many times.
  static Future<void> init() async {
    if (_ready) return;

    // Reminder times are in Indian time
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

        // The Android part of the notification plugin (needed for channels)
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Remove the old channel (it still vibrates) so only the alarm remains
    await android?.deleteNotificationChannel('medicine_reminders_v1');

    // Create the alarm channel: own sound, no vibration
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        'Medicine alarm',
        description: 'Reminds you to take your medicine',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('medicine_alarm'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: false,
      ),
    );

    _ready = true;
  }

  // Asks the patient to allow notifications and exact alarm times.
  // The second one opens a phone settings page.
  static Future<void> askPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await android?.requestNotificationsPermission();

    final canExact = await android?.canScheduleExactNotifications() ?? false;

    if (!canExact) {
      await android?.requestExactAlarmsPermission();
    }
  }

  // True if the phone lets us fire reminders on the exact minute
  static Future<bool> canFireExactly() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    return await android?.canScheduleExactNotifications() ?? false;
  }

  // Each notification needs its own number. This builds it from the
  // reminder, the time of day (0 to 3) and the day (0 to 99).
  static int _notificationId(int reminderId, int timeIndex, int dayIndex) {
    return reminderId * 1000 + timeIndex * 100 + dayIndex;
  }

  // ----------------------------------------------------------
  // SAVED REMINDERS
  // ----------------------------------------------------------

  // Reads all reminders saved on the phone
  static Future<List<MedicineReminder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_storageKey);

    if (text == null || text.isEmpty) return [];

    try {
      final list = jsonDecode(text) as List<dynamic>;

      return list
          .map((item) =>
              MedicineReminder.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      // If the saved text is damaged, start with an empty list
      return [];
    }
  }

  // Saves the list of reminders on the phone
  static Future<void> _save(List<MedicineReminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _storageKey,
      jsonEncode(reminders.map((r) => r.toJson()).toList()),
    );
  }

  // ----------------------------------------------------------
  // SCHEDULING
  // ----------------------------------------------------------

  // Sets up the notifications of one reminder (replacing old ones)
  static Future<void> schedule(MedicineReminder reminder) async {
    await init();

    // Remove anything scheduled earlier for this reminder
    await cancel(reminder.id);

    if (!reminder.enabled) return;

    // Exact timing only works if the patient allowed it
    final mode = await canFireExactly()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final now = tz.TZDateTime.now(tz.local);
    final start = DateTime.parse(reminder.startDate);

    final body = reminder.note.isEmpty
        ? 'Time to take ${reminder.name}.'
        : 'Time to take ${reminder.name}. ${reminder.note}';

    for (var t = 0; t < reminder.times.length; t++) {
      final parts = reminder.times[t].split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      if (reminder.days == 0) {
        // "Until I stop": one notification that repeats every day
        var first = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        );

        // Today's time has already passed: start tomorrow
        if (!first.isAfter(now)) {
          first = first.add(const Duration(days: 1));
        }

        await _plugin.zonedSchedule(
          _notificationId(reminder.id, t, 0),
          'Medicine reminder',
          body,
          first,
          _details(),
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        // A limited number of days: one notification for each day
        for (var d = 0; d < reminder.days && d < maxDays; d++) {
          final when = tz.TZDateTime(
            tz.local,
            start.year,
            start.month,
            start.day + d,
            hour,
            minute,
          );

          // Skip times that have already passed
          if (!when.isAfter(now)) continue;

          await _plugin.zonedSchedule(
            _notificationId(reminder.id, t, d),
            'Medicine reminder',
            body,
            when,
            _details(),
            androidScheduleMode: mode,
          );
        }
      }
    }
  }

  // Removes every scheduled notification of one reminder
  static Future<void> cancel(int reminderId) async {
    for (var t = 0; t < maxTimesPerDay; t++) {
      for (var d = 0; d < maxDays; d++) {
        await _plugin.cancel(_notificationId(reminderId, t, d));
      }
    }
  }

  // ----------------------------------------------------------
  // WHAT THE SCREEN USES
  // ----------------------------------------------------------

  // Creates a new reminder, saves it and schedules it
  static Future<MedicineReminder> add({
    required String name,
    required String note,
    required List<String> times, // Like "08:00"
    required int days, // 0 = until the patient stops it
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // A small increasing number for each new reminder
    final id = (prefs.getInt(_counterKey) ?? 0) + 1;
    await prefs.setInt(_counterKey, id);

    final today = DateTime.now();

    final sortedTimes = [...times]..sort();

    final reminder = MedicineReminder(
      id: id,
      name: name,
      note: note,
      times: sortedTimes,
      days: days,
      startDate:
          '${today.year.toString().padLeft(4, '0')}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}',
      enabled: true,
    );

    final all = await load();
    all.add(reminder);
    await _save(all);

    await schedule(reminder);

    return reminder;
  }

  // Turns a reminder on or off
  static Future<void> setEnabled(int id, bool enabled) async {
    final all = await load();
    final updated = <MedicineReminder>[];

    for (final reminder in all) {
      if (reminder.id == id) {
        final changed = reminder.copyWith(enabled: enabled);
        updated.add(changed);
        await schedule(changed); // Sets up or removes the notifications
      } else {
        updated.add(reminder);
      }
    }

    await _save(updated);
  }

  // Deletes a reminder
  static Future<void> remove(int id) async {
    await cancel(id);

    final all = await load();
    all.removeWhere((reminder) => reminder.id == id);
    await _save(all);
  }

  // The four parts of the day, with a sensible time for each
  static const String morning = '08:00';
  static const String afternoon = '14:00';
  static const String evening = '18:00';
  static const String night = '21:00';

  // Turns the doctor's "how often" text into times of day.
  // It understands words ("twice daily", "three times a day"),
  // short forms ("OD", "BD", "TDS", "QID"), "every 8 hours" and the
  // Indian "1-0-1" style (morning - afternoon - night).
  // If the text is not understood, it gives one morning dose.
  static List<String> suggestTimes(String frequency) {
    final text = frequency.toLowerCase().trim();

    // "1-0-1": a number for each of morning, afternoon and night.
    // A 0 means "not at that time".
    final dashed = RegExp(r'^(\d)\s*-\s*(\d)\s*-\s*(\d)$').firstMatch(text);

    if (dashed != null) {
      final times = <String>[];

      if (dashed.group(1) != '0') times.add(morning);
      if (dashed.group(2) != '0') times.add(afternoon);
      if (dashed.group(3) != '0') times.add(night);

      if (times.isNotEmpty) return times;
    }

    // "every 6 hours", "every 8 hours", "every 12 hours"
    final every = RegExp(r'every\s*(\d+)\s*h').firstMatch(text);

    if (every != null) {
      final hours = int.parse(every.group(1)!);

      if (hours <= 6) return [morning, afternoon, evening, night];
      if (hours <= 8) return [morning, afternoon, night];
      if (hours <= 12) return [morning, night];
    }

    // Four times a day
    if (RegExp(r'\b(qid|four|4)\b').hasMatch(text)) {
      return [morning, afternoon, evening, night];
    }

    // Three times a day
    if (RegExp(r'\b(tds|tid|thrice|three|3)\b').hasMatch(text)) {
      return [morning, afternoon, night];
    }

    // Twice a day
    if (RegExp(r'\b(bd|bid|twice|two|2)\b').hasMatch(text)) {
      return [morning, night];
    }

    // Once a day, with a clue about when
    if (RegExp(r'\b(night|bedtime|hs)\b').hasMatch(text)) return [night];
    if (text.contains('evening')) return [evening];
    if (text.contains('afternoon')) return [afternoon];

    // Anything else: one dose in the morning
    return [morning];
  }

  // Shows a test notification right now, with the same 15-second
  // vibration, so the patient can check it works
  static Future<void> showTest() async {
    await init();

    await _plugin.show(
      2000000001,
      'Medicine reminder (test)',
      'This is how your reminder will look and feel.',
      _details(),
    );
  }
}