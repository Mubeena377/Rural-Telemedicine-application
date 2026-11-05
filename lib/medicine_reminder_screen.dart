import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'app_text.dart';
import 'medicine_reminder_service.dart';
import 'medicine_reminder_texts.dart';

// ============================================================
// MEDICINE REMINDER SCREEN
// The patient adds a medicine, chooses the times of day and for
// how many days. The phone then notifies and vibrates at those
// times, even when the app is closed.
// All its texts go through t(), so they follow the chosen language.
// ============================================================

class MedicineReminderScreen extends StatefulWidget {
  const MedicineReminderScreen({super.key});

  @override
  State<MedicineReminderScreen> createState() =>
      _MedicineReminderScreenState();
}

class _MedicineReminderScreenState extends State<MedicineReminderScreen> {
  // The reminders saved on the phone
  List<MedicineReminder> reminders = [];

  // True while loading (shows a spinner)
  bool isLoading = true;

  // False if the phone does not let us fire on the exact minute yet
  bool exactAllowed = true;

  // The medicines from the patient's prescriptions (newest first)
  List<Map<String, dynamic>> prescribedMedicines = [];

  // The choices for "how many days" (0 means until the patient stops it)
  final List<int> dayChoices = const [3, 5, 7, 10, 14, 30, 0];

  // Finds a text in the chosen language (English if it is missing)
  String t(String text) => tt(reminderTexts, text);

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

  // Loads the saved reminders and checks the exact-alarm permission
  Future<void> loadAll() async {
    await MedicineReminderService.init();

    final list = await MedicineReminderService.load();
    final exact = await MedicineReminderService.canFireExactly();
    final prescribed = await loadPrescribedMedicines();

    // If the patient left this screen while waiting, stop here
    if (!mounted) return;

    setState(() {
      reminders = list;
      exactAllowed = exact;
      prescribedMedicines = prescribed;
      isLoading = false;
    });
  }

  // Reads the medicines from the patient's prescriptions (up to 8).
  // If anything goes wrong, the section is simply left out.
  Future<List<Map<String, dynamic>>> loadPrescribedMedicines() async {
    try {
      // The patient ID was saved on the phone when the patient logged in
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getInt('patientId');

      if (patientId == null) return [];

      // Ask the server (function we added in api_service.dart)
      final prescriptions = await ApiService.getPatientPrescriptions(patientId);

      final result = <Map<String, dynamic>>[];

      // The server gives the newest prescription first
      for (final prescription in prescriptions) {
        final medicines = List<Map<String, dynamic>>.from(
          prescription['medicines'] ?? [],
        );

        for (final medicine in medicines) {
          result.add({
            ...medicine,
            'doctor_name': prescription['doctor_name'],
          });
        }

        if (result.length >= 8) break;
      }

      return result;
    } catch (e) {
      return [];
    }
  }

  // "paracetamol" + "500mg" -> "Paracetamol 500mg"
  String prescribedName(Map<String, dynamic> medicine) {
    var name = (medicine['medicine'] ?? '').toString().trim();
    final dose = (medicine['dosage'] ?? '').toString().trim();

    if (name.isNotEmpty) {
      name = name[0].toUpperCase() + name.substring(1);
    }

    return dose.isEmpty ? name : '$name $dose';
  }

  // True if this medicine already has a reminder that is still running
  bool alreadyHasReminder(Map<String, dynamic> medicine) {
    final name = prescribedName(medicine).toLowerCase();
    final now = DateTime.now();

    return reminders.any(
      (reminder) =>
          reminder.name.toLowerCase() == name && !reminder.isFinished(now),
    );
  }

  // One tap: makes a reminder from a prescribed medicine
  Future<void> remindFromPrescription(Map<String, dynamic> medicine) async {
    // Make sure notifications (and exact times) are allowed
    await MedicineReminderService.askPermissions();

    // The times come from the doctor's "how often" text
    final times = MedicineReminderService.suggestTimes(
      (medicine['frequency'] ?? '').toString(),
    );

    // The days come from the prescription (7 if the doctor left it empty)
    var days = 7;
    final fromPrescription = medicine['duration_days'];

    if (fromPrescription is int && fromPrescription > 0) {
      days = fromPrescription;
    }

    if (days > MedicineReminderService.maxDays) {
      days = MedicineReminderService.maxDays;
    }

    await MedicineReminderService.add(
      name: prescribedName(medicine),
      note: (medicine['instructions'] ?? '').toString(),
      times: times,
      days: days,
    );

    if (!mounted) return;

    showMessage('${t('Reminder set for')} ${times.map(timeLabel).join(', ')}.');
    loadAll();
  }

  // "20:30" -> "08:30 PM"
  String timeLabel(String text) {
    final parts = text.split(':');
    var hour = int.parse(parts[0]);
    final minute = parts[1];
    final suffix = hour >= 12 ? 'PM' : 'AM';

    hour = hour % 12;
    if (hour == 0) hour = 12;

    return '${hour.toString().padLeft(2, '0')}:$minute $suffix';
  }

  // A time chosen on the clock -> "20:30"
  String timeToText(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  // 7 -> "7 days", 0 -> "Until I stop" (in the chosen language)
  String daysLabel(int days) =>
      days == 0 ? t('Until I stop') : '$days ${t('days')}';

  // ----------------------------------------------------------
  // ADDING A REMINDER
  // ----------------------------------------------------------

  // Opens the form at the bottom of the screen
  Future<void> showAddSheet() async {
    // These values live only while the form is open
    String name = '';
    String note = '';
    final times = <String>[];
    int days = 7;
    bool saving = false;
    String? error;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Lets the form move up with the keyboard
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        // StatefulBuilder lets the form redraw itself when a choice changes
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                // Keeps the form above the keyboard
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('New medicine reminder'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF26384A),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // The medicine's name
                    TextField(
                      onChanged: (value) => name = value,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: t('Medicine name'),
                        hintText: t('Example: Paracetamol 500 mg'),
                        prefixIcon: const Icon(Icons.medication),
                        filled: true,
                        fillColor: const Color(0xFFF7FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // An optional note
                    TextField(
                      onChanged: (value) => note = value,
                      decoration: InputDecoration(
                        labelText: t('Note (optional)'),
                        hintText: t('Example: after food'),
                        prefixIcon: const Icon(Icons.notes),
                        filled: true,
                        fillColor: const Color(0xFFF7FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // The times of day
                    Text(
                      t('Times of day'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Four big picture buttons for the time of day.
                        // Tap one to choose it, tap again to remove it.
                        ...[
                          [
                            MedicineReminderService.morning,
                            'Morning',
                            Icons.free_breakfast,
                            Colors.orange,
                          ],
                          [
                            MedicineReminderService.afternoon,
                            'Afternoon',
                            Icons.wb_sunny,
                            Colors.amber,
                          ],
                          [
                            MedicineReminderService.evening,
                            'Evening',
                            Icons.wb_twilight,
                            Colors.deepOrange,
                          ],
                          [
                            MedicineReminderService.night,
                            'Night',
                            Icons.bedtime,
                            Colors.indigo,
                          ],
                        ].map((item) {
                          final text = item[0] as String;
                          final color = item[3] as Color;
                          final chosen = times.contains(text);

                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              setSheetState(() {
                                if (chosen) {
                                  times.remove(text);
                                } else if (times.length <
                                    MedicineReminderService.maxTimesPerDay) {
                                  times.add(text);
                                  times.sort();
                                }
                              });
                            },
                            child: Container(
                              width: 76,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: chosen
                                    ? color.withOpacity(0.15)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: chosen
                                      ? color
                                      : const Color(0xFFDCE5EE),
                                  width: chosen ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    item[2] as IconData,
                                    size: 34,
                                    color: color,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t(item[1] as String),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    timeLabel(text),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),

                        // One chip for each custom time (picked from the clock)
                        ...times.where((text) => ![
                              MedicineReminderService.morning,
                              MedicineReminderService.afternoon,
                              MedicineReminderService.evening,
                              MedicineReminderService.night,
                            ].contains(text)).map((text) {
                          return InputChip(
                            avatar: const Icon(Icons.alarm, size: 18),
                            label: Text(timeLabel(text)),
                            onDeleted: () {
                              setSheetState(() {
                                times.remove(text);
                              });
                            },
                          );
                        }),

                        // The button that opens the clock
                        if (times.length < MedicineReminderService.maxTimesPerDay)
                          ActionChip(
                            avatar: const Icon(Icons.add_alarm, size: 18),
                            label: Text(t('Add time')),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(hour: 8, minute: 0),
                              );

                              if (picked == null) return;

                              final text = timeToText(picked);

                              setSheetState(() {
                                if (!times.contains(text)) {
                                  times.add(text);
                                  times.sort();
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // For how many days
                    Text(
                      t('For how long'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: dayChoices.map((choice) {
                        return ChoiceChip(
                          label: Text(daysLabel(choice)),
                          selected: days == choice,
                          onSelected: (_) {
                            setSheetState(() {
                              days = choice;
                            });
                          },
                        );
                      }).toList(),
                    ),

                    // A problem with the form (shown in red)
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],

                    const SizedBox(height: 18),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        // Disabled while the reminder is being saved
                        onPressed: saving
                            ? null
                            : () async {
                                if (name.trim().isEmpty) {
                                  setSheetState(() {
                                    error = t('Please enter the medicine name.');
                                  });
                                  return;
                                }

                                if (times.isEmpty) {
                                  setSheetState(() {
                                    error = t('Please add at least one time.');
                                  });
                                  return;
                                }

                                setSheetState(() {
                                  saving = true;
                                  error = null;
                                });

                                try {
                                  await MedicineReminderService.add(
                                    name: name.trim(),
                                    note: note.trim(),
                                    times: times,
                                    days: days,
                                  );
                                } catch (e) {
                                  setSheetState(() {
                                    saving = false;
                                    error =
                                        '${t('Could not set the reminder:')} $e';
                                  });
                                  return;
                                }

                                if (!mounted) return;

                                // Saved: close the form and reload the list
                                Navigator.pop(sheetContext);
                                showMessage(t('Reminder set.'));
                                loadAll();
                              },
                        icon: const Icon(Icons.check),
                        label: Text(
                          saving ? t('Saving...') : t('Set reminder'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3F6FA8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------------
  // CHANGING AND DELETING
  // ----------------------------------------------------------

  // Asks first, then deletes one reminder
  Future<void> deleteReminder(MedicineReminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t('Delete this reminder?')),
          content: Text(reminder.name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('Cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(t('Delete')),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await MedicineReminderService.remove(reminder.id);

    if (!mounted) return;

    showMessage(t('Reminder deleted.'));
    loadAll();
  }

  // Turns one reminder on or off
  Future<void> toggleReminder(MedicineReminder reminder, bool value) async {
    await MedicineReminderService.setEnabled(reminder.id, value);

    if (!mounted) return;

    loadAll();
  }

  // Sends a test notification right now
  Future<void> sendTest() async {
    await MedicineReminderService.askPermissions();
    await MedicineReminderService.showTest();

    if (!mounted) return;

    showMessage(t('Test sent. The phone should vibrate for about 15 seconds.'));
  }

  // ----------------------------------------------------------
  // SMALL BUILDING BLOCKS
  // ----------------------------------------------------------

  // The blue banner at the top
  Widget banner() {
    return Container(
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('Medicine Reminder'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t('Never forget to take your medicine.'),
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
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
            child: const Icon(Icons.alarm, size: 40, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // The orange warning when exact times are not allowed yet
  Widget exactAlarmWarning() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('To get reminders exactly on time, allow "Alarms & reminders" for this app.'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () async {
              await MedicineReminderService.askPermissions();
              await loadAll();
            },
            child: Text(t('Allow')),
          ),
        ],
      ),
    );
  }

  // The card for one reminder
  Widget reminderCard(MedicineReminder reminder) {
    final finished = reminder.isFinished(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.teal.withOpacity(0.12),
                  child: const Icon(
                    Icons.medication,
                    color: Colors.teal,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (reminder.note.isNotEmpty)
                        Text(
                          reminder.note,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      Text(
                        finished ? t('Finished') : daysLabel(reminder.days),
                        style: TextStyle(
                          fontSize: 12,
                          color: finished ? Colors.red : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),

                // The on/off switch
                Switch(
                  value: reminder.enabled && !finished,
                  onChanged: finished
                      ? null
                      : (value) => toggleReminder(reminder, value),
                ),

                // The delete button
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: t('Delete'),
                  onPressed: () => deleteReminder(reminder),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // The times of day
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: reminder.times.map((text) {
                return Chip(
                  avatar: const Icon(Icons.alarm, size: 16),
                  label: Text(timeLabel(text)),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // A friendly message with a big icon (used when the list is empty)
  Widget emptyMessage() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5EE)),
      ),
      child: Column(
        children: [
          const Icon(Icons.alarm_add, size: 56, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            t('No reminders yet.\nTap "Add reminder" to set one.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // A card for one medicine from the prescriptions, with a big button
  Widget prescribedCard(Map<String, dynamic> medicine) {
    final done = alreadyHasReminder(medicine);

    // Build a short line like "twice daily • 3 days"
    final details = <String>[];

    if ((medicine['frequency'] ?? '').toString().isNotEmpty) {
      details.add(medicine['frequency'].toString());
    }

    if (medicine['duration_days'] != null) {
      details.add('${medicine['duration_days']} ${t('days')}');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: Colors.teal.withOpacity(0.12),
              child: const Icon(
                Icons.medication,
                color: Colors.teal,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prescribedName(medicine),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details.join(' • '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // The big one-tap button, or a green tick
            done
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 34,
                      ),
                      Text(
                        t('Reminder set'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  )
                : ElevatedButton.icon(
                    onPressed: () => remindFromPrescription(medicine),
                    icon: const Icon(Icons.alarm_add),
                    label: Text(t('Remind me')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F6FA8),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(t('Medicine Reminder')),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showAddSheet,
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alarm),
        label: Text(t('Add reminder')),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // Extra space at the bottom so the button never hides a card
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                banner(),
                if (!exactAllowed) exactAlarmWarning(),

                const SizedBox(height: 14),

                // Lets the patient check the vibration straight away
                OutlinedButton.icon(
                  onPressed: sendTest,
                  icon: const Icon(Icons.vibration),
                  label: Text(t('Test the alarm')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ----- One-tap reminders from the prescriptions -----
                if (prescribedMedicines.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.medication, color: Color(0xFF3F6FA8)),
                      const SizedBox(width: 8),
                      Text(
                        t('From your prescriptions'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF26384A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  ...prescribedMedicines.map(prescribedCard),

                  const SizedBox(height: 12),
                ],

                // ----- All the patient's reminders -----
                Row(
                  children: [
                    const Icon(Icons.alarm, color: Color(0xFF3F6FA8)),
                    const SizedBox(width: 8),
                    Text(
                      t('My reminders'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF26384A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (reminders.isEmpty)
                  emptyMessage()
                else
                  ...reminders.map(reminderCard),
              ],
            ),
    );
  }
}