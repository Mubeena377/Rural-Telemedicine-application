import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'app_text.dart'; // gives us the tt() translation helper
import 'patient_orders_texts.dart'; // the 8-language texts for this screen

// Short helper: translates one English text for this screen
String _t(String text) => tt(patientOrdersTexts, text);

// ============================================================
// PATIENT ORDERS SCREEN
// One screen with two uses:
//  - "Your Orders"       (trackMode = false): every order
//  - "Track Your Order"  (trackMode = true):  only orders that
//                        are still on their way
// ============================================================

class PatientOrdersScreen extends StatefulWidget {
  // True when opened from "Track Your Order"
  final bool trackMode;

  const PatientOrdersScreen({
    super.key,
    this.trackMode = false,
  });

  @override
  State<PatientOrdersScreen> createState() => _PatientOrdersScreenState();
}

class _PatientOrdersScreenState extends State<PatientOrdersScreen> {
  // The orders loaded from the server
  List<Map<String, dynamic>> orders = [];

  // True while loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // The four steps of a delivery, in order.
  // These stay in English because they are compared with the status
  // sent by the server. They are translated only when shown on screen.
  final List<String> stepNames = const [
    'Placed',
    'Confirmed',
    'Dispatched',
    'Delivered',
  ];

  final List<IconData> stepIcons = const [
    Icons.receipt_long,
    Icons.thumb_up_alt_outlined,
    Icons.local_shipping_outlined,
    Icons.home_outlined,
  ];

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadOrders(); // Start loading right away
  }

  // Loads this patient's orders from the server
  Future<void> loadOrders() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // The patient ID was saved on the phone when the patient logged in
      final prefs = await SharedPreferences.getInstance();
      final patientId = prefs.getInt('patientId');

      if (patientId == null) {
        if (!mounted) return;
        setState(() {
          isLoading = false;
          // Translated message (made on the phone, not by the server)
          errorMessage =
              _t('Patient information not found. Please log in again.');
        });
        return;
      }

      // Ask the server (function we added in api_service.dart)
      final data = await ApiService.getPatientMedicineOrders(patientId);

      if (!mounted) return;

      setState(() {
        orders = data;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        // Server messages stay in English
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // A colour for each order status (uses the English status from the server)
  Color statusColor(String status) {
    switch (status) {
      case 'Confirmed':
        return Colors.indigo;
      case 'Dispatched':
        return Colors.orange;
      case 'Delivered':
        return Colors.green;
      case 'Cancelled':
        return Colors.red;
      default:
        return const Color(0xFF3F6FA8); // Placed
    }
  }

  // Friendly text for the payment method codes
  String paymentLabel(String code) {
    if (code == 'COD') return _t('Cash on delivery');
    return code;
  }

  // "2026-10-22 07:00:29.27" -> "2026-10-22"
  String dateOnly(String value) {
    return value.length >= 10 ? value.substring(0, 10) : value;
  }

  // The progress bar and four icons that show where the order is
  Widget tracker(String status) {
    // A cancelled order has no progress, so show a red message
    if (status == 'Cancelled') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        // (no "const" here because the text is translated)
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _t('This order was cancelled.'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    // Which step the order is on (0 = Placed ... 3 = Delivered)
    var current = stepNames.indexOf(status);
    if (current < 0) current = 0;

    final color = statusColor(status);

    return Column(
      children: [
        // The progress bar fills up as the order moves forward
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (current + 1) / stepNames.length,
            minHeight: 8,
            backgroundColor: Colors.grey.shade300,
            color: color,
          ),
        ),

        const SizedBox(height: 12),

        // The four steps with their icons
        Row(
          children: List.generate(stepNames.length, (i) {
            // A step is "done" if the order has reached it
            final done = i <= current;

            return Expanded(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: done ? color : Colors.grey.shade300,
                    child: Icon(stepIcons[i], color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(stepNames[i]), // translated step name
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          i == current ? FontWeight.bold : FontWeight.normal,
                      color: done ? Colors.black87 : Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  // The card for one order
  Widget orderCard(Map<String, dynamic> order) {
    final status = (order['status'] ?? 'Placed').toString();
    final total = ((order['total_amount'] ?? 0) as num).toDouble();

    final items = List<Map<String, dynamic>>.from(order['items'] ?? []);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      // Remove the default lines inside the expandable tile
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // In "Track" mode the order opens by itself
          initiallyExpanded: widget.trackMode,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: CircleAvatar(
            backgroundColor: statusColor(status).withOpacity(0.12),
            child: Icon(Icons.local_pharmacy, color: statusColor(status)),
          ),
          title: Text(
            // "Order #5" in the chosen language
            _t('Order #{number}')
                .replaceAll('{number}', order['order_id'].toString()),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                // The coloured status label
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _t(status), // translated status name
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor(status),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dateOnly((order['order_date'] ?? '').toString()),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          children: [
            // Progress of the delivery
            tracker(status),

            const SizedBox(height: 16),
            const Divider(),

            // The medicines in this order
            // (medicine names come from the server, so they stay as they are)
            ...items.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.medication_outlined,
                      size: 20,
                      color: Color(0xFF3F6FA8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item['medicine']} × ${item['quantity']}',
                      ),
                    ),
                  ],
                ),
              );
            }),

            const Divider(),

            // Total price (0 means the pharmacy still has to set it)
            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    total > 0
                        ? _t('Total: ₹{amount}')
                            .replaceAll('{amount}', total.toStringAsFixed(2))
                        : _t('Price will be confirmed by the pharmacy'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Payment method
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  paymentLabel((order['payment_method'] ?? '').toString()),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Delivery address (typed by the patient, so it stays as it is)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (order['delivery_address'] ?? '').toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // A friendly message with a big icon (used for empty states)
  Widget messageView(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 70, color: Colors.grey),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Decides what to show in the middle of the screen
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
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: loadOrders,
                icon: const Icon(Icons.refresh),
                label: Text(_t('Retry')),
              ),
            ],
          ),
        ),
      );
    }

    // In "Track" mode we only keep orders that are still on their way
    final shown = widget.trackMode
        ? orders.where((order) {
            final status = (order['status'] ?? '').toString();
            return status != 'Delivered' && status != 'Cancelled';
          }).toList()
        : orders;

    // 3. Nothing to show
    if (shown.isEmpty) {
      return messageView(
        widget.trackMode
            ? Icons.local_shipping_outlined
            : Icons.shopping_bag_outlined,
        widget.trackMode
            ? _t('No orders on their way right now.')
            : _t('You have not placed any orders yet.'),
      );
    }

    // 4. The list (pull down to refresh)
    return RefreshIndicator(
      onRefresh: loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: shown.length,
        itemBuilder: (context, index) {
          return orderCard(shown[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(
          widget.trackMode ? _t('Track Your Order') : _t('Your Orders'),
        ),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: buildBody(),
    );
  }
}