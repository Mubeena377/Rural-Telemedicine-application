# Rural Telemedicine Platform

> **Contributors:** [@Mubeena377](https://github.com/Mubeena377), [@TeammateGitHubHandle](https://github.com/)

---

## 1. Overview & Problem Statement

- **The Challenge:** Rural communities often face difficulties accessing timely healthcare because of long travel distances, limited medical facilities, and shortages of healthcare professionals. Patients may also struggle to access medical consultations, manage prescriptions, and obtain emergency assistance when needed.
- **Target Audience:** Rural patients, doctors, and communities with limited access to healthcare services. The platform is also intended to support patients in urban areas.
- **Impact Metric:** The project aims to reduce unnecessary travel and waiting time through remote consultations, digital prescriptions, and easier access to healthcare information. The actual improvement in time and accessibility will be measured during testing.

---

## 2. Architecture & Solution Logic

- **Concept:** The Rural Telemedicine Platform is a mobile healthcare application designed to connect patients and doctors through digital services. It provides patient and doctor interfaces, video consultation functionality, prescription management, and multilingual language selection. Planned extensions include AI-assisted triage, emergency SOS, medicine reminders, and additional healthcare services.

- **Tech / Framework Stack:**

  - **Frontend:** Flutter and Dart
  - **Backend:** Python and Flask
  - **Database:** PostgreSQL
  - **Video Consultations:** Agora
  - **Development Tools:** Visual Studio Code and Android Studio
  - **Version Control:** Git and GitHub

### System Flow

1. Patients and doctors interact with the Flutter mobile application.
2. The application sends supported requests to the Flask backend through APIs.
3. The backend processes requests and communicates with PostgreSQL.
4. The application provides interfaces for consultations, prescriptions, patient information, and other healthcare workflows.
5. Additional modules can be integrated as development progresses.

---

## 3. Project Structure

The application follows a modular Flutter project structure, with separate files for patient services, doctor workflows, consultations, prescriptions, language selection, and supporting functionality.

```text
flutter_application_1/
├── lib/
│   ├── main.dart
│   ├── api_service.dart
│   ├── choose_language.dart
│   ├── doctor_create_prescription_screen.dart
│   ├── doctor_patient_history_screen.dart
│   ├── doctor_patients_screen.dart
│   ├── doctor_session.dart
│   ├── emergency_screen.dart
│   ├── order_medicine_home_screen.dart
│   ├── order_medicine_screen.dart
│   ├── patient_details_screen.dart
│   ├── patient_health_record_screen.dart
│   ├── patient_orders_screen.dart
│   ├── patient_prescriptions_screen.dart
│   ├── prescription_pdf.dart
│   ├── push_service.dart
│   ├── report_file_picker.dart
│   ├── signature_pad_screen.dart
│   └── video_call_screen.dart
├── android/
├── ios/
├── linux/
├── test/
├── web/
├── windows/
├── pubspec.yaml
└── README.md
```

### Main Components

- **`main.dart`** — Application entry point, navigation, global language state, and translation functionality.
- **`api_service.dart`** — Provides the Flutter-side service for communicating with backend APIs.
- **`choose_language.dart`** — Language-selection interface supporting English, Hindi, Kannada, Tamil, Telugu, Malayalam, Marathi, and Bengali.
- **Doctor screens** — Support doctor-related workflows, patient history, consultation sessions, and prescription creation.
- **Patient screens** — Support patient details, health records, prescriptions, and medicine-order management.
- **`video_call_screen.dart`** — Video consultation interface using Agora.
- **`emergency_screen.dart`** — Emergency assistance interface.
- **`push_service.dart`** — Supports push-notification and navigation-related functionality.
- **`report_file_picker.dart`** — Supports selecting medical report files.
- **`prescription_pdf.dart`** — Handles prescription PDF functionality.
- **`signature_pad_screen.dart`** — Provides a signature-capture interface.
- **`pubspec.yaml`** — Defines Flutter dependencies and project configuration.

*The structure is based on the files visible in the current development environment. Update it as the project evolves.*

---

## 4. Key Features & Prototype

- [x] **Flutter Application Foundation:** Mobile application structure and core screens.
- [x] **Patient and Doctor Interfaces:** Patient details and doctor-related workflows.
- [x] **Video Consultation Interface:** Agora-based video consultation functionality.
- [x] **Prescription Module:** Doctor prescription creation and patient prescription interfaces.
- [x] **Multilingual Selection Interface:** Language selection for eight Indian languages.
- [ ] **Complete Backend Integration:** Connect and verify all required API workflows.
- [x] **AI Triage Assistant:** Preliminary assessment of symptoms and medical information.
- [ ] **Emergency SOS Integration:** Emergency requests and location-based assistance.
- [ ] **Medicine Reminders:** Medication schedules and notifications.
- [ ] **Electronic Health Records:** Integrated patient health-history management.
- [ ] **Ambulance Tracking:** Real-time ambulance location and status.
- [ ] **Online Medicine Ordering:** Complete ordering workflow and backend integration.
- [ ] **App-Wide Language Switching:** Immediate translation updates across all screens and persistence after restarting the application.

*Checkboxes should reflect features that have actually been implemented and tested. Some listed functionality remains under development.*

---

## 5. Scalability & Next Steps

- **Phase 1 — Core Application:** Develop the Flutter application structure, patient and doctor interfaces, prescription workflows, video consultation interface, and language-selection screen.

- **Phase 2 — Integration & Testing:** Complete Flask API integration, connect database-backed workflows, improve multilingual support, and implement automated tests.

- **Phase 3 — Advanced Healthcare Features:** Develop AI-assisted triage, strengthen emergency SOS workflows, add medicine reminders and ambulance tracking, and integrate additional healthcare services.

- **Scalability:** The modular Flutter frontend, Flask backend, and PostgreSQL database provide a foundation for expanding the platform. Production deployment will require security reviews, privacy safeguards, performance testing, and reliable healthcare-service integrations.

---

*Created as a final-year Bachelor of Computer Applications (BCA) academic project.*
