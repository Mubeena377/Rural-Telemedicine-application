import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';

// ============================================================
// OPEN SOS REQUESTS (for ambulances and hospitals)
// Shows every SOS request that is not closed yet: who needs help,
// the phone numbers, and the location. The list refreshes itself
// every 10 seconds, and you can also pull down to refresh.
// ============================================================

class ResponderSosListScreen extends StatefulWidget {
  // The title in the top bar
  final String title;

  const ResponderSosListScreen({
    super.key,
    this.title = 'Emergency Requests',
  });

  @override
  State<ResponderSosListScreen> createState() => _ResponderSosListScreenState();
}

class _ResponderSosListScreenState extends State<ResponderSosListScreen> {
  // The open SOS requests from the server
  List<Map<String, dynamic>> requests = [];

  // True while loading for the first time (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // Asks the server again every 10 seconds
  Timer? refreshTimer;

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadRequests(); // Start loading right away

    // Quiet refresh every 10 seconds (no spinner)
    refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) loadRequests(quiet: true);
    });
  }

  // Runs when the screen closes: stop the timer
  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  // quiet = true means a background refresh: no spinner, and a failed
  // refresh keeps the list that is already on the screen
  Future<void> loadRequests({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      // Which ambulance or hospital is logged in on this phone?
      final prefs = await SharedPreferences.getInstance();
      final responderId = prefs.getInt('responderId');

      if (responderId == null) {
        throw Exception('Please login again.');
      }

      final list = await ApiService.getResponderOpenSos(responderId);

      // If the person left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        requests = list;
        isLoading = false;
        errorMessage = null;
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

  // A colour for each SOS status
  Color statusColor(String status) {
    switch (status) {
      case 'Requested':
        return Colors.red;
      case 'Assigned':
        return Colors.orange;
      case 'Enroute':
        return Colors.blue;
      case 'Arrived':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // Opens the phone's dialer with the number already typed
  Future<void> dial(String number) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the dialer. Please dial $number')),
      );
    }
  }

  // Opens the patient's location in the maps app or the browser
  Future<void> openMap(double latitude, double longitude) async {
    try {
      await launchUrl(
        Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
        ),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the map.')),
      );
    }
  }

  // One line with a small icon (time, phone, contact)
  Widget infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: Color(0xFF26384A)),
            ),
          ),
        ],
      ),
    );
  }

  // The card of one SOS request
  Widget requestCard(Map<String, dynamic> sos) {
    final status = (sos['status'] ?? '').toString();
    final color = statusColor(status);
    final patientPhone = (sos['patient_phone'] ?? '').toString();
    final contactName = (sos['contact_name'] ?? '').toString();
    final contactPhone = (sos['contact_phone'] ?? '').toString();
    final latitude = sos['latitude'];
    final longitude = sos['longitude'];

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
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(Icons.sos, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (sos['patient_name'] ?? 'Patient').toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF26384A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            infoRow(Icons.access_time, 'SOS #${sos['sos_id']}  |  ${sos['request_time']}'),
            infoRow(Icons.phone_outlined, 'Patient: $patientPhone'),
            if (contactName.isNotEmpty || contactPhone.isNotEmpty)
              infoRow(
                Icons.contact_phone_outlined,
                'Emergency contact: $contactName $contactPhone',
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: patientPhone.isEmpty ? null : () => dial(patientPhone),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('Call'),
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
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (latitude == null || longitude == null)
                        ? null
                        : () => openMap(
                              (latitude as num).toDouble(),
                              (longitude as num).toDouble(),
                            ),
                    icon: const Icon(Icons.location_on, size: 18),
                    label: const Text('Location'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F6FA8),
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

  // Decides what to show: spinner, error, empty message, or the list
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
              Text(errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: loadRequests,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Nothing to show
    if (requests.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
          SizedBox(height: 14),
          Center(
            child: Text(
              'No open SOS requests',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      );
    }

    // 4. The list
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: requests.length,
      itemBuilder: (context, index) => requestCard(requests[index]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      // Pull down to refresh
      body: RefreshIndicator(
        onRefresh: loadRequests,
        child: buildBody(),
      ),
    );
  }
}