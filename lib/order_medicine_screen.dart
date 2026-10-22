import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

// ============================================================
// ORDER MEDICINE SCREEN
// Lets the patient order the medicines of one prescription.
// ============================================================

class OrderMedicineScreen extends StatefulWidget {
  // The prescription being ordered (the same map the server sends)
  final Map<String, dynamic> prescription;

  const OrderMedicineScreen({
    super.key,
    required this.prescription,
  });

  @override
  State<OrderMedicineScreen> createState() => _OrderMedicineScreenState();
}

class _OrderMedicineScreenState extends State<OrderMedicineScreen> {
  // The delivery address typed by the patient
  final TextEditingController addressController = TextEditingController();

  // The chosen payment method (COD = cash on delivery)
  String paymentMethod = 'COD';

  // True while the order is being sent (stops double taps)
  bool placing = false;

  // The payment choices: the first value goes to the server,
  // the second is the text shown on the screen
  final List<List<String>> paymentOptions = const [
    ['COD', 'Cash on delivery'],
    ['UPI', 'UPI'],
    ['Card', 'Card'],
    ['Wallet', 'Wallet'],
  ];

  // Frees the text box memory when the screen closes
  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  // Shows a short message at the bottom of the screen
  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Sends the order to the server
  Future<void> placeOrder() async {
    // Ignore extra taps while an order is already being sent
    if (placing) return;

    // The address is required
    final address = addressController.text.trim();
    if (address.isEmpty) {
      showMessage('Please enter your delivery address.');
      return;
    }

    // The patient ID was saved on the phone when the patient logged in
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getInt('patientId');

    if (patientId == null) {
      if (!mounted) return;
      showMessage('Patient information not found. Please log in again.');
      return;
    }

    setState(() {
      placing = true;
    });

    // Ask the server (function we added in api_service.dart)
    final result = await ApiService.placeMedicineOrder(
      patientId: patientId,
      prescriptionId: widget.prescription['prescription_id'] as int,
      deliveryAddress: address,
      paymentMethod: paymentMethod,
    );

    // If the patient left this screen while waiting, stop here
    if (!mounted) return;

    setState(() {
      placing = false;
    });

    // If the server refused, show its message and stay on this screen
    if (result['success'] != true) {
      showMessage(result['message'] ?? 'Failed to place the order.');
      return;
    }

    // The total price worked out by the server
    final total = ((result['total_amount'] ?? 0) as num).toDouble();

    // Show a confirmation popup
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Order Placed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 60,
                color: Colors.green,
              ),
              const SizedBox(height: 15),
              Text(
                'Your order number is ${result['order_id']}.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                // A total of 0 means the catalog has no price yet
                total > 0
                    ? 'Total: ₹${total.toStringAsFixed(2)}'
                    : 'The pharmacy will confirm the price.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close the popup
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );

    // Go back to the prescriptions list
    if (!mounted) return;
    Navigator.pop(context);
  }

  // Builds the short text line for one medicine, e.g.
  // "200mg • twice daily • 3 days"
  String medicineSummary(Map<String, dynamic> medicine) {
    final parts = <String>[];

    if (medicine['dosage'] != null) {
      parts.add(medicine['dosage'].toString());
    }
    if (medicine['frequency'] != null) {
      parts.add(medicine['frequency'].toString());
    }
    if (medicine['duration_days'] != null) {
      parts.add('${medicine['duration_days']} days');
    }

    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    // The medicines inside this prescription
    final medicines = List<Map<String, dynamic>>.from(
      widget.prescription['medicines'] ?? [],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text('Order Medicines'),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- Medicines on this prescription -----
            const Text(
              'Medicines in this prescription',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '1 pack of each medicine will be ordered.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),

            // One card per medicine
            ...medicines.map((medicine) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(
                    Icons.medication_outlined,
                    color: Color(0xFF3F6FA8),
                  ),
                  title: Text(medicine['medicine']?.toString() ?? ''),
                  subtitle: Text(medicineSummary(medicine)),
                ),
              );
            }),

            const SizedBox(height: 20),

            // ----- Delivery address -----
            const Text(
              'Delivery address',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: addressController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'House, village, landmark, PIN code',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ----- Payment method -----
            const Text(
              'Payment method',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),
            const SizedBox(height: 10),

            // One tappable chip per payment option
            Wrap(
              spacing: 8,
              children: paymentOptions.map((option) {
                return ChoiceChip(
                  label: Text(option[1]),
                  selected: paymentMethod == option[0],
                  onSelected: (_) {
                    setState(() {
                      paymentMethod = option[0];
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 6),
            const Text(
              'No payment is taken in the app. It is collected on delivery or confirmed by the pharmacy.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),

            const SizedBox(height: 28),

            // ----- Place order button -----
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: placing ? null : placeOrder,
                icon: placing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.local_pharmacy),
                label: Text(
                  placing ? 'Placing order...' : 'Place Order',
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

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}