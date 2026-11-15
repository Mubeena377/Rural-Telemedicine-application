import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'order_medicine_text.dart'; // tx() shows text in the chosen language

// ============================================================
// ORDER MEDICINE SCREEN
// Lets the patient order the medicines of one prescription.
// Every fixed sentence goes through tx(), so it follows the language the
// patient chose. The medicine names, doses and the address the patient
// typed are shown as written.
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

  // The payment choices: the first value goes to the server (it stays
  // as it is), the second is the English text, translated when shown
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
      showMessage(tx('Please enter your delivery address.'));
      return;
    }

    // The patient ID was saved on the phone when the patient logged in
    final prefs = await SharedPreferences.getInstance();
    final patientId = prefs.getInt('patientId');

    if (patientId == null) {
      if (!mounted) return;
      showMessage(tx('Patient information not found. Please log in again.'));
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
      showMessage(
        (result['message'] ?? tx('Failed to place the order.')).toString(),
      );
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
          title: Text(tx('Order Placed')),
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
                // {id} is replaced with the real order number
                tx('Your order number is {id}.')
                    .replaceAll('{id}', '${result['order_id']}'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                // A total of 0 means the catalog has no price yet
                total > 0
                    ? tx('Total: ₹{amount}')
                        .replaceAll('{amount}', total.toStringAsFixed(2))
                    : tx('The pharmacy will confirm the price.'),
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
              child: Text(tx('Done')),
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
  // (the dose and the frequency are what the doctor wrote)
  String medicineSummary(Map<String, dynamic> medicine) {
    final parts = <String>[];

    if (medicine['dosage'] != null) {
      parts.add(medicine['dosage'].toString());
    }
    if (medicine['frequency'] != null) {
      parts.add(medicine['frequency'].toString());
    }
    if (medicine['duration_days'] != null) {
      // The number first, then the word for "days" in the chosen language
      parts.add('${medicine['duration_days']} ${tx('days')}');
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
        title: Text(tx('Order Medicines')),
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
            Text(
              tx('Medicines in this prescription'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF26384A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tx('1 pack of each medicine will be ordered.'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
            Text(
              tx('Delivery address'),
              style: const TextStyle(
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
                hintText: tx('House, village, landmark, PIN code'),
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
            Text(
              tx('Payment method'),
              style: const TextStyle(
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
                  // Shown in the chosen language; option[0] goes to the server
                  label: Text(tx(option[1])),
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
            Text(
              tx('No payment is taken in the app. It is collected on delivery or confirmed by the pharmacy.'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
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
                  placing ? tx('Placing order...') : tx('Place Order'),
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