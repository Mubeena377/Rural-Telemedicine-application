import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import 'app_text.dart';
import 'first_aid_texts.dart';

// ============================================================
// FIRST AID GUIDE
// Two screens in this file:
//  - FirstAidScreen: search, big tiles for the important topics,
//    and buttons to call the emergency numbers
//  - FirstAidDetailScreen: the full text of one topic
// The buttons, headings and notes follow the chosen language. The
// medical steps come from the server and stay as they are stored.
// ============================================================

// Finds a text in the chosen language (English if it is missing)
String t(String text) => tt(firstAidTexts, text);

// Opens the phone's dialer with the number already typed.
// The person only has to press the green call button.
Future<void> dialNumber(BuildContext context, String number) async {
  try {
    final opened = await launchUrl(Uri(scheme: 'tel', path: number));

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t('Could not open the dialer. Please dial')} $number'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t('Could not open the dialer. Please dial')} $number'),
        ),
      );
    }
  }
}

// A picture for each topic, chosen from words in its name
IconData firstAidIcon(String name) {
  final n = name.toLowerCase();

  if (n.contains('bleeding')) return Icons.bloodtype;
  if (n.contains('burn')) return Icons.local_fire_department;
  if (n.contains('snake')) return Icons.pest_control;
  if (n.contains('choking')) return Icons.air;
  if (n.contains('cpr')) return Icons.favorite;
  if (n.contains('chest')) return Icons.monitor_heart;
  if (n.contains('faint')) return Icons.accessibility_new;
  if (n.contains('fit')) return Icons.flash_on;
  if (n.contains('poison')) return Icons.warning_amber_rounded;
  if (n.contains('electric')) return Icons.bolt;
  if (n.contains('heat')) return Icons.wb_sunny;
  if (n.contains('drown')) return Icons.pool;
  if (n.contains('bone')) return Icons.personal_injury;
  if (n.contains('animal')) return Icons.pets;
  if (n.contains('scorpion') || n.contains('sting')) return Icons.bug_report;
  if (n.contains('nose')) return Icons.water_drop;
  if (n.contains('dehydration')) return Icons.local_drink;

  return Icons.medical_services;
}

// A colour for each group of topics
Color firstAidColor(String category) {
  switch (category) {
    case 'Wounds':
      return Colors.red;
    case 'Burns & heat':
      return Colors.deepOrange;
    case 'Bites & stings':
      return Colors.green;
    case 'Heart & breathing':
      return Colors.pink;
    case 'Fainting & fits':
      return Colors.indigo;
    case 'Poison & shock':
      return Colors.purple;
    case 'Bones & injuries':
      return Colors.brown;
    case 'Stomach & fluids':
      return Colors.teal;
    default:
      return Colors.blueGrey;
  }
}

// The two big red call buttons (used on both screens)
Widget emergencyCallRow(BuildContext context) {
  return Row(
    children: [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: () => dialNumber(context, '112'),
          icon: const Icon(Icons.call),
          label: Text(t('Call 112')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 54),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: ElevatedButton.icon(
          onPressed: () => dialNumber(context, '108'),
          icon: const Icon(Icons.local_hospital),
          label: Text(t('Call 108')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 54),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    ],
  );
}

// ============================================================
// SCREEN 1: THE LIST OF TOPICS
// ============================================================

class FirstAidScreen extends StatefulWidget {
  const FirstAidScreen({super.key});

  @override
  State<FirstAidScreen> createState() => _FirstAidScreenState();
}

class _FirstAidScreenState extends State<FirstAidScreen> {
  // All the topics from the server
  List<Map<String, dynamic>> topics = [];

  // True while loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // What the person typed in the search box
  String searchText = '';

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    loadTopics(); // Start loading right away
  }

  // Loads the topics from the server
  Future<void> loadTopics() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Ask the server (function we added in api_service.dart)
      final list = await ApiService.getFirstAidTopics();

      // If the person left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        topics = list;
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

  // Opens the full page of one topic
  void openTopic(Map<String, dynamic> topic) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FirstAidDetailScreen(
          firstAidId: topic['first_aid_id'] as int,
          name: (topic['name'] ?? '').toString(),
        ),
      ),
    );
  }

  // The red "call" box at the top of the screen
  Widget emergencyBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emergency, color: Colors.red, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('In an emergency, call for help first'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          emergencyCallRow(context),
        ],
      ),
    );
  }

  // The grey note under the search box
  Widget guidanceNote() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        t('This is general guidance only. It does not replace a doctor. Topics marked "Draft" have not been checked by a doctor yet.'),
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
    );
  }

  // A big picture tile for one important topic
  Widget topicTile(Map<String, dynamic> topic) {
    final color = firstAidColor((topic['category'] ?? '').toString());
    final name = (topic['name'] ?? '').toString();
    final reviewed = topic['reviewed'] == true;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => openTopic(topic),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The icon is chosen from the English name, so it still works
            // when the shown name is translated
            Icon(
              firstAidIcon((topic['english_name'] ?? name).toString()),
              size: 40,
              color: color,
            ),
            const SizedBox(height: 6),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            if (!reviewed)
              Text(
                t('Draft'),
                style: const TextStyle(fontSize: 10, color: Colors.orange),
              ),
          ],
        ),
      ),
    );
  }

  // One row in the list of other topics
  Widget topicRow(Map<String, dynamic> topic) {
    final color = firstAidColor((topic['category'] ?? '').toString());
    final name = (topic['name'] ?? '').toString();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        // Same here: pick the icon from the English name
        child: Icon(
          firstAidIcon((topic['english_name'] ?? name).toString()),
          color: color,
        ),
      ),
      title: Text(name),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      onTap: () => openTopic(topic),
    );
  }

  // Everything below the emergency box
  List<Widget> topicSection() {
    // 1. Still loading
    if (isLoading) {
      return const [
        Padding(
          padding: EdgeInsets.all(30),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    // 2. Loading failed: message and Retry button
    if (errorMessage != null) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: loadTopics,
                icon: const Icon(Icons.refresh),
                label: Text(t('Retry')),
              ),
            ],
          ),
        ),
      ];
    }

    final search = searchText.trim().toLowerCase();

    // 3. Searching: one list of every topic that matches
    if (search.isNotEmpty) {
      final matches = topics
          .where((t) => (t['name'] ?? '').toString().toLowerCase().contains(search))
          .toList();

      if (matches.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t('No topic found. Try another word, or call 112 if it is an emergency.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ];
      }

      return matches.map(topicRow).toList();
    }

    // 4. Not searching: big tiles for the important topics,
    //    then the other topics in a folding list
    final important = topics.where((topic) => topic['is_priority'] == true).toList();
    final others = topics.where((topic) => topic['is_priority'] != true).toList();

    return [
      if (important.isNotEmpty) ...[
        Text(
          t('Important topics'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.9,
          children: important.map(topicTile).toList(),
        ),
      ],
      if (others.isNotEmpty) ...[
        const SizedBox(height: 16),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          // ExpansionTile folds the long list until the person taps it
          child: ExpansionTile(
            leading: const Icon(Icons.list),
            title: Text('${t('More topics')} (${others.length})'),
            children: others.map(topicRow).toList(),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(t('First Aid Guide')),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: loadTopics, // Pull down to refresh
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            emergencyBox(),
            const SizedBox(height: 16),

            // The search box
            TextField(
              onChanged: (value) => setState(() => searchText = value),
              decoration: InputDecoration(
                hintText: t('Search (for example: burn, snake)'),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            guidanceNote(),
            const SizedBox(height: 16),

            ...topicSection(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SCREEN 2: ONE TOPIC
// ============================================================

class FirstAidDetailScreen extends StatefulWidget {
  final int firstAidId;
  final String name; // Shown in the top bar while loading

  const FirstAidDetailScreen({
    super.key,
    required this.firstAidId,
    required this.name,
  });

  @override
  State<FirstAidDetailScreen> createState() => _FirstAidDetailScreenState();
}

class _FirstAidDetailScreenState extends State<FirstAidDetailScreen> {
  // The full topic from the server
  Map<String, dynamic>? topic;

  // True while loading (shows a spinner)
  bool isLoading = true;

  // Holds an error message if loading fails
  String? errorMessage;

  // Runs once when the screen first opens
  @override
  void initState() {
    super.initState();
    load(); // Start loading right away
  }

  // Loads the topic from the server
  Future<void> load() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Ask the server (function we added in api_service.dart)
      final data = await ApiService.getFirstAidTopic(widget.firstAidId);

      // If the person left this screen while waiting, stop here
      if (!mounted) return;

      setState(() {
        topic = data;
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

  // Cuts a text into lines and removes empty ones
  List<String> linesOf(dynamic text) {
    return (text ?? '')
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  // One coloured box with a title and a list of lines
  Widget section(String title, IconData icon, Color color, List<String> lines) {
    // Hide the box if there is nothing to show
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(line, style: const TextStyle(fontSize: 16, height: 1.35)),
            ),
          ),
        ],
      ),
    );
  }

  // The whole topic
  Widget content() {
    final data = topic!;
    final category = (data['category'] ?? '').toString();
    final color = firstAidColor(category);
    final name = (data['name'] ?? widget.name).toString();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // The title with a big picture
        Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: color.withOpacity(0.12),
              // Same here: pick the icon from the English name
              child: Icon(
                firstAidIcon((data['english_name'] ?? name).toString()),
                size: 36,
                color: color,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // The warning that this topic is a draft
        if (data['reviewed'] != true)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              t('Draft: this advice has not been checked by a doctor yet.'),
              style: const TextStyle(fontSize: 12),
            ),
          ),

        // The most urgent box first: when to call for emergency help
        section(
          t('Call for emergency help'),
          Icons.emergency,
          Colors.red,
          linesOf(data['emergency_warning']),
        ),
        emergencyCallRow(context),
        const SizedBox(height: 16),

        section(t('What you may see'), Icons.visibility, Colors.blueGrey,
            linesOf(data['symptoms'])),
        section(t('What to do'), Icons.checklist, Colors.green.shade700,
            linesOf(data['steps'])),
        section(t('Do NOT'), Icons.block, Colors.red, linesOf(data['do_not_do'])),
        section(t('When to see a doctor'), Icons.local_hospital,
            Colors.orange.shade800, linesOf(data['when_to_seek_help'])),

        const SizedBox(height: 8),
        Text(
          t('This is general guidance only. It does not replace a doctor.'),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // Decides what to show: spinner, error, or the topic
  Widget buildBody() {
    // 1. Still loading
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 2. Loading failed: message, Retry button, and the call buttons
    if (errorMessage != null || topic == null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            errorMessage ?? t('Could not load this topic.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: Text(t('Retry')),
          ),
          const SizedBox(height: 20),
          emergencyCallRow(context),
        ],
      );
    }

    // 3. Loaded
    return content();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: const Color(0xFF3F6FA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: buildBody(),
    );
  }
}