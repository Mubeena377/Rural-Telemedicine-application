import 'dart:async';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'video_call_screen.dart';

// ============================================================
// DOCTOR CONSULTATIONS SCREEN
// Shows the appointments the doctor has ACCEPTED (status Scheduled).
//  - Upcoming: the appointment time has not ended yet
//  - Past: the time has gone but the consultation was never
//    completed (finished ones are in Consultation History)
// The Start button works only once the appointment time arrives.
// Each card also has:
//  - Cancel: the doctor cancels the appointment (the patient is told)
//  - Notes & Complete: opens the form where the doctor writes the
//    consultation notes. Saving it completes the appointment and
//    moves it to Consultation History.
// ============================================================

class DoctorConsultationQueueScreen extends StatefulWidget {
  final int doctorId;

  // Gives back the screen where the doctor writes the consultation
  // notes. main.dart supplies it, so this file does not need to
  // import main.dart.
  final Widget Function(
    Map<String, dynamic> consultation,
    int appointmentId,
  ) notesScreenBuilder;

  const DoctorConsultationQueueScreen({
    super.key,
    required this.doctorId,
    required this.notesScreenBuilder,
  });

  @override
  State<DoctorConsultationQueueScreen> createState() =>
      _DoctorConsultationQueueScreenState();
}

class _DoctorConsultationQueueScreenState
    extends State<DoctorConsultationQueueScreen> {
  // All accepted appointments from the server
  List<Map<String, dynamic>> consultations = [];

  // True while loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // false = Upcoming tab, true = Past tab
  bool showPast = false;

  // Runs once when the screen first opens
  // Asks the server again every minute, so a button that says
  // "Starts ..." turns into "Start Consultation" by itself
  Timer? refreshTimer;

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadConsultations(); // Start loading right away

    // Quiet refresh every minute (no spinner)
    refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) loadConsultations(quiet: true);
    });
  }

  // Runs when the screen closes: stop the timer
  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }


  // Cuts "17:30:00" down to "17:30"
  String shortTime(dynamic value) {
    final text = (value ?? '').toString();
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  // True if the appointment's end time has already gone by
  bool isPastItem(Map<String, dynamic> item) {
    final end = (item['end_time'] ?? item['start_time'] ?? '').toString();
    final endTime = DateTime.tryParse('${item['appointment_date']} $end');

    // If the time cannot be read, treat it as upcoming
    if (endTime == null) return false;

    return DateTime.now().isAfter(endTime);
  }

  // Loads the accepted appointments from the server
  // quiet = true means a background refresh: no spinner, and a failed
  // refresh keeps the list that is already on the screen
  Future<void> loadConsultations({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final result = await ApiService.getDoctorConsultationQueue(
        widget.doctorId,
      );

      // If the doctor left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        consultations = result.map((item) {
          return {
            'appointment_id': item['appointment_id'],
            'patientName': item['patient_name']?.toString() ?? 'Patient',
            'date': item['appointment_date']?.toString() ?? '',
            'time':
                '${shortTime(item['start_time'])} - ${shortTime(item['end_time'])}',
            'mode': item['consultation_mode']?.toString() ?? '',
            'reason': item['reason_for_visit']?.toString() ?? '',
            // True once the appointment time has arrived (Start is enabled)
            'canStart': item['can_start'] == true,
            // Shown on the button before the time arrives
            'startsAt':
                '${item['appointment_date'] ?? ''} at ${shortTime(item['start_time'])}',
            // True if the appointment time is over
            'isPast': isPastItem(item),
          };
        }).toList();
        isLoading = false;
      });
        } catch (e) {
      if (!mounted) return;

      // A failed background refresh is ignored
      if (quiet) return;

      setState(() {
        isLoading = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // Upcoming: soonest first
  List<Map<String, dynamic>> get upcomingList =>
      consultations.where((c) => c['isPast'] != true).toList();

  // Past: most recent first
  List<Map<String, dynamic>> get pastList =>
      consultations.where((c) => c['isPast'] == true).toList().reversed.toList();

  // Opens the video call, then reloads the list when the doctor returns
  Future<void> startConsultation(Map<String, dynamic> consultation) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoCallScreen(
          appointmentId: int.parse(consultation['appointment_id'].toString()),
          participantId: widget.doctorId,
          participantRole: 'doctor',
        ),
      ),
    );

    if (mounted) loadConsultations();
  }

  // Opens the notes form. Saving it completes the appointment, so the
  // card disappears from here and appears in Consultation History.
  Future<void> openNotes(Map<String, dynamic> consultation) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => widget.notesScreenBuilder(
          consultation,
          int.parse(consultation['appointment_id'].toString()),
        ),
      ),
    );

    if (mounted) loadConsultations();
  }

  // The doctor cancels an accepted appointment (asks first)
  Future<void> cancelAppointment(Map<String, dynamic> consultation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this appointment?'),
        content: Text(
          '${consultation['patientName']} will be told that you cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel appointment'),
          ),
        ],
      ),
    );

    // The doctor tapped "Keep it" (or closed the popup)
    if (confirmed != true) return;

    // Send the cancellation to the server
    final result = await ApiService.doctorCancelAppointment(
      doctorId: widget.doctorId,
      appointmentId: int.parse(consultation['appointment_id'].toString()),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'Appointment cancelled.'
              : (result['message'] ?? 'Failed to cancel the appointment.')
                  .toString(),
        ),
        backgroundColor: result['success'] == true ? Colors.green : Colors.red,
      ),
    );

    // Reload so the cancelled appointment leaves the list
    if (result['success'] == true) loadConsultations();
  }

  // One small line with an icon (date, time, reason)
  Widget infoRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: Color(0xFF26384A)),
          ),
        ),
      ],
    );
  }

  // The card of one appointment
  Widget consultationCard(Map<String, dynamic> consultation) {
    final isPast = consultation['isPast'] == true;
    final canStart = consultation['canStart'] == true;
    final reason = consultation['reason'].toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 25,
                  backgroundColor: Color(0xFFEAF2FA),
                  child: Icon(
                    Icons.person_outline,
                    color: Color(0xFF3F6FA8),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        consultation['patientName'].toString(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF26384A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        consultation['mode'].toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF3F6FA8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Orange label for past ones, green for upcoming ones
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isPast ? Colors.orange.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isPast ? 'Not completed' : 'Accepted',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isPast ? Colors.orange.shade800 : Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 12),
            infoRow(Icons.calendar_today_outlined, consultation['date'].toString()),
            const SizedBox(height: 10),
            infoRow(Icons.access_time_outlined, consultation['time'].toString()),
            const SizedBox(height: 10),
            infoRow(
              Icons.description_outlined,
              reason.isEmpty ? 'No reason given' : reason,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                // Disabled (null) until the appointment time arrives
                onPressed: canStart ? () => startConsultation(consultation) : null,
                icon: const Icon(Icons.video_call, size: 20),
                label: Text(
                  // Before the time arrives, say when it starts
                  canStart
                      ? 'Start Consultation'
                      : 'Starts ${consultation['startsAt']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F6FA8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                // Cancel the appointment
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => cancelAppointment(consultation),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Write the notes and complete (only once the time arrives)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canStart ? () => openNotes(consultation) : null,
                    icon: const Icon(Icons.edit_note, size: 20),
                    label: const Text('Notes & Complete'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // The two buttons at the top: Upcoming and Past
  Widget tabButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          ChoiceChip(
            label: Text('Upcoming (${upcomingList.length})'),
            selected: !showPast,
            onSelected: (_) => setState(() => showPast = false),
          ),
          const SizedBox(width: 10),
          ChoiceChip(
            label: Text('Past (${pastList.length})'),
            selected: showPast,
            onSelected: (_) => setState(() => showPast = true),
          ),
        ],
      ),
    );
  }

  // Decides what to show under the buttons
  Widget buildList() {
    // 1. Still loading
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. Loading failed: message and Retry button
    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: loadConsultations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final list = showPast ? pastList : upcomingList;

    // 3. Nothing in this tab
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_call_outlined, size: 60, color: Colors.grey),
            const SizedBox(height: 14),
            Text(
              showPast ? 'No past consultations' : 'No upcoming consultations',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    // 4. The list (pull down to refresh)
    return RefreshIndicator(
      onRefresh: loadConsultations,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: list.length,
        itemBuilder: (context, index) => consultationCard(list[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text('Consultations'),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          tabButtons(),
          Expanded(child: buildList()),
        ],
      ),
    );
  }
}