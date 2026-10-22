import 'package:flutter/material.dart';
import 'patient_prescriptions_screen.dart';
import 'patient_orders_screen.dart';

// ============================================================
// ORDER MEDICINE HOME SCREEN
// The page that opens from the "Order Medicine" card.
// It has three big options:
//   1. Order from a prescription
//   2. Your orders
//   3. Track your order
// ============================================================

class OrderMedicineHomeScreen extends StatelessWidget {
  const OrderMedicineHomeScreen({super.key});

  // Opens another screen (a small helper so the code is shorter)
  void openScreen(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  // One big tile. "index" is used to slide the tiles in one after another.
  Widget optionTile({
    required BuildContext context,
    required int index,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    // TweenAnimationBuilder fades the tile in and slides it up
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      // Each tile starts a little later than the one above it
      duration: Duration(milliseconds: 400 + index * 150),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 14),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        // InkWell gives the ripple effect when the tile is tapped
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Big round icon with a soft colour behind it
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 34, color: color),
                ),
                const SizedBox(width: 16),

                // Title and a short explanation
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF26384A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),

                Icon(Icons.arrow_forward_ios, size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: const Text('Order Medicine'),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----- Coloured banner at the top -----
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Medicines at your door',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Order the medicines your doctor prescribed.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Large icon on the right side of the banner
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_pharmacy,
                      size: 38,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // ----- Option 1: order from a prescription -----
            optionTile(
              context: context,
              index: 0,
              icon: Icons.medication,
              color: Colors.teal,
              title: 'Order from Prescription',
              subtitle: 'Choose a prescription and order its medicines',
              onTap: () => openScreen(
                context,
                const PatientPrescriptionsScreen(orderMode: true),
              ),
            ),

            // ----- Option 2: past orders -----
            optionTile(
              context: context,
              index: 1,
              icon: Icons.shopping_bag_outlined,
              color: const Color(0xFF3F6FA8),
              title: 'Your Orders',
              subtitle: 'See all the orders you have placed',
              onTap: () => openScreen(
                context,
                const PatientOrdersScreen(),
              ),
            ),

            // ----- Option 3: track an order -----
            optionTile(
              context: context,
              index: 2,
              icon: Icons.local_shipping_outlined,
              color: Colors.orange,
              title: 'Track Your Order',
              subtitle: 'See where your medicines are right now',
              onTap: () => openScreen(
                context,
                const PatientOrdersScreen(trackMode: true),
              ),
            ),

            const SizedBox(height: 6),

            // ----- Reminder about the 7-day rule -----
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'A prescription can be used to order medicines for 7 days. After that, please consult the doctor again for a new prescription.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}