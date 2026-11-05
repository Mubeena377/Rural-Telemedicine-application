# ============================================================
# NOTIFICATION TEXTS
# Every notification the server sends, written in the 8 app
# languages. {doctor_name} and similar blanks are filled in
# when the notification is sent.
# If a language or a kind is missing, English is used instead.
# ============================================================

# Each kind has: a title, the message saved in the app's list,
# and a shorter message for the push on the lock screen.
NOTIFICATION_TEXTS = {
    "ConsultationStarted": {
        "en_IN": {
            "title": "Your doctor is ready",
            "message": "{doctor_name} has started your consultation. Tap Join to start the video call.",
            "push": "{doctor_name} has started your consultation. Tap to join.",
        },
        "hi_IN": {
            "title": "आपके डॉक्टर तैयार हैं",
            "message": "{doctor_name} ने आपका परामर्श शुरू कर दिया है। वीडियो कॉल शुरू करने के लिए जॉइन पर टैप करें।",
            "push": "{doctor_name} ने आपका परामर्श शुरू कर दिया है। जॉइन करने के लिए टैप करें।",
        },
        "kn_IN": {
            "title": "ನಿಮ್ಮ ವೈದ್ಯರು ಸಿದ್ಧರಾಗಿದ್ದಾರೆ",
            "message": "{doctor_name} ಅವರು ನಿಮ್ಮ ಸಮಾಲೋಚನೆಯನ್ನು ಪ್ರಾರಂಭಿಸಿದ್ದಾರೆ. ವೀಡಿಯೊ ಕರೆ ಪ್ರಾರಂಭಿಸಲು ಜಾಯಿನ್ ಒತ್ತಿರಿ.",
            "push": "{doctor_name} ಅವರು ನಿಮ್ಮ ಸಮಾಲೋಚನೆಯನ್ನು ಪ್ರಾರಂಭಿಸಿದ್ದಾರೆ. ಸೇರಲು ಟ್ಯಾಪ್ ಮಾಡಿ.",
        },
        "ta_IN": {
            "title": "உங்கள் மருத்துவர் தயார்",
            "message": "{doctor_name} உங்கள் ஆலோசனையைத் தொடங்கிவிட்டார். வீடியோ அழைப்பைத் தொடங்க இணை என்பதைத் தட்டவும்.",
            "push": "{doctor_name} உங்கள் ஆலோசனையைத் தொடங்கிவிட்டார். சேர தட்டவும்.",
        },
        "te_IN": {
            "title": "మీ డాక్టర్ సిద్ధంగా ఉన్నారు",
            "message": "{doctor_name} మీ సంప్రదింపును ప్రారంభించారు. వీడియో కాల్ ప్రారంభించడానికి జాయిన్ నొక్కండి.",
            "push": "{doctor_name} మీ సంప్రదింపును ప్రారంభించారు. చేరడానికి నొక్కండి.",
        },
        "ml_IN": {
            "title": "നിങ്ങളുടെ ഡോക്ടർ തയ്യാറാണ്",
            "message": "{doctor_name} നിങ്ങളുടെ കൺസൾട്ടേഷൻ ആരംഭിച്ചു. വീഡിയോ കോൾ തുടങ്ങാൻ ജോയിൻ ടാപ്പ് ചെയ്യുക.",
            "push": "{doctor_name} നിങ്ങളുടെ കൺസൾട്ടേഷൻ ആരംഭിച്ചു. ചേരാൻ ടാപ്പ് ചെയ്യുക.",
        },
        "mr_IN": {
            "title": "तुमचे डॉक्टर तयार आहेत",
            "message": "{doctor_name} यांनी तुमचा सल्ला सुरू केला आहे. व्हिडिओ कॉल सुरू करण्यासाठी जॉइन वर टॅप करा.",
            "push": "{doctor_name} यांनी तुमचा सल्ला सुरू केला आहे. जॉइन करण्यासाठी टॅप करा.",
        },
        "bn_IN": {
            "title": "আপনার ডাক্তার প্রস্তুত",
            "message": "{doctor_name} আপনার পরামর্শ শুরু করেছেন। ভিডিও কল শুরু করতে জয়েন-এ ট্যাপ করুন।",
            "push": "{doctor_name} আপনার পরামর্শ শুরু করেছেন। যোগ দিতে ট্যাপ করুন।",
        },
    },
}


def notif_text(kind, language, **values):
    """Returns (title, message, push) for one notification kind.

    kind     - the notification type, for example "ConsultationStarted"
    language - the user's language code, for example "ta_IN"
    values   - the blanks to fill in, for example doctor_name="Dr. Rao"
    """
    # All the languages for this kind (empty if the kind is unknown)
    versions = NOTIFICATION_TEXTS.get(kind, {})

    # Use the user's language, or English if it is missing
    chosen = versions.get(language) or versions.get("en_IN")

    # An unknown kind: return empty texts instead of crashing
    if not chosen:
        return "", "", ""

    try:
        # Fill the blanks such as {doctor_name}
        return (
            chosen["title"].format(**values),
            chosen["message"].format(**values),
            chosen["push"].format(**values),
        )
    except (KeyError, IndexError):
        # A blank was not provided: return the text as it is
        return chosen["title"], chosen["message"], chosen["push"]