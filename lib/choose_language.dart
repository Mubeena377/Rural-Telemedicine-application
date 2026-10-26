
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

class ChooseLanguage extends StatefulWidget {
  const ChooseLanguage({super.key});

  @override
  State<ChooseLanguage> createState() => _ChooseLanguageState();
}

class _ChooseLanguageState extends State<ChooseLanguage> {
  String selectedLanguage = 'en_IN';

  final List<Map<String, String>> languages = [
    {
      'code': 'en_IN',
      'name': 'English',
      'native': 'English',
      'subtitle': 'Continue in English',
    },
    {
      'code': 'hi_IN',
      'name': 'Hindi',
      'native': 'हिन्दी',
      'subtitle': 'हिन्दी में जारी रखें',
    },
    {
      'code': 'kn_IN',
      'name': 'Kannada',
      'native': 'ಕನ್ನಡ',
      'subtitle': 'ಕನ್ನಡದಲ್ಲಿ ಮುಂದುವರಿಯಿರಿ',
    },
    {
      'code': 'ta_IN',
      'name': 'Tamil',
      'native': 'தமிழ்',
      'subtitle': 'தமிழில் தொடரவும்',
    },
    {
      'code': 'te_IN',
      'name': 'Telugu',
      'native': 'తెలుగు',
      'subtitle': 'తెలుగులో కొనసాగించండి',
    },
    {
      'code': 'ml_IN',
      'name': 'Malayalam',
      'native': 'മലയാളം',
      'subtitle': 'മലയാളത്തിൽ തുടരുക',
    },
    {
      'code': 'mr_IN',
      'name': 'Marathi',
      'native': 'मराठी',
      'subtitle': 'मराठीत पुढे जा',
    },
    {
      'code': 'bn_IN',
      'name': 'Bengali',
      'native': 'বাংলা',
      'subtitle': 'বাংলায় চালিয়ে যান',
    },
  ];

  @override
  void initState() {
    super.initState();
    selectedLanguage = appLanguage.value;
  }

  Future<void> continueWithLanguage() async {
    final chosenLanguage = selectedLanguage;

    appLanguage.value = chosenLanguage;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedLanguage', chosenLanguage);

    if (!mounted) return;

    Navigator.pop(context, chosenLanguage);
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF167D68);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F7),
      appBar: AppBar(
        title: const Text(
          'Choose Language',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFF5F8F7),
        foregroundColor: const Color(0xFF173D35),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.translate_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Your language, your comfort',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Choose a language to use the telemedicine app comfortably.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Select your language',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF173D35),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'You can change this later in your profile.',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: languages.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.12,
                      ),
                      itemBuilder: (context, index) {
                        final language = languages[index];
                        final isSelected =
                            selectedLanguage == language['code'];

                        return InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            final newLanguage = language['code']!;

                            setState(() {
                              selectedLanguage = newLanguage;
                            });

                            // Update the language across the app immediately.
                            appLanguage.value = newLanguage;

                            // Save the selection for the next app launch.
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString(
                              'selectedLanguage',
                              newLanguage,
                            );
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFE4F4EF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected
                                    ? primaryColor
                                    : const Color(0xFFE0E8E5),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        language['native']!,
                                        style: const TextStyle(
                                          fontSize: 21,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF173D35),
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: primaryColor,
                                        size: 22,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  language['name']!,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  language['subtitle']!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE6ECE9)),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: continueWithLanguage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
