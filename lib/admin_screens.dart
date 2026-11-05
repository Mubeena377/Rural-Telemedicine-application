import 'package:flutter/material.dart';
import 'package:flutter_application_1/api_service.dart';
 
// ======================================================
// ADMIN PORTAL
// Talks to the Flask /api/admin/... routes.
// The login token is kept in memory in ApiService.adminToken.
// ======================================================
 
const Color _adminPrimary = Color(0xFF10192F);
const Color _adminBg = Color(0xFFF7FAFC);
 
const List<String> _sosStatuses = [
  'Requested',
  'Assigned',
  'Enroute',
  'Arrived',
  'Closed',
];
 
Color _statusColor(String status) {
  switch (status) {
    case 'Requested':
      return Colors.red;
    case 'Assigned':
      return Colors.orange;
    case 'Enroute':
      return Colors.blue;
    case 'Arrived':
      return Colors.purple;
    case 'Closed':
      return Colors.green;
    default:
      return Colors.grey;
  }
}
 
AppBar _adminAppBar(
  String title, {
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black87,
    elevation: 0,
    centerTitle: true,
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
    ),
    actions: actions,
    bottom: bottom,
  );
}
 
void _toast(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: error ? Colors.red : null,
      content: Text(message),
    ),
  );
}
 
// If the login token has expired, go back to the start and say so.
// Returns true when that happened, so the caller can stop.
bool _sessionExpired(BuildContext context, Map<String, dynamic> result) {
  if (result['expired'] != true) return false;
  if (context.mounted) {
    _toast(context, 'Session expired. Please login again.', error: true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
  return true;
}
 
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            action,
            style: TextStyle(color: danger ? Colors.red : null),
          ),
        ),
      ],
    ),
  );
  return result == true;
}
 
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
 
  const _ErrorView({required this.message, required this.onRetry});
 
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('TRY AGAIN'),
              style: ElevatedButton.styleFrom(backgroundColor: _adminPrimary, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
 
class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
 
  const _EmptyView({required this.icon, required this.text});
 
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
 
// ======================================================
// LOGIN
// ======================================================
 
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});
 
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}
 
class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool hidePassword = true;
  bool loggingIn = false;
 
  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }
 
  Future<void> login() async {
    if (loggingIn) return;
 
    final username = usernameController.text.trim();
    final password = passwordController.text;
 
    if (username.isEmpty || password.isEmpty) {
      _toast(context, 'Please enter your username and password.', error: true);
      return;
    }
 
    setState(() => loggingIn = true);
 
    final result = await ApiService.adminLogin(
      username: username,
      password: password,
    );
 
    if (!mounted) return;
    setState(() => loggingIn = false);
 
    if (result['success'] == true) {
      passwordController.clear();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
      );
    } else {
      _toast(context, result['message'] ?? 'Login failed', error: true);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    debugPrint('ADMIN: login screen building');
    return Scaffold(
      backgroundColor: _adminBg,
      appBar: _adminAppBar('Admin Login'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const CircleAvatar(
              radius: 42,
              backgroundColor: Color(0xFFE3E8F2),
              child: Icon(Icons.admin_panel_settings, size: 46, color: _adminPrimary),
            ),
            const SizedBox(height: 20),
            const Text(
              'Administrator',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _adminPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to manage the platform',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: usernameController,
              enabled: !loggingIn,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              enabled: !loggingIn,
              obscureText: hidePassword,
              onSubmitted: (_) => login(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(hidePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => hidePassword = !hidePassword),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: loggingIn ? null : login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _adminPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: loggingIn
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('LOGIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 
// ======================================================
// DASHBOARD
// ======================================================
 
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
 
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}
 
class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? stats;
  bool loading = true;
  String? error;
 
  @override
  void initState() {
    super.initState();
    loadStats();
  }
 
  @override
  void dispose() {
    // Leaving the admin area forgets the login
    ApiService.adminToken = null;
    super.dispose();
  }
 
  Future<void> loadStats() async {
    setState(() {
      loading = true;
      error = null;
    });
 
    final result = await ApiService.adminRequest('GET', '/stats');
 
    if (!mounted) return;
    if (_sessionExpired(context, result)) return;
 
    setState(() {
      loading = false;
      if (result['success'] == true) {
        stats = Map<String, dynamic>.from(result['stats']);
      } else {
        error = result['message'] ?? 'Could not load the numbers';
      }
    });
  }
 
  Future<void> open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
    if (mounted) loadStats();
  }
 
  Future<void> logout() async {
    final ok = await _confirm(
      context,
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      action: 'LOGOUT',
    );
    if (ok && mounted) {
      ApiService.adminToken = null;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
 
  Widget statCard(IconData icon, Color color, int? value, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 6),
          Text(
            value == null ? '-' : '$value',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
 
  Widget menuCard(IconData icon, Color color, String title, String subtitle, VoidCallback onTap, {int badge = 0}) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(subtitle),
        trailing: badge > 0
            ? CircleAvatar(
                radius: 13,
                backgroundColor: Colors.red,
                child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              )
            : const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final pending = (stats?['pending_doctors'] ?? 0) as int;
    final activeSos = (stats?['active_sos'] ?? 0) as int;
 
    return Scaffold(
      backgroundColor: _adminBg,
      appBar: _adminAppBar(
        'Admin Portal',
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: Colors.red), tooltip: 'Logout', onPressed: logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (loading && stats == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (error != null && stats == null)
                SizedBox(height: 220, child: _ErrorView(message: error!, onRetry: loadStats))
              else
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.5,
                  children: [
                    statCard(Icons.people, Colors.teal, stats?['patients'], 'Patients'),
                    statCard(Icons.medical_services, Colors.indigo, stats?['doctors'], 'Doctors'),
                    statCard(Icons.pending_actions, Colors.orange, stats?['pending_doctors'], 'Pending approvals'),
                    statCard(Icons.sos, Colors.red, stats?['active_sos'], 'Active SOS'),
                  ],
                ),
              const SizedBox(height: 24),
              const Text('Manage', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              menuCard(Icons.how_to_reg, Colors.orange, 'Doctor Approvals', 'Review new doctor registrations',
                  () => open(const AdminApprovalsScreen()), badge: pending),
              menuCard(Icons.sos, Colors.red, 'SOS Monitor', 'Track and update emergencies',
                  () => open(const AdminSosMonitorScreen()), badge: activeSos),
              menuCard(Icons.manage_accounts, Colors.teal, 'Users', 'Patients and doctors',
                  () => open(const AdminUsersScreen())),
            ],
          ),
        ),
      ),
    );
  }
}
 
// ======================================================
// DOCTOR APPROVALS
// ======================================================
 
class AdminApprovalsScreen extends StatefulWidget {
  const AdminApprovalsScreen({super.key});
 
  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}
 
class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> {
  List<Map<String, dynamic>> doctors = [];
  bool loading = true;
  String? error;
  final Set<int> busy = {};
 
  @override
  void initState() {
    super.initState();
    load();
  }
 
  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
 
    final result = await ApiService.adminRequest('GET', '/doctors/pending');
 
    if (!mounted) return;
    if (_sessionExpired(context, result)) return;
 
    setState(() {
      loading = false;
      if (result['success'] == true) {
        doctors = List<Map<String, dynamic>>.from(result['doctors']);
      } else {
        error = result['message'] ?? 'Could not load the requests';
      }
    });
  }
 
  Future<void> decide(Map<String, dynamic> doctor, bool approve) async {
    final id = doctor['doctor_id'] as int;
    final name = doctor['full_name'];
 
    if (!approve) {
      final ok = await _confirm(
        context,
        title: 'Reject registration?',
        message: '$name will not be able to log in.',
        action: 'REJECT',
        danger: true,
      );
      if (!ok) return;
    }
 
    setState(() => busy.add(id));
 
    final result = await ApiService.adminRequest(
      'PUT',
      '/doctors/$id/decision',
      body: {'decision': approve ? 'approve' : 'reject'},
    );
 
    if (!mounted) return;
    if (_sessionExpired(context, result)) return;
 
    setState(() => busy.remove(id));
 
    if (result['success'] == true) {
      setState(() => doctors.removeWhere((d) => d['doctor_id'] == id));
      _toast(context, '$name ${approve ? 'approved' : 'rejected'}.');
    } else {
      _toast(context, result['message'] ?? 'Could not save the decision', error: true);
      load(); // It may already have been decided; show the latest list
    }
  }
 
  @override
  Widget build(BuildContext context) {
    Widget body;
 
    if (loading && doctors.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null && doctors.isEmpty) {
      body = _ErrorView(message: error!, onRetry: load);
    } else if (doctors.isEmpty) {
      body = const _EmptyView(icon: Icons.check_circle_outline, text: 'No pending doctor requests');
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: doctors.length,
        itemBuilder: (context, index) {
          final d = doctors[index];
          final id = d['doctor_id'] as int;
          final isBusy = busy.contains(id);
 
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange.withOpacity(0.12),
                        child: const Icon(Icons.medical_services, color: Colors.orange),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${d['full_name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('${d['specialization']} · ${d['experience_years']} yrs',
                                style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Qualification: ${d['qualification']}', style: const TextStyle(fontSize: 13)),
                  Text('Registration no: ${d['license_number']}', style: const TextStyle(fontSize: 13)),
                  Text('Phone: ${d['phone']}', style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 14),
                  if (isBusy)
                    const Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => decide(d, false),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                            child: const Text('REJECT'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => decide(d, true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            child: const Text('APPROVE'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      );
    }
 
    return Scaffold(
      backgroundColor: _adminBg,
      appBar: _adminAppBar('Doctor Approvals'),
      body: RefreshIndicator(onRefresh: load, child: body),
    );
  }
}
 
// ======================================================
// SOS MONITOR
// ======================================================
 
class AdminSosMonitorScreen extends StatefulWidget {
  const AdminSosMonitorScreen({super.key});
 
  @override
  State<AdminSosMonitorScreen> createState() => _AdminSosMonitorScreenState();
}
 
class _AdminSosMonitorScreenState extends State<AdminSosMonitorScreen> {
  static const filters = {'all': 'All', 'active': 'Active', 'closed': 'Closed'};
 
  String filter = 'active';
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? error;
 
  @override
  void initState() {
    super.initState();
    load();
  }
 
  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
 
    final result = await ApiService.adminRequest('GET', '/sos?filter=$filter');
 
    if (!mounted) return;
    if (_sessionExpired(context, result)) return;
 
    setState(() {
      loading = false;
      if (result['success'] == true) {
        items = List<Map<String, dynamic>>.from(result['sos']);
      } else {
        error = result['message'] ?? 'Could not load the SOS requests';
      }
    });
  }
 
  Future<void> changeStatus(Map<String, dynamic> sos, String status) async {
    if (status == 'Closed') {
      final ok = await _confirm(
        context,
        title: 'Close this SOS?',
        message: 'SOS #${sos['sos_id']} will be marked as closed.',
        action: 'CLOSE',
      );
      if (!ok) return;
    }
 
    final result = await ApiService.adminRequest(
      'PUT',
      '/sos/${sos['sos_id']}/status',
      body: {'status': status},
    );
 
    if (!mounted) return;
    if (_sessionExpired(context, result)) return;
 
    if (result['success'] == true) {
      _toast(context, 'SOS #${sos['sos_id']} is now $status.');
      load();
    } else {
      _toast(context, result['message'] ?? 'Could not update the status', error: true);
    }
  }
 
  Widget detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(
            child: Text(
              (value == null || value.isEmpty) ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
 
  void showDetails(Map<String, dynamic> s) {
    final status = '${s['status']}';
    final lat = s['latitude'];
    final lng = s['longitude'];
    final location = (lat != null && lng != null)
        ? '${(lat as num).toStringAsFixed(5)}, ${(lng as num).toStringAsFixed(5)}'
        : null;
 
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('SOS #${s['sos_id']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  Chip(
                    label: Text(status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    backgroundColor: _statusColor(status),
                  ),
                ],
              ),
              const Divider(),
              detailRow('Patient', s['patient_name']),
              detailRow('Phone', s['patient_phone']),
              detailRow('Contact', s['contact_name']),
              detailRow('Contact phone', s['contact_phone']),
              detailRow('Type', s['emergency_type']),
              detailRow('Requested', s['request_time']),
              detailRow('Last update', s['updated_at']),
              detailRow('Location', location),
              const SizedBox(height: 14),
              const Text('Change status', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sosStatuses
                    .where((st) => st != status)
                    .map((st) => OutlinedButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            changeStatus(s, st);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _statusColor(st),
                            side: BorderSide(color: _statusColor(st)),
                          ),
                          child: Text(st),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    Widget body;
 
    if (loading && items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null && items.isEmpty) {
      body = _ErrorView(message: error!, onRetry: load);
    } else if (items.isEmpty) {
      body = const _EmptyView(icon: Icons.sos, text: 'No SOS requests');
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final s = items[index];
          final status = '${s['status']}';
          final color = _statusColor(status);
 
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(0.12),
                child: Icon(Icons.sos, color: color),
              ),
              title: Text('#${s['sos_id']} · ${s['patient_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${s['patient_phone']}\n${s['request_time']}'),
              isThreeLine: true,
              trailing: Chip(
                label: Text(status, style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: color,
                visualDensity: VisualDensity.compact,
              ),
              onTap: () => showDetails(s),
            ),
          );
        },
      );
    }
 
    return Scaffold(
      backgroundColor: _adminBg,
      appBar: _adminAppBar('SOS Monitor'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: filters.entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: filter == e.key,
                          selectedColor: _adminPrimary,
                          labelStyle: TextStyle(color: filter == e.key ? Colors.white : Colors.black87),
                          onSelected: (_) {
                            if (filter == e.key) return;
                            setState(() {
                              filter = e.key;
                              items = [];
                            });
                            load();
                          },
                        ),
                      ))
                  .toList(),
            ),
          ),
          Expanded(child: RefreshIndicator(onRefresh: load, child: body)),
        ],
      ),
    );
  }
}
 
// ======================================================
// USERS
// ======================================================
 
class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});
 
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _adminBg,
        appBar: _adminAppBar(
          'Users',
          bottom: const TabBar(
            labelColor: _adminPrimary,
            indicatorColor: _adminPrimary,
            tabs: [Tab(text: 'Patients'), Tab(text: 'Doctors')],
          ),
        ),
        body: const TabBarView(
          children: [
            _UserList(group: 'patients'),
            _UserList(group: 'doctors'),
          ],
        ),
      ),
    );
  }
}
 
class _UserList extends StatefulWidget {
  final String group; // patients or doctors
 
  const _UserList({required this.group});
 
  @override
  State<_UserList> createState() => _UserListState();
}
 
class _UserListState extends State<_UserList> {
  List<Map<String, dynamic>> users = [];
  bool loading = true;
  String? error;
  String search = '';
  final Set<int> busy = {};
 
  @override
  void initState() {
    super.initState();
    load();
  }
 
  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
 
    final result = await ApiService.adminRequest('GET', '/users/${widget.group}');
 
    if (!mounted) return;
    if (_sessionExpired(context, result)) return;
 
    setState(() {
      loading = false;
      if (result['success'] == true) {
        users = List<Map<String, dynamic>>.from(result['users']);
      } else {
        error = result['message'] ?? 'Could not load the users';
      }
    });
  }
 
  Future<void> setActive(Map<String, dynamic> user, bool value) async {
    final id = user['id'] as int;
 
    if (!value) {
      final ok = await _confirm(
        context,
        title: 'Deactivate user?',
        message: '${user['full_name']} will no longer be able to use the app.',
        action: 'DEACTIVATE',
        danger: true,
      );
      if (!ok) return;
    }
 
    setState(() => busy.add(id));
 
    final result = await ApiService.adminRequest(
      'PUT',
      '/users/${widget.group}/$id/active',
      body: {'active': value},
    );
 
    if (!mounted) return;
    if (_sessionExpired(context, result)) return;
 
    setState(() => busy.remove(id));
 
    if (result['success'] == true) {
      setState(() => user['active'] = value);
      _toast(context, '${user['full_name']} ${value ? 'activated' : 'deactivated'}.');
    } else {
      _toast(context, result['message'] ?? 'Could not update the user', error: true);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final query = search.trim().toLowerCase();
    final shown = users.where((u) {
      if (query.isEmpty) return true;
      return '${u['full_name']}'.toLowerCase().contains(query) ||
          '${u['phone']}'.contains(query);
    }).toList();
 
    Widget body;
 
    if (loading && users.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null && users.isEmpty) {
      body = _ErrorView(message: error!, onRetry: load);
    } else if (shown.isEmpty) {
      body = const _EmptyView(icon: Icons.person_off_outlined, text: 'No users found');
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: shown.length,
        itemBuilder: (context, index) {
          final u = shown[index];
          final id = u['id'] as int;
          final active = u['active'] == true;
          final approval = u['approval_status'];
 
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: (active ? Colors.teal : Colors.grey).withOpacity(0.12),
                child: Icon(Icons.person, color: active ? Colors.teal : Colors.grey),
              ),
              title: Text('${u['full_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${u['phone']}'
                '${approval != null ? '\nApproval: $approval' : ''}'
                '\n${active ? 'Active' : 'Deactivated'}',
              ),
              isThreeLine: true,
              trailing: busy.contains(id)
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Switch(
                      value: active,
                      activeColor: Colors.teal,
                      onChanged: (value) => setActive(u, value),
                    ),
            ),
          );
        },
      );
    }
 
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: (value) => setState(() => search = value),
            decoration: InputDecoration(
              hintText: 'Search by name or phone',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(child: RefreshIndicator(onRefresh: load, child: body)),
      ],
    );
  }
}
 

