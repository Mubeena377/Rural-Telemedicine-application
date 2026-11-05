import os
from dotenv import load_dotenv
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import psycopg2
from werkzeug.utils import secure_filename
from functools import wraps
from itsdangerous import URLSafeTimedSerializer, BadSignature, SignatureExpired
from werkzeug.security import generate_password_hash, check_password_hash
import joblib
import time
import re
import uuid
import threading
import datetime as dt
import firebase_admin
from firebase_admin import credentials, messaging
from agora_token_builder import RtcTokenBuilder



load_dotenv()
print("AGORA_APP_ID exists:", "AGORA_APP_ID" in os.environ)
print("AGORA_APP_CERTIFICATE exists:", "AGORA_APP_CERTIFICATE" in os.environ)
AGORA_APP_ID = os.getenv("AGORA_APP_ID")
AGORA_APP_CERTIFICATE = os.getenv("AGORA_APP_CERTIFICATE")
print("Agora App ID loaded:", bool(os.getenv("AGORA_APP_ID")))
print("Agora Certificate loaded:", bool(os.getenv("AGORA_APP_CERTIFICATE")))
print("Agora configuration variables set:",
      bool(AGORA_APP_ID),
      bool(AGORA_APP_CERTIFICATE))

app = Flask(__name__)
CORS(app)

# ============================================================
# FIREBASE (sends push notifications to phones)
# The key file location comes from the .env file.
# If anything is wrong, the server still starts, it just cannot
# send push notifications.
# ============================================================
firebase_ready = False

try:
    key_path = os.getenv("FIREBASE_KEY_PATH")

    if key_path:
        # Look for the key file in the same folder as app.py
        key_full_path = os.path.join(os.path.dirname(__file__), key_path)

        firebase_admin.initialize_app(
            credentials.Certificate(key_full_path)
        )
        firebase_ready = True

except Exception as firebase_error:
    print("Firebase setup failed:", firebase_error)

print("Firebase ready:", firebase_ready)
model = joblib.load(os.path.join(os.path.dirname(__file__), "triage_model.pkl"))
DATABASE_URL = (
    f"dbname={os.getenv('DB_NAME')} "
    f"user={os.getenv('DB_USER')} "
    f"password={os.getenv('DB_PASSWORD')} "
    f"host={os.getenv('DB_HOST')} "
    f"port={os.getenv('DB_PORT')}"
)
UPLOAD_FOLDER="uploads"
os.makedirs(UPLOAD_FOLDER,exist_ok=True)

def get_db_connection():
    return psycopg2.connect(DATABASE_URL)

@app.route("/api/health", methods=["GET"])
def health():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("SELECT 1;")
        result = cursor.fetchone()

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "message": "Flask and PostgreSQL are connected",
            "database_test": result[0]
        })

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route("/api/patients", methods=["POST"])
def register_patient():

    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    # Registration data from Flutter
    full_name = data.get("full_name")
    date_of_birth = data.get("date_of_birth")
    gender = data.get("gender")
    address = data.get("address")
    phone = data.get("phone")
    emergency_name = data.get("emergency_contact_name")
    emergency_phone = data.get("emergency_contact_phone")

    # Basic validation
    if not full_name:
        return jsonify({
            "status": "error",
            "message": "Full name is required"
        }), 400

    if not phone:
        return jsonify({
            "status": "error",
            "message": "Phone number is required"
        }), 400

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # -------------------------------------------------
        # STEP 1: Create the user account
        # Patient role_id = 2
        # -------------------------------------------------

        # Generate an internal password hash because
        # the current registration uses OTP instead of
        # a password.
        internal_password = os.urandom(32).hex()
        password_hash = generate_password_hash(internal_password)

        cursor.execute("""
            INSERT INTO users
            (
                full_name,
                phone,
                password_hash,
                role_id
            )
            VALUES (%s, %s, %s, %s)
            RETURNING user_id
        """, (
            full_name,
            phone,
            password_hash,
            2
        ))

        user_id = cursor.fetchone()[0]

        # -------------------------------------------------
        # STEP 2: Create the patient profile
        # -------------------------------------------------

        cursor.execute("""
            INSERT INTO patients
            (
                user_id,
                date_of_birth,
                gender,
                address,
                emergency_contact_name,
                emergency_contact_phone
            )
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING patient_id
        """, (
            user_id,
            date_of_birth if date_of_birth else None,
            gender if gender else None,
            address if address else None,
            emergency_name if emergency_name else None,
            emergency_phone if emergency_phone else None
        ))

        patient_id = cursor.fetchone()[0]

        # Save both records
        conn.commit()

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "message": "Patient registered successfully",
            "user_id": user_id,
            "patient_id": patient_id
        }), 201

    except Exception as e:

        # Undo the transaction if anything goes wrong
        if 'conn' in locals():
            conn.rollback()
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

@app.route("/api/patients/check-phone", methods=["GET"])
def check_patient_phone():
    phone = request.args.get("phone", "").strip()

    if len(phone) != 10 or not phone.isdigit():
        return jsonify({
            "status": "error",
            "message": "Please enter a valid 10-digit phone number."
        }), 400

    conn = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                u.user_id,
                u.full_name,
                p.patient_id
            FROM users u
            JOIN patients p ON p.user_id = u.user_id
            WHERE u.phone = %s
              AND u.role_id = 2
              AND u.status = 'Active'
            LIMIT 1
        """, (phone,))

        patient = cursor.fetchone()

        cursor.close()
        conn.close()
        conn = None

        if patient is None:
            return jsonify({
                "status": "error",
                "message": "No patient account found with this phone number. Please register first."
            }), 404

        return jsonify({
            "status": "success",
            "message": "Patient account found",
            "patient": {
                "user_id": patient[0],
                "full_name": patient[1],
                "patient_id": patient[2]
            }
        }), 200

    except Exception as e:
        if conn is not None:
            conn.close()

        print("Patient phone check error:", e)

        return jsonify({
            "status": "error",
            "message": "Unable to check patient account."
        }), 500  


# ============================================================
# GET PATIENT DETAILS
# Retrieves a patient's complete profile from the database
# using the patient_id saved during registration.
# ============================================================

@app.route("/api/patients/<int:patient_id>", methods=["GET"])
def get_patient_details(patient_id):
    conn = None

    try:
        # Connect to the database
        conn = get_db_connection()
        cursor = conn.cursor()

        # Combine the users and patients tables because
        # personal information is stored in both tables.
        cursor.execute("""
            SELECT
                p.patient_id,
                u.user_id,
                u.full_name,
                u.phone,
                p.date_of_birth,
                p.gender,
                p.address,
                p.emergency_contact_name,
                p.emergency_contact_phone
            FROM patients p
            JOIN users u ON u.user_id = p.user_id
            WHERE p.patient_id = %s
              AND u.role_id = 2
            LIMIT 1
        """, (patient_id,))

        # Fetch the matching patient's record
        patient = cursor.fetchone()

        cursor.close()
        conn.close()
        conn = None

        # Return 404 if the patient ID does not exist
        if patient is None:
            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        # Return the database values as JSON for Flutter
        return jsonify({
            "status": "success",
            "patient": {
                "patient_id": patient[0],
                "user_id": patient[1],
                "full_name": patient[2],
                "phone": patient[3],
                "date_of_birth": (
                    patient[4].isoformat()
                    if patient[4] is not None
                    and hasattr(patient[4], "isoformat")
                    else patient[4]
                ),
                "gender": patient[5],
                "address": patient[6],
                "emergency_contact_name": patient[7],
                "emergency_contact_phone": patient[8]
            }
        }), 200

    except Exception as e:
        # Close the connection if an error occurs
        if conn is not None:
            conn.close()

        print("Get patient details error:", e)

        return jsonify({
            "status": "error",
            "message": "Unable to retrieve patient details"
        }), 500

  
# ============================================================
# UPDATE PATIENT EMERGENCY CONTACT
# Saves emergency contact changes to the database.
# ============================================================
@app.route("/api/patients/<int:patient_id>/emergency-contact", methods=["PUT"])
def update_emergency_contact(patient_id):
    conn = None

    try:
        data = request.get_json()

        if not data:
            return jsonify({
                "status": "error",
                "message": "Request data is required"
            }), 400

        contact_name = (data.get("emergency_contact_name") or "").strip()
        contact_phone = (data.get("emergency_contact_phone") or "").strip()

        if not contact_name or not contact_phone:
            return jsonify({
                "status": "error",
                "message": "Emergency contact name and phone are required"
            }), 400

        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            UPDATE patients
            SET emergency_contact_name = %s,
                emergency_contact_phone = %s
            WHERE patient_id = %s
            RETURNING patient_id
        """, (contact_name, contact_phone, patient_id))

        updated_patient = cursor.fetchone()

        if updated_patient is None:
            conn.rollback()
            cursor.close()
            conn.close()
            conn = None

            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        conn.commit()
        cursor.close()
        conn.close()
        conn = None

        return jsonify({
            "status": "success",
            "message": "Emergency contact updated successfully",
            "patient_id": patient_id,
            "emergency_contact_name": contact_name,
            "emergency_contact_phone": contact_phone
        }), 200

    except Exception as e:
        if conn is not None:
            conn.rollback()
            conn.close()

        print("Update emergency contact error:", e)

        return jsonify({
            "status": "error",
            "message": "Unable to update emergency contact"
        }), 500
      

 # ============================================================
# TRIAGE CLASSIFICATION
# ============================================================

def classify_triage(symptoms):
    symptoms = (symptoms or "").strip()
    text = symptoms.lower()

    # --------------------------------------------------------
    # Emergency phrases that should always be treated as
    # emergency symptoms
    # --------------------------------------------------------

    emergency_phrases = [
        "chest pain",
        "severe chest pain",
        "difficulty breathing",
        "severe breathing",
        "cannot breathe",
        "unable to breathe",
        "unconscious",
        "fainted",
        "severe bleeding",
        "heavy bleeding",
        "seizure",
        "stroke",
        "face drooping",
        "slurred speech",
        "cannot speak",
        "can't speak",
        "difficulty speaking",
        "trouble speaking",
        "speech suddenly",
        "speech became unclear"
    ]

    if any(phrase in text for phrase in emergency_phrases):
        predicted_category = "EMERGENCY"

    elif not symptoms:
        predicted_category = "CONSULTATION"

    else:
        predicted_category = model.predict([symptoms])[0]

    # --------------------------------------------------------
    # Convert ML result into our application result
    # --------------------------------------------------------

    if predicted_category == "EMERGENCY":
        return {
            "risk_code": "Emergency",
            "risk_name": "Emergency SOS",
            "recommendation":
                "Possible emergency. Seek immediate professional medical help or contact local emergency services."
        }

    elif predicted_category == "FIRST AID":
        return {
            "risk_code": "Basic Care",
            "risk_name": "Basic First Aid",
            "recommendation":
                "Basic first-aid information may be appropriate. Consult a healthcare professional if symptoms continue or worsen."
        }

    else:
        return {
            "risk_code": "Consultation",
            "risk_name": "Medical Consultation",
            "recommendation":
                "Consult a qualified healthcare professional for further evaluation."
        }

# ------------------------------------------------------------
# FIND THE FIRST AID TOPIC THAT FITS THE SYMPTOMS
# The words of the symptoms are compared with the words in each
# topic's name. The topic with the most shared words wins.
# ------------------------------------------------------------

# Words that say nothing about the problem (ignored when matching)
FIRST_AID_STOP_WORDS = {
    "the", "and", "with", "for", "have", "has", "had", "was", "are",
    "very", "from", "that", "this", "but", "not", "feel", "feeling",
    "since", "after", "about", "just", "some", "much", "little",
    "when", "then", "also", "been", "getting", "got"
}

# Everyday words that point to the word used in the topic names
FIRST_AID_SYNONYMS = {
    "cut": "wound", "scratch": "wound", "scrape": "wound",
    "graze": "wound", "bleed": "bleeding", "blood": "bleeding",
    "scald": "burn", "burnt": "burn", "burned": "burn",
    "bitten": "bite", "stung": "sting", "twisted": "sprain",
    "broken": "fracture"
}


# Turns a text into a set of simple lowercase words
def first_aid_words(text):
    words = set()

    for word in re.findall(r"[a-z]+", (text or "").lower()):
        # Skip very short words and the ignored words
        if len(word) < 3 or word in FIRST_AID_STOP_WORDS:
            continue

        # "burns" and "burn" should count as the same word
        if len(word) > 3 and word.endswith("s"):
            word = word[:-1]

        words.add(word)

        # Also add the word used in the topic names, if we know it
        if word in FIRST_AID_SYNONYMS:
            words.add(FIRST_AID_SYNONYMS[word])

    return words


# Picks the best topic from a list of (id, name, is_priority) rows.
# Returns None if no topic shares a word with the symptoms.
def pick_first_aid_topic(symptoms, topics):
    words = first_aid_words(symptoms)

    if not words:
        return None

    best = None
    best_rank = None

    for topic_id, name, is_priority in topics:
        score = len(words & first_aid_words(name))

        if score == 0:
            continue

        # More shared words wins, then important topics, then the oldest
        rank = (score, 1 if is_priority == "Y" else 0, -topic_id)

        if best_rank is None or rank > best_rank:
            best_rank = rank
            best = {"id": topic_id, "name": name}

    return best


# Loads the topics and picks one. It uses its own database connection
# and never raises an error, so triage keeps working even if this fails.
def find_first_aid_topic(symptoms):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT first_aid_id, condition_name, is_priority
            FROM first_aid_guidance
        """)

        return pick_first_aid_topic(symptoms, cursor.fetchall())

    except Exception as e:
        print("Find First Aid Topic Error:", e)
        return None

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# TRIAGE API
# ============================================================

@app.route("/api/triage", methods=["POST"])
def triage():

    # --------------------------------------------------------
    # Receive data from Flutter
    # --------------------------------------------------------

    patient_id = request.form.get("patient_id", type=int)
    symptoms = request.form.get("symptoms", "").strip()

    # --------------------------------------------------------
    # Validate patient
    # --------------------------------------------------------

    if not patient_id:
        return jsonify({
            "status": "error",
            "message": "patient_id is required"
        }), 400

    # --------------------------------------------------------
    # Validate that the patient exists
    # --------------------------------------------------------

    try:

        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT patient_id
            FROM patients
            WHERE patient_id = %s
        """, (patient_id,))

        patient = cursor.fetchone()

        if not patient:

            cursor.close()
            conn.close()

            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        # ----------------------------------------------------
        # Run ML triage classification
        # ----------------------------------------------------

        result = classify_triage(symptoms)
        # If the result is "Basic Care", look for the first aid topic that fits
        first_aid = None

        if result["risk_code"] == "Basic Care":
            first_aid = find_first_aid_topic(symptoms)
        # ----------------------------------------------------
        # Save triage session
        # ----------------------------------------------------

        cursor.execute("""
            INSERT INTO triage_sessions
            (
                patient_id,
                chief_complaint,
                symptoms_summary,
                triage_result,
                recommended_action,
                session_end
            )
            VALUES
            (
                %s,
                %s,
                %s,
                %s,
                %s,
                CURRENT_TIMESTAMP
            )
            RETURNING triage_id
        """, (
            patient_id,
            symptoms[:500] if symptoms else None,
            symptoms if symptoms else None,
            result["risk_code"],
            result["recommendation"]
        ))

        triage_id = cursor.fetchone()[0]

        # ----------------------------------------------------
        # Save changes
        # ----------------------------------------------------

        conn.commit()

        cursor.close()
        conn.close()

        # ----------------------------------------------------
        # Send result back to Flutter
        # ----------------------------------------------------

        return jsonify({
            "status": "success",
            "triage_id": triage_id,
            "first_aid_id": first_aid["id"] if first_aid else None,
            "first_aid_name": first_aid["name"] if first_aid else None,            
            "risk_code": result["risk_code"],
            "risk_name": result["risk_name"],
            "recommendation": result["recommendation"]
        }), 201

    except Exception as e:

        if 'conn' in locals():
            conn.rollback()
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route("/api/sos", methods=["POST"])
def active_sos():
    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    patient_id = data.get("patient_id")
    latitude = data.get("latitude")
    longitude = data.get("longitude")

    if patient_id is None:
        return jsonify({
            "status": "error",
            "message": "patient_id is required"
        }), 400

    if latitude is None or longitude is None:
        return jsonify({
            "status": "error",
            "message": "GPS location is required"
        }), 400

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Check that patient exists
        cursor.execute("""
            SELECT patient_id
            FROM patients
            WHERE patient_id = %s
        """, (patient_id,))

        patient = cursor.fetchone()

        if not patient:
            cursor.close()
            conn.close()

            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        # Save SOS request
        cursor.execute("""
            INSERT INTO sos_requests
            (
                patient_id,
                location_lat,
                location_lng,
                emergency_type,
                status
            )
            VALUES (%s, %s, %s, %s, 'Requested')
            RETURNING sos_id
        """, (
            patient_id,
            latitude,
            longitude,
            "Medical Emergency"
        ))

        sos_id = cursor.fetchone()[0]

        conn.commit()

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "sos_id": sos_id,
            "message": "SOS request created successfully"
        }), 201

    except Exception as e:

        if 'conn' in locals():
            conn.rollback()
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
@app.route("/api/sos/<int:sos_id>/cancel", methods=["PATCH"])
def cancel_sos(sos_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Check whether the SOS exists
        cursor.execute("""
            SELECT sos_id, status
            FROM sos_requests
            WHERE sos_id = %s
        """, (sos_id,))

        sos = cursor.fetchone()

        if not sos:
            cursor.close()
            conn.close()

            return jsonify({
                "status": "error",
                "message": "SOS request not found"
            }), 404

        # Update SOS status
        cursor.execute("""
            UPDATE sos_requests
            SET status = 'Closed',
                updated_at = CURRENT_TIMESTAMP
            WHERE sos_id = %s
            RETURNING sos_id, status
        """, (sos_id,))

        updated_sos = cursor.fetchone()

        conn.commit()

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "sos_id": updated_sos[0],
            "new_status": updated_sos[1],
            "message": "SOS request cancelled successfully"
        }), 200

    except Exception as e:
        if 'conn' in locals():
            conn.rollback()
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500    
# ============================================================
# CREATE APPOINTMENT
# ============================================================
@app.route("/api/appointments", methods=["POST"])
def create_appointment():
    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    patient_id = data.get("patient_id")
    doctor_id = data.get("doctor_id")
    appointment_date = data.get("appointment_date")
    start_time = data.get("start_time")
    end_time = data.get("end_time")
    consultation_mode = data.get("consultation_mode")
    reason_for_visit = data.get("reason_for_visit")

    # Check required fields
    if not patient_id:
        return jsonify({
            "status": "error",
            "message": "Patient ID is required"
        }), 400

    if not doctor_id:
        return jsonify({
            "status": "error",
            "message": "Doctor ID is required"
        }), 400

    if not appointment_date:
        return jsonify({
            "status": "error",
            "message": "Appointment date is required"
        }), 400

    if not start_time:
        return jsonify({
            "status": "error",
            "message": "Start time is required"
        }), 400

    if not end_time:
        return jsonify({
            "status": "error",
            "message": "End time is required"
        }), 400

    if not consultation_mode:
        return jsonify({
            "status": "error",
            "message": "Consultation mode is required"
        }), 400

    # Validate consultation mode
    valid_modes = [
        "Online",
        "Offline",
        "Voice",
        "Chat"
    ]

    if consultation_mode not in valid_modes:
        return jsonify({
            "status": "error",
            "message": "Invalid consultation mode"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # -----------------------------------
        # Check patient
        # -----------------------------------
        cursor.execute(
            "SELECT patient_id FROM patients WHERE patient_id = %s",
            (patient_id,)
        )

        patient = cursor.fetchone()

        if not patient:
            print(
                "APPOINTMENT ERROR: Patient not found. Patient ID =",
                patient_id
            )

            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        # -----------------------------------
        # Check doctor
        # -----------------------------------
        cursor.execute(
            """
            SELECT doctor_id, is_available
            FROM doctors
            WHERE doctor_id = %s
            """,
            (doctor_id,)
        )

        doctor = cursor.fetchone()

        if not doctor:
            print(
                "APPOINTMENT ERROR: Doctor not found. Doctor ID =",
                doctor_id
            )

            return jsonify({
                "status": "error",
                "message": "Doctor not found"
            }), 404

        # -----------------------------------
        # Check doctor availability
        # -----------------------------------
        if doctor[1] != 'Y':
            print(
                "APPOINTMENT ERROR: Doctor unavailable. Doctor ID =",
                doctor_id
            )

            return jsonify({
                "status": "error",
                "message": "Selected doctor is currently unavailable"
            }), 404

        # -----------------------------------
        # Check that the doctor is free at this time.
        # Two bookings overlap when one starts before the other ends.
        # Cancelled and Rejected bookings do not block a time.
        # -----------------------------------

        # Lock this doctor's bookings while we check and save, so two
        # patients cannot take the same time at the same moment.
        # (The lock is released automatically at the end of the request.)
        cursor.execute("SELECT pg_advisory_xact_lock(%s)", (doctor_id,))

        cursor.execute("""
            SELECT 1
            FROM appointments
            WHERE doctor_id = %s
              AND appointment_date = %s
              AND status IN ('Pending', 'Scheduled')
              AND start_time < %s::time
              AND COALESCE(
                    end_time,
                    start_time + INTERVAL '30 minutes'
                  ) > %s::time
            LIMIT 1
        """, (doctor_id, appointment_date, end_time, start_time))

        if cursor.fetchone():
            return jsonify({
                "status": "error",
                "message": "This time is already booked. Please choose another time."
            }), 409

        # -----------------------------------
        # Create appointment
        # -----------------------------------
        cursor.execute(
            """
            INSERT INTO appointments
            (
                patient_id,
                doctor_id,
                appointment_date,
                start_time,
                end_time,
                consultation_mode,
                reason_for_visit,
                status
            )
            VALUES
            (
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                %s,
                'Scheduled'
            )
            RETURNING appointment_id
            """,
            (
                patient_id,
                doctor_id,
                appointment_date,
                start_time,
                end_time,
                consultation_mode,
                reason_for_visit
            )
        )

        appointment_id = cursor.fetchone()[0]

        # A new booking waits for the doctor's decision (Pending).
        # This runs in the same transaction as the booking above.
        cursor.execute("""
            UPDATE appointments
            SET status = 'Pending'
            WHERE appointment_id = %s
        """, (appointment_id,))

        conn.commit()

        print(
            "APPOINTMENT CREATED. Appointment ID =",
            appointment_id
        )

        # ----- Tell the doctor about the new request. A problem here
        # must never undo the booking, so it has its own try/except. -----
        try:
            cursor.execute("""
                SELECT du.user_id, pu.full_name
                FROM doctors d
                JOIN users du
                    ON d.user_id = du.user_id
                CROSS JOIN patients p
                JOIN users pu
                    ON p.user_id = pu.user_id
                WHERE d.doctor_id = %s
                  AND p.patient_id = %s
            """, (doctor_id, patient_id))

            info = cursor.fetchone()

            if info:
                doctor_user_id = info[0]
                patient_name = info[1]

                when = f"{appointment_date} at {str(start_time)[:5]}"
                title = "New appointment request"
                message = f"{patient_name} requested an appointment on {when}."

                # Save the notice (for the Alerts list)
                cursor.execute("""
                    INSERT INTO notifications
                        (user_id, title, message, type, appointment_id)
                    VALUES (%s, %s, %s, 'AppointmentRequest', %s)
                """, (doctor_user_id, title, message, appointment_id))

                conn.commit()

                # Send the push notification to the doctor's phone(s)
                send_push_to_user(
                    doctor_user_id,
                    title,
                    message,
                    {
                        "type": "AppointmentRequest",
                        "appointment_id": str(appointment_id)
                    }
                )

        except Exception as notice_error:
            conn.rollback()
            print("Booking notice error:", notice_error)

        return jsonify({
            "status": "success",
            "message": "Appointment booked successfully",
            "appointment_id": appointment_id
        }), 201

    except Exception as e:

        if conn:
            conn.rollback()

        print("Appointment Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to create appointment"
        }), 500

    finally:

        if cursor:
            cursor.close()

        if conn:
            conn.close()

@app.route("/api/appointments/<int:patient_id>", methods=["GET"])
def get_patient_appointments(patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute(
            """
            SELECT
                a.appointment_id,
                a.appointment_date,
                a.start_time,
                a.end_time,
                a.consultation_mode,
                a.reason_for_visit,
                a.status,
                d.doctor_id,
                u.full_name,
                s.spec_name,
                d.qualification,
                d.experience_years
            FROM appointments a
            JOIN doctors d
                ON a.doctor_id = d.doctor_id
            JOIN users u
                ON d.user_id = u.user_id
            JOIN specializations s
                ON d.specialization_id = s.spec_id
            WHERE a.patient_id = %s
            ORDER BY a.appointment_date DESC, a.start_time DESC
            """,
            (patient_id,)
        )

        appointments = cursor.fetchall()

        appointment_list = []

        for appointment in appointments:
            appointment_list.append({
                "appointment_id": appointment[0],
                "appointment_date": str(appointment[1]),
                "start_time": str(appointment[2]),
                "end_time": str(appointment[3]),
                "consultation_mode": appointment[4],
                "reason_for_visit": appointment[5],
                "status": appointment[6],
                "doctor_id": appointment[7],
                "doctor_name": appointment[8],
                "specialization": appointment[9],
                "qualification": appointment[10],
                "experience_years": appointment[11],
            })

        return jsonify({
            "status": "success",
            "appointments": appointment_list
        }), 200

    except Exception as e:
        print("Get Appointments Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load appointments"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()    
@app.route("/api/appointments/<int:appointment_id>/cancel", methods=["PUT"])
def cancel_appointment(appointment_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Check whether the appointment exists
        cursor.execute("""
            SELECT status
            FROM appointments
            WHERE appointment_id = %s
        """, (appointment_id,))

        appointment = cursor.fetchone()

        if not appointment:
            return jsonify({
                "status": "error",
                "message": "Appointment not found"
            }), 404

        current_status = appointment[0]

        # Prevent cancelling an already completed appointment
        if current_status == "Completed":
            return jsonify({
                "status": "error",
                "message": "Completed appointments cannot be cancelled"
            }), 400

        # Prevent cancelling an already cancelled appointment
        if current_status == "Cancelled":
            return jsonify({
                "status": "error",
                "message": "Appointment is already cancelled"
            }), 400

        # Update appointment status
        cursor.execute("""
            UPDATE appointments
            SET status = 'Cancelled'
            WHERE appointment_id = %s
        """, (appointment_id,))

        conn.commit()

        print("APPOINTMENT CANCELLED. Appointment ID =", appointment_id)

        # ----- Tell the doctor. Only for bookings the doctor knew about
        # (Pending or Scheduled). A problem here must never undo the
        # cancellation, so it has its own try/except. -----
        if current_status in ("Pending", "Scheduled"):
            try:
                cursor.execute("""
                    SELECT du.user_id, pu.full_name,
                           a.appointment_date, a.start_time
                    FROM appointments a
                    JOIN doctors d
                        ON a.doctor_id = d.doctor_id
                    JOIN users du
                        ON d.user_id = du.user_id
                    JOIN patients p
                        ON a.patient_id = p.patient_id
                    JOIN users pu
                        ON p.user_id = pu.user_id
                    WHERE a.appointment_id = %s
                """, (appointment_id,))

                info = cursor.fetchone()

                if info:
                    doctor_user_id = info[0]
                    patient_name = info[1]
                    when = f"{info[2]} at {str(info[3])[:5]}"

                    title = "Appointment cancelled"
                    message = f"{patient_name} cancelled the appointment on {when}."

                    # Save the notice (for the Alerts list)
                    cursor.execute("""
                        INSERT INTO notifications
                            (user_id, title, message, type, appointment_id)
                        VALUES (%s, %s, %s, 'AppointmentCancelled', %s)
                    """, (doctor_user_id, title, message, appointment_id))

                    conn.commit()

                    # Send the push notification to the doctor's phone(s)
                    send_push_to_user(
                        doctor_user_id,
                        title,
                        message,
                        {
                            "type": "AppointmentCancelled",
                            "appointment_id": str(appointment_id)
                        }
                    )

            except Exception as notice_error:
                conn.rollback()
                print("Cancel notice error:", notice_error)

        return jsonify({
            "status": "success",
            "message": "Appointment cancelled successfully",
            "appointment_id": appointment_id
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Cancel Appointment Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to cancel appointment"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()                    
# ============================================================
# UPDATE SOS STATUS
# ============================================================

@app.route("/api/sos/<int:sos_id>/status", methods=["PATCH"])
def update_sos_status(sos_id):


    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    new_status = data.get("status")

    # Only allow statuses that exist in our SOS workflow
    allowed_statuses = [
        "Requested",
        "Assigned",
        "Enroute",
        "Arrived",
        "Closed"
    ]

    if new_status not in allowed_statuses:
        return jsonify({
            "status": "error",
            "message": "Invalid SOS status"
        }), 400

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Check whether SOS exists
        cursor.execute("""
            SELECT sos_id, status
            FROM sos_requests
            WHERE sos_id = %s
        """, (sos_id,))

        sos = cursor.fetchone()

        if not sos:
            cursor.close()
            conn.close()

            return jsonify({
                "status": "error",
                "message": "SOS request not found"
            }), 404

        # Update status
        cursor.execute("""
            UPDATE sos_requests
            SET status = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE sos_id = %s
            RETURNING sos_id, status
        """, (
            new_status,
            sos_id
        ))

        updated_sos = cursor.fetchone()

        conn.commit()

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "sos_id": updated_sos[0],
            "new_status": updated_sos[1],
            "message": "SOS status updated successfully"
        }), 200

    except Exception as e:

        if 'conn' in locals():
            conn.rollback()
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500      
# ============================================================
# GET DOCTORS
# ============================================================
@app.route("/api/doctors", methods=["GET"])
def get_doctors():
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                d.doctor_id,
                d.user_id,
                u.full_name,
                u.phone,
                s.spec_id,
                s.spec_name,
                d.qualification,
                d.experience_years,
                d.about,
                d.consultation_fee,
                d.is_available,
                d.approval_status
            FROM doctors d
            JOIN users u
                ON d.user_id = u.user_id
            JOIN specializations s
                ON d.specialization_id = s.spec_id
            WHERE u.role_id = 1
              AND d.is_available = 'Y'
              AND d.approval_status = 'Approved'
              AND u.status = 'Active'
            ORDER BY u.full_name
        """)

        doctors = cursor.fetchall()

        doctor_list = []

        for doctor in doctors:
            doctor_list.append({
                "doctor_id": doctor[0],
                "user_id": doctor[1],
                "full_name": doctor[2],
                "phone": doctor[3],
                "specialization_id": doctor[4],
                "specialization": doctor[5],
                "qualification": doctor[6],
                "experience_years": doctor[7],
                "about": doctor[8],
                "consultation_fee": float(doctor[9]),
                "is_available": doctor[10]
            })

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "doctors": doctor_list
        }), 200

    except Exception as e:
        if 'conn' in locals():
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
@app.route('/api/doctors/register', methods=['POST'])
def register_doctor():
    try:
        data = request.get_json()

        full_name = data.get('full_name')
        phone = data.get('phone')
        registration_number = data.get('registration_number')
        qualification = data.get('qualification')
        specialization_id = data.get('specialization_id')
        experience_years = data.get('experience_years')
        hospital_id = data.get('hospital_id')

        # Basic validation
        if not full_name or not phone:
            return jsonify({
                "status": "error",
                "message": "Full name and phone are required"
            }), 400

        if not registration_number:
            return jsonify({
                "status": "error",
                "message": "Medical registration number is required"
            }), 400

        if not qualification:
            return jsonify({
                "status": "error",
                "message": "Qualification is required"
            }), 400

        if not specialization_id:
            return jsonify({
                "status": "error",
                "message": "Specialization is required"
            }), 400

        if experience_years is None:
            return jsonify({
                "status": "error",
                "message": "Experience is required"
            }), 400

        conn = get_db_connection()
        cursor = conn.cursor()

        # Check whether phone already exists
        cursor.execute(
            "SELECT user_id FROM users WHERE phone = %s",
            (phone,)
        )

        existing_user = cursor.fetchone()

        if existing_user:
            cursor.close()
            conn.close()

            return jsonify({
                "status": "error",
                "message": "A user with this phone number already exists"
            }), 409

        # Create user account
        password_hash = generate_password_hash(
            "doctor_temp_password"
        )

        cursor.execute("""
            INSERT INTO users
                (full_name, phone, password_hash, role_id, status)
            VALUES
                (%s, %s, %s, 1, 'Active')
            RETURNING user_id
        """, (
            full_name,
            phone,
            password_hash
        ))

        user_id = cursor.fetchone()[0]

        # Create doctor
        cursor.execute("""
            INSERT INTO doctors
                (
                    user_id,
                    specialization_id,
                    qualification,
                    experience_years,
                    license_number,
                    is_available
                )
            VALUES
                (%s, %s, %s, %s, %s, 'Y')
            RETURNING doctor_id
        """, (
            user_id,
            specialization_id,
            qualification,
            experience_years,
            registration_number
        ))

        doctor_id = cursor.fetchone()[0]

        # Connect doctor to hospital if hospital_id was supplied
        if hospital_id is not None:

            cursor.execute("""
                SELECT hospital_id
                FROM hospitals
                WHERE hospital_id = %s
            """, (hospital_id,))

            hospital_exists = cursor.fetchone()

            if not hospital_exists:
                conn.rollback()
                cursor.close()
                conn.close()

                return jsonify({
                    "status": "error",
                    "message": "Selected hospital does not exist"
                }), 400

            cursor.execute("""
                INSERT INTO doctor_hospitals
                    (doctor_id, hospital_id, is_primary)
                VALUES
                    (%s, %s, 'Y')
            """, (
                doctor_id,
                hospital_id
            ))

        conn.commit()

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "message": "Doctor registered successfully",
            "user_id": user_id,
            "doctor_id": doctor_id
        }), 201

    except Exception as e:
        if 'conn' in locals():
            conn.rollback()
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
@app.route('/api/doctors/login', methods=['POST'])
def doctor_login():
    try:
        data = request.get_json()

        phone = data.get('phone')

        if not phone:
            return jsonify({
                "status": "error",
                "message": "Phone number is required"
            }), 400

        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                d.doctor_id,
                u.user_id,
                u.full_name,
                u.phone,
                d.specialization_id,
                s.spec_name,
                d.qualification,
                d.experience_years,
                d.license_number,
                d.is_available,
                d.approval_status
            FROM doctors d
            JOIN users u
                ON d.user_id = u.user_id
            JOIN specializations s
                ON d.specialization_id = s.spec_id
            WHERE u.phone = %s
              AND u.role_id = 1
              AND u.status = 'Active'
        """, (phone,))

        doctor = cursor.fetchone()

        cursor.close()
        conn.close()

        if not doctor:
            return jsonify({
                "status": "error",
                "message": "No registered doctor found with this phone number"
            }), 404
        if doctor[10] == "Pending":
            return jsonify({
                "status": "error",
                "message": "Your registration is waiting for admin approval."
            }), 403

        if doctor[10] == "Rejected":
            return jsonify({
                "status": "error",
                "message": "Your registration was not approved. Please contact support."
            }), 403

        return jsonify({
            "status": "success",
            "message": "Doctor found",
            "doctor": {
                "doctor_id": doctor[0],
                "user_id": doctor[1],
                "full_name": doctor[2],
                "phone": doctor[3],
                "specialization_id": doctor[4],
                "specialization": doctor[5],
                "qualification": doctor[6],
                "experience_years": doctor[7],
                "license_number": doctor[8],
                "is_available": doctor[9]
            }
        }), 200

    except Exception as e:
        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
@app.route('/api/doctors/<int:doctor_id>/appointments', methods=['GET'])
def get_doctor_appointments(doctor_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
          SELECT
           a.appointment_id,
           a.patient_id,
           u.full_name AS patient_name,
           a.appointment_date,
           a.start_time,
           a.end_time,
           a.consultation_mode,
           a.reason_for_visit,
           a.status
        FROM appointments a
        JOIN patients p
           ON a.patient_id = p.patient_id
        JOIN users u
           ON p.user_id = u.user_id
        WHERE a.doctor_id = %s
        ORDER BY a.appointment_date ASC,
              a.start_time ASC
   """, (doctor_id,))

        rows = cursor.fetchall()

        appointments = []

        for row in rows:
            appointments.append({
                "appointment_id": row[0],
                "patient_id": row[1],
                "patient_name": row[2],
                "appointment_date": str(row[3]),
                "start_time": str(row[4]),
                "end_time": str(row[5]),
                "consultation_mode": row[6],
                "reason_for_visit": row[7],
                "status": row[8],
            })

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "appointments": appointments
        }), 200

    except Exception as e:
        if 'conn' in locals():
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
@app.route('/api/doctors/<int:doctor_id>/appointments/<int:appointment_id>/complete', methods=['PUT'])
def complete_doctor_appointment(doctor_id, appointment_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            UPDATE appointments
            SET status = 'Completed'
            WHERE appointment_id = %s
              AND doctor_id = %s
              AND status = 'Scheduled'
            RETURNING appointment_id
        """, (appointment_id, doctor_id))

        updated_appointment = cursor.fetchone()

        if not updated_appointment:
            conn.rollback()
            cursor.close()
            conn.close()

            return jsonify({
                "status": "error",
                "message": "Appointment not found or is not scheduled."
            }), 404

        conn.commit()
        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "message": "Appointment marked as completed.",
            "appointment_id": updated_appointment[0]
        }), 200

    except Exception as e:
        if 'conn' in locals():
            conn.rollback()
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500


@app.route('/api/doctors/appointments/<int:appointment_id>/consultation', methods=['POST'])
def save_consultation(appointment_id):
    try:
        data = request.get_json()

        consultation_type = data.get('consultation_type')
        chief_complaint = data.get('chief_complaint')
        diagnosis = data.get('diagnosis')
        notes = data.get('notes')
        advice = data.get('advice')
        follow_up_date = data.get('follow_up_date')

        if not all([chief_complaint, diagnosis, notes, advice]):
            return jsonify({
                "status": "error",
                "message": "Please provide all required consultation details."
            }), 400

        conn = get_db_connection()
        cursor = conn.cursor()

        # Verify that the appointment exists and is scheduled.
        cursor.execute("""
            SELECT appointment_id, doctor_id
            FROM appointments
            WHERE appointment_id = %s
              AND status = 'Scheduled'
              AND appointment_date + start_time <= CURRENT_TIMESTAMP
        """, (appointment_id,))

        appointment = cursor.fetchone()

        if not appointment:
            cursor.close()
            conn.close()
            return jsonify({
                "status": "error",
                "message": "Appointment is not available for consultation yet."
            }), 404

        cursor.execute("""
            INSERT INTO consultations (
                appointment_id,
                consultation_type,
                chief_complaint,
                diagnosis,
                notes,
                advice,
                follow_up_date
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING consultation_id
        """, (
            appointment_id,
            consultation_type,
            chief_complaint,
            diagnosis,
            notes,
            advice,
            follow_up_date
        ))

        consultation_id = cursor.fetchone()[0]

        cursor.execute("""
            UPDATE appointments
            SET status = 'Completed'
            WHERE appointment_id = %s
        """, (appointment_id,))

        conn.commit()
        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "message": "Consultation saved successfully.",
            "consultation_id": consultation_id
        }), 201

    except Exception as e:
        if 'conn' in locals():
            conn.rollback()
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500
@app.route('/api/doctors/<int:doctor_id>/consultations', methods=['GET'])
def get_doctor_consultations(doctor_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                a.appointment_id,
                a.patient_id,
                u.full_name AS patient_name,
                a.appointment_date,
                a.start_time,
                a.end_time,
                a.consultation_mode,
                a.reason_for_visit,
                a.status
            FROM appointments a
            JOIN patients p ON a.patient_id = p.patient_id
            JOIN users u ON p.user_id = u.user_id
            WHERE a.doctor_id = %s
              AND a.status = 'Scheduled'
              AND (a.appointment_date + a.start_time)
                    <= CURRENT_TIMESTAMP::timestamp
            ORDER BY a.appointment_date ASC, a.start_time ASC
        """, (doctor_id,))

        rows = cursor.fetchall()

        consultations = []

        for row in rows:
            consultations.append({
                "appointment_id": row[0],
                "patient_id": row[1],
                "patient_name": row[2],
                "appointment_date": str(row[3]),
                "start_time": str(row[4]),
                "end_time": str(row[5]),
                "consultation_mode": row[6],
                "reason_for_visit": row[7],
                "status": row[8]
            })

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "consultations": consultations
        }), 200

    except Exception as e:
        if 'conn' in locals():
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500

# ============================================================
# DOCTOR'S CONSULTATION QUEUE
# Every ACCEPTED (Scheduled) appointment of this doctor, even if
# its time has not come yet. "can_start" is true once the
# appointment time has arrived, so the app can switch on the
# Start button only then.
# Completed appointments are not here: they live in the
# consultation history.
# ============================================================
@app.route('/api/doctors/<int:doctor_id>/consultation-queue', methods=['GET'])
def get_doctor_consultation_queue(doctor_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                a.appointment_id,
                a.patient_id,
                u.full_name AS patient_name,
                a.appointment_date,
                a.start_time,
                a.end_time,
                a.consultation_mode,
                a.reason_for_visit,
                a.status,
                (a.appointment_date + a.start_time)
                    <= CURRENT_TIMESTAMP::timestamp AS can_start
            FROM appointments a
            JOIN patients p
                ON a.patient_id = p.patient_id
            JOIN users u
                ON p.user_id = u.user_id
            WHERE a.doctor_id = %s
              AND a.status = 'Scheduled'
            ORDER BY a.appointment_date ASC, a.start_time ASC
        """, (doctor_id,))

        consultations = []

        for row in cursor.fetchall():
            consultations.append({
                "appointment_id": row[0],
                "patient_id": row[1],
                "patient_name": row[2],
                "appointment_date": str(row[3]),
                "start_time": str(row[4]),
                "end_time": str(row[5]),
                "consultation_mode": row[6],
                "reason_for_visit": row[7],
                "status": row[8],
                "can_start": bool(row[9])
            })

        return jsonify({
            "status": "success",
            "consultations": consultations
        }), 200

    except Exception as e:
        print("Consultation Queue Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load consultations"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

@app.route('/api/doctors/<int:doctor_id>/consultation-history', methods=['GET'])
def get_doctor_consultation_history(doctor_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                c.consultation_id,
                c.appointment_id,
                a.patient_id,
                u.full_name AS patient_name,
                a.appointment_date,
                a.start_time,
                a.end_time,
                a.consultation_mode,
                a.reason_for_visit,
                c.consultation_type,
                c.chief_complaint,
                c.diagnosis,
                c.notes,
                c.advice,
                c.follow_up_date,
                c.created_at
            FROM consultations c
            JOIN appointments a
                ON c.appointment_id = a.appointment_id
            JOIN patients p
                ON a.patient_id = p.patient_id
            JOIN users u
                ON p.user_id = u.user_id
            WHERE a.doctor_id = %s
              AND a.status = 'Completed'
            ORDER BY c.created_at DESC
        """, (doctor_id,))

        rows = cursor.fetchall()
        columns = [description[0] for description in cursor.description]

        
        consultations = []

        for row in rows:
            consultation = dict(zip(columns, row))

            for key, value in consultation.items():
               if value is not None and hasattr(value, 'isoformat'):
                   consultation[key] = value.isoformat()

            consultations.append(consultation) 

        cursor.close()
        conn.close()

        return jsonify({
            "status": "success",
            "consultations": consultations
        }), 200

    except Exception as e:
        if 'conn' in locals():
            conn.close()

        return jsonify({
            "status": "error",
            "message": str(e)
        }), 500   
 # ============================================================
# GENERATE AGORA VIDEO CALL TOKEN
# ============================================================

@app.route("/api/appointments/<int:appointment_id>/video-token", methods=["GET"])
def generate_video_token(appointment_id):

    participant_id = request.args.get("participant_id", type=int)
    participant_role = request.args.get("participant_role")

    if not AGORA_APP_ID or not AGORA_APP_CERTIFICATE:
        return jsonify({
            "status": "error",
            "message": "Agora configuration is missing"
        }), 500

    if not participant_id or participant_role not in ["patient", "doctor"]:
        return jsonify({
            "status": "error",
            "message": "Valid participant details are required"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT patient_id, doctor_id, consultation_mode, status
            FROM appointments
            WHERE appointment_id = %s
        """, (appointment_id,))

        appointment = cursor.fetchone()

        if not appointment:
            return jsonify({
                "status": "error",
                "message": "Appointment not found"
            }), 404

        patient_id, doctor_id, consultation_mode, appointment_status = appointment

        # Verify that the participant belongs to this appointment
        if participant_role == "patient" and participant_id != patient_id:
            return jsonify({
                "status": "error",
                "message": "Patient does not belong to this appointment"
            }), 403

        if participant_role == "doctor" and participant_id != doctor_id:
            return jsonify({
                "status": "error",
                "message": "Doctor does not belong to this appointment"
            }), 403

        if consultation_mode != "Online":
            return jsonify({
                "status": "error",
                "message": "This appointment is not an online consultation"
            }), 400

        if appointment_status != "Scheduled":
            return jsonify({
                "status": "error",
                "message": "This appointment is not available for a video call"
            }), 400

         # When the DOCTOR joins, leave a notice for the patient.
        # A problem here must never stop the video call, so it has
        # its own try/except.
        if participant_role == "doctor":
            try:
                # Find the patient's user ID and the doctor's name
                cursor.execute("""
                    SELECT p.user_id, du.full_name
                    FROM patients p
                    CROSS JOIN doctors d
                    JOIN users du
                        ON d.user_id = du.user_id
                    WHERE p.patient_id = %s
                      AND d.doctor_id = %s
                """, (patient_id, doctor_id))

                notice_info = cursor.fetchone()

                if notice_info:
                    patient_user_id = notice_info[0]
                    doctor_name = notice_info[1]

                    # Skip it if the patient already has an unread notice
                    # for this appointment (for example after "Try Again")
                    cursor.execute("""
                        SELECT 1
                        FROM notifications
                        WHERE user_id = %s
                          AND appointment_id = %s
                          AND type = 'ConsultationStarted'
                          AND is_read = 'N'
                        LIMIT 1
                    """, (patient_user_id, appointment_id))

                    if not cursor.fetchone():
                          # Find out which language the patient chose
                        cursor.execute(
                            "SELECT language FROM users WHERE user_id = %s",
                            (patient_user_id,)
                        )
                        language_row = cursor.fetchone()
                        patient_language = (
                            language_row[0] if language_row else "en_IN"
                        )

                        # Get the title and texts in that language
                        # (English is used if the language is missing)
                        title, message, push_text = notif_text(
                            "ConsultationStarted",
                            patient_language,
                            doctor_name=doctor_name
                        )

                        # Save the notification in the patient's list
                        cursor.execute("""
                            INSERT INTO notifications
                                (user_id, title, message, type, appointment_id)
                            VALUES (%s, %s, %s, 'ConsultationStarted', %s)
                        """, (
                            patient_user_id,
                            title,
                            message,
                            appointment_id
                        ))

                        conn.commit()

                        # Also send a real push notification to the
                        # patient's phone(s), in the same language
                        send_push_to_user(
                            patient_user_id,
                            title,
                            push_text,
                            {
                                "type": "ConsultationStarted",
                                "appointment_id": str(appointment_id)
                            }
                        )                      
            except Exception as notice_error:
                # Forget the failed notice and carry on with the call
                conn.rollback()
                print("Consultation notice error:", notice_error)

        # Create the same channel for both participants  
        channel_name = f"rural_appt_{appointment_id}"

        # Give patient and doctor different Agora UIDs
        if participant_role == "patient":
            agora_uid = patient_id
        else:
            agora_uid = doctor_id + 1000000000

        # Token valid for one hour
        expiry_time = int(time.time()) + 3600

        token = RtcTokenBuilder.buildTokenWithUid(
            AGORA_APP_ID,
            AGORA_APP_CERTIFICATE,
            channel_name,
            agora_uid,
            1,
            expiry_time
        )

        return jsonify({
            "status": "success",
            "appointment_id": appointment_id,
            "channel_name": channel_name,
            "agora_uid": agora_uid,
            "agora_app_id": AGORA_APP_ID,
            "token": token,
            "message": "Video call token generated successfully"
        }), 200

    except Exception as e:
        print("Agora Token Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to generate video call token"
        }), 500

  
    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()   

# ============================================================
# SAVE PRESCRIPTION
# ============================================================

def parse_duration_days(text):
    # Turns text like "3 days", "2 weeks" or "1 month" into a number of days
    text = (text or "").lower()
    match = re.search(r"\d+", text)

    if not match:
        return None

    number = int(match.group())

    if number <= 0:
        return None

    if "week" in text:
        number = number * 7
    elif "month" in text:
        number = number * 30

    return number


@app.route("/api/prescriptions", methods=["POST"])
def save_prescription():
    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    doctor_id = data.get("doctor_id")
    consultation_id = data.get("consultation_id")
    notes = data.get("notes")
    medicines = data.get("medicines")

    if not doctor_id or not consultation_id:
        return jsonify({
            "status": "error",
            "message": "doctor_id and consultation_id are required"
        }), 400

    if not medicines or not isinstance(medicines, list):
        return jsonify({
            "status": "error",
            "message": "Please add at least one medicine"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # The consultation must belong to this doctor
        cursor.execute("""
            SELECT c.consultation_id
            FROM consultations c
            JOIN appointments a
                ON c.appointment_id = a.appointment_id
            WHERE c.consultation_id = %s
              AND a.doctor_id = %s
        """, (consultation_id, doctor_id))

        if not cursor.fetchone():
            return jsonify({
                "status": "error",
                "message": "Consultation not found for this doctor"
            }), 404

        # Category used for medicines that are not in the catalog yet
        cursor.execute("""
            SELECT category_id
            FROM medicine_categories
            WHERE category_name = 'General Medicine'
        """)

        category = cursor.fetchone()

        if not category:
            return jsonify({
                "status": "error",
                "message": "General Medicine category is missing"
            }), 500

        general_category_id = category[0]

        # Create the prescription
        cursor.execute("""
            INSERT INTO prescriptions (consultation_id, notes)
            VALUES (%s, %s)
            RETURNING prescription_id
        """, (
            consultation_id,
            notes if notes else None
        ))

        prescription_id = cursor.fetchone()[0]

        used_medicine_ids = set()

        for item in medicines:
            name = (item.get("medicine") or "").strip()

            if not name:
                conn.rollback()
                return jsonify({
                    "status": "error",
                    "message": "Medicine name is required"
                }), 400

            # Find the medicine in the catalog (ignore capital letters)
            cursor.execute("""
                SELECT medicine_id
                FROM medicine_catalog
                WHERE LOWER(medicine_name) = LOWER(%s)
                LIMIT 1
            """, (name,))

            row = cursor.fetchone()

            if row:
                medicine_id = row[0]
            else:
                cursor.execute("""
                    INSERT INTO medicine_catalog
                        (category_id, medicine_name)
                    VALUES (%s, %s)
                    RETURNING medicine_id
                """, (general_category_id, name))

                medicine_id = cursor.fetchone()[0]

            if medicine_id in used_medicine_ids:
                conn.rollback()
                return jsonify({
                    "status": "error",
                    "message": "The same medicine was added twice"
                }), 400

            used_medicine_ids.add(medicine_id)

            cursor.execute("""
                INSERT INTO prescription_medicines
                (
                    prescription_id,
                    medicine_id,
                    dose,
                    frequency,
                    duration_days,
                    instructions
                )
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (
                prescription_id,
                medicine_id,
                item.get("dosage"),
                item.get("frequency"),
                parse_duration_days(item.get("duration")),
                item.get("instructions") or None
            ))

        conn.commit()

        # ----- Tell the patient. A problem here must never undo the
        # saved prescription, so it has its own try/except. -----
        try:
            cursor.execute("""
                SELECT p.user_id, du.full_name
                FROM consultations c
                JOIN appointments a
                    ON c.appointment_id = a.appointment_id
                JOIN patients p
                    ON a.patient_id = p.patient_id
                JOIN doctors d
                    ON a.doctor_id = d.doctor_id
                JOIN users du
                    ON d.user_id = du.user_id
                WHERE c.consultation_id = %s
            """, (consultation_id,))

            info = cursor.fetchone()

            if info:
                patient_user_id = info[0]
                doctor_name = info[1]

                title = "New prescription"
                message = (
                    f"{doctor_name} has issued your prescription. "
                    "You can order the medicines within 7 days."
                )

                # Save the notice (for the Alerts list)
                cursor.execute("""
                    INSERT INTO notifications
                        (user_id, title, message, type)
                    VALUES (%s, %s, %s, 'PrescriptionIssued')
                """, (patient_user_id, title, message))

                conn.commit()

                # Send the push notification to the patient's phone(s)
                send_push_to_user(
                    patient_user_id,
                    title,
                    message,
                    {
                        "type": "PrescriptionIssued",
                        "prescription_id": str(prescription_id)
                    }
                )

        except Exception as notice_error:
            conn.rollback()
            print("Prescription notice error:", notice_error)

        return jsonify({
            "status": "success",
            "message": "Prescription saved successfully",
        }), 201

    except Exception as e:
        if conn:
            conn.rollback()

        print("Save Prescription Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to save prescription"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()     

# ============================================================
# GET A PATIENT'S PRESCRIPTIONS
# ============================================================

@app.route("/api/patients/<int:patient_id>/prescriptions", methods=["GET"])
def get_patient_prescriptions(patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                p.prescription_id,
                p.prescription_date,
                p.notes,
                c.diagnosis,
                u.full_name AS doctor_name,
                s.spec_name,
                m.medicine_name,
                pm.dose,
                pm.frequency,
                pm.duration_days,
                pm.instructions,
                (CURRENT_DATE - p.prescription_date) > 7 AS expired,
                pu.full_name AS patient_name,
                d.signature_image AS doctor_signature
            FROM prescriptions p  
            JOIN consultations c
                ON p.consultation_id = c.consultation_id
            JOIN appointments a
                ON c.appointment_id = a.appointment_id
            JOIN doctors d
                ON a.doctor_id = d.doctor_id
            JOIN users u
                ON d.user_id = u.user_id
            JOIN specializations s
                ON d.specialization_id = s.spec_id
            JOIN patients pt
                ON a.patient_id = pt.patient_id
            JOIN users pu
                ON pt.user_id = pu.user_id
            LEFT JOIN prescription_medicines pm
                ON pm.prescription_id = p.prescription_id
            LEFT JOIN medicine_catalog m
                ON pm.medicine_id = m.medicine_id
            WHERE a.patient_id = %s
            ORDER BY p.created_at DESC, p.prescription_id DESC, pm.id ASC
        """, (patient_id,))

        rows = cursor.fetchall()

        prescriptions = {}

        for row in rows:
            prescription_id = row[0]

            if prescription_id not in prescriptions:
                prescriptions[prescription_id] = {
                    "prescription_id": prescription_id,
                    "prescription_date": str(row[1]),
                    "notes": row[2],
                    "diagnosis": row[3],
                    "doctor_name": row[4],
                    "specialization": row[5],
                    "expired": row[11],  # True if older than 7 days
                    "patient_name": row[12],  # Shown on the PDF
                    "doctor_signature": row[13],  # Shown on the PDF          # Shown on the PDF# True if older than 7 days
                    "medicines": []
                }

            if row[6] is not None:
                prescriptions[prescription_id]["medicines"].append({
                    "medicine": row[6],
                    "dosage": row[7],
                    "frequency": row[8],
                    "duration_days": row[9],
                    "instructions": row[10]
                })

        return jsonify({
            "status": "success",
            "prescriptions": list(prescriptions.values())
        }), 200

    except Exception as e:
        print("Get Patient Prescriptions Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load prescriptions"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()   

 # ============================================================
# GET A DOCTOR'S PRESCRIPTIONS
# Returns every prescription written by one doctor.
# ============================================================

@app.route("/api/doctors/<int:doctor_id>/prescriptions", methods=["GET"])
def get_doctor_prescriptions(doctor_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # One row is returned per medicine, so a prescription with
        # 3 medicines comes back as 3 rows. We group them below.
        cursor.execute("""
            SELECT
                p.prescription_id,
                p.prescription_date,
                p.notes,
                c.diagnosis,
                pu.full_name AS patient_name,
                m.medicine_name,
                pm.dose,
                pm.frequency,
                pm.duration_days,
                pm.instructions,
                du.full_name AS doctor_name,
                s.spec_name AS specialization,
                d.signature_image AS doctor_signature
            FROM prescriptions p
            JOIN consultations c
                ON p.consultation_id = c.consultation_id
            JOIN appointments a
                ON c.appointment_id = a.appointment_id
            JOIN patients pt
                ON a.patient_id = pt.patient_id
            JOIN users pu
                ON pt.user_id = pu.user_id
            JOIN doctors d
                ON a.doctor_id = d.doctor_id
            JOIN users du
                ON d.user_id = du.user_id
            JOIN specializations s
                ON d.specialization_id = s.spec_id
            LEFT JOIN prescription_medicines pm
                ON pm.prescription_id = p.prescription_id
            LEFT JOIN medicine_catalog m
                ON pm.medicine_id = m.medicine_id
            WHERE a.doctor_id = %s
            ORDER BY p.created_at DESC, p.prescription_id DESC, pm.id ASC
        """, (doctor_id,))

        rows = cursor.fetchall()

        # Group the rows so each prescription appears only once
        prescriptions = {}

        for row in rows:
            prescription_id = row[0]

            # First time we see this prescription: create its entry
            if prescription_id not in prescriptions:
                prescriptions[prescription_id] = {
                    "prescription_id": prescription_id,
                    "prescription_date": str(row[1]),
                    "notes": row[2],
                    "diagnosis": row[3],
                    "patient_name": row[4],
                    "doctor_name": row[10],  # Shown on the PDF
                    "specialization": row[11],  # Shown on the PDF
                    "doctor_signature": row[12],  # Shown on the PDF # Shown on the PDF
                    "medicines": []
                }

            # Add this row's medicine (if the prescription has one)
            if row[5] is not None:
                prescriptions[prescription_id]["medicines"].append({
                    "medicine": row[5],
                    "dosage": row[6],
                    "frequency": row[7],
                    "duration_days": row[8],
                    "instructions": row[9]
                })

        return jsonify({
            "status": "success",
            "prescriptions": list(prescriptions.values())
        }), 200

    except Exception as e:
        print("Get Doctor Prescriptions Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load prescriptions"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()  
            
# ============================================================
# PLACE A MEDICINE ORDER FROM A PRESCRIPTION
# Creates an order with 1 pack of every medicine on the prescription.
# ============================================================

@app.route("/api/medicine-orders", methods=["POST"])
def place_medicine_order():
    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    patient_id = data.get("patient_id")
    prescription_id = data.get("prescription_id")
    delivery_address = (data.get("delivery_address") or "").strip()
    payment_method = data.get("payment_method")

    # Check the required details
    if not patient_id or not prescription_id:
        return jsonify({
            "status": "error",
            "message": "patient_id and prescription_id are required"
        }), 400

    if not delivery_address:
        return jsonify({
            "status": "error",
            "message": "Please enter a delivery address"
        }), 400

    # Only the payment methods that exist in the payment_methods table
    if payment_method not in ["COD", "Card", "UPI", "Wallet"]:
        return jsonify({
            "status": "error",
            "message": "Please choose a valid payment method"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # The prescription must belong to this patient
        cursor.execute("""
            SELECT p.prescription_id
            FROM prescriptions p
            JOIN consultations c
                ON p.consultation_id = c.consultation_id
            JOIN appointments a
                ON c.appointment_id = a.appointment_id
            WHERE p.prescription_id = %s
              AND a.patient_id = %s
        """, (prescription_id, patient_id))

        if not cursor.fetchone():
            return jsonify({
                "status": "error",
                "message": "Prescription not found for this patient"
            }), 404

                # Prescriptions older than 7 days cannot be used to order.
        # (CURRENT_DATE - prescription_date) is the age in days.
        cursor.execute("""
            SELECT (CURRENT_DATE - prescription_date) > 7
            FROM prescriptions
            WHERE prescription_id = %s
        """, (prescription_id,))

        is_expired = cursor.fetchone()[0]

        if is_expired:
            return jsonify({
                "status": "error",
                "message": "This prescription is more than 7 days old. Please consult the doctor again for a new prescription."
            }), 400

        # Get every medicine on the prescription, with its price
        cursor.execute("""
            SELECT
                pm.medicine_id,
                mc.unit_price
            FROM prescription_medicines pm
            JOIN medicine_catalog mc
                ON pm.medicine_id = mc.medicine_id
            WHERE pm.prescription_id = %s
        """, (prescription_id,))

        items = cursor.fetchall()

        if not items:
            return jsonify({
                "status": "error",
                "message": "This prescription has no medicines to order"
            }), 400

        # First version: 1 pack of each medicine
        quantity = 1

        # Add up the price of all medicines
        total_amount = sum(float(item[1]) * quantity for item in items)

        # Create the order
        cursor.execute("""
            INSERT INTO medicine_orders
                (patient_id, total_amount, status,
                 delivery_address, payment_method)
            VALUES (%s, %s, 'Placed', %s, %s)
            RETURNING order_id
        """, (
            patient_id,
            total_amount,
            delivery_address,
            payment_method
        ))

        order_id = cursor.fetchone()[0]

        # Add one row to the order for each medicine
        for item in items:
            medicine_id = item[0]
            unit_price = float(item[1])

            cursor.execute("""
                INSERT INTO medicine_order_items
                    (order_id, medicine_id, quantity,
                     unit_price, total_price)
                VALUES (%s, %s, %s, %s, %s)
            """, (
                order_id,
                medicine_id,
                quantity,
                unit_price,
                unit_price * quantity
            ))

        # Save the order and its items together
        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Order placed successfully",
            "order_id": order_id,
            "total_amount": total_amount
        }), 201

    except Exception as e:
        if conn:
            conn.rollback()

        print("Place Medicine Order Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to place the order"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()  

# ============================================================
# GET A PATIENT'S MEDICINE ORDERS
# Used for "Your Orders" and "Track Your Order" in the app.
# ============================================================

@app.route("/api/patients/<int:patient_id>/medicine-orders", methods=["GET"])
def get_patient_medicine_orders(patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # One row is returned per medicine in an order, so an order
        # with 3 medicines comes back as 3 rows. We group them below.
        cursor.execute("""
            SELECT
                o.order_id,
                o.order_date,
                o.total_amount,
                o.status,
                o.delivery_address,
                o.payment_method,
                mc.medicine_name,
                oi.quantity,
                oi.unit_price,
                oi.total_price
            FROM medicine_orders o
            LEFT JOIN medicine_order_items oi
                ON oi.order_id = o.order_id
            LEFT JOIN medicine_catalog mc
                ON oi.medicine_id = mc.medicine_id
            WHERE o.patient_id = %s
            ORDER BY o.order_date DESC, o.order_id DESC, oi.id ASC
        """, (patient_id,))

        rows = cursor.fetchall()

        # Group the rows so each order appears only once
        orders = {}

        for row in rows:
            order_id = row[0]

            # First time we see this order: create its entry
            if order_id not in orders:
                orders[order_id] = {
                    "order_id": order_id,
                    "order_date": str(row[1]),
                    "total_amount": float(row[2]),
                    "status": row[3],
                    "delivery_address": row[4],
                    "payment_method": row[5],
                    "items": []
                }

            # Add this row's medicine (if the order has one)
            if row[6] is not None:
                orders[order_id]["items"].append({
                    "medicine": row[6],
                    "quantity": row[7],
                    "unit_price": float(row[8]),
                    "total_price": float(row[9])
                })

        return jsonify({
            "status": "success",
            "orders": list(orders.values())
        }), 200

    except Exception as e:
        print("Get Medicine Orders Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load orders"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()
# ============================================================
# DOCTOR SIGNATURE
# The signature is a small PNG picture, sent by the app as text
# (base64) and stored in the doctors table.
# ============================================================

# Read the saved signature of a doctor
@app.route("/api/doctors/<int:doctor_id>/signature", methods=["GET"])
def get_doctor_signature(doctor_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT signature_image
            FROM doctors
            WHERE doctor_id = %s
        """, (doctor_id,))

        row = cursor.fetchone()

        # No doctor with this ID
        if not row:
            return jsonify({
                "status": "error",
                "message": "Doctor not found"
            }), 404

        # row[0] is empty (null) if the doctor has not drawn one yet
        return jsonify({
            "status": "success",
            "signature": row[0]
        }), 200

    except Exception as e:
        print("Get Signature Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load signature"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# Save (or replace) the signature of a doctor
@app.route("/api/doctors/<int:doctor_id>/signature", methods=["PUT"])
def save_doctor_signature(doctor_id):
    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    signature = data.get("signature")

    # The signature must be a non-empty piece of text
    if not signature or not isinstance(signature, str):
        return jsonify({
            "status": "error",
            "message": "Signature is required"
        }), 400

    # Reject very large pictures (about 500 KB of text is plenty)
    if len(signature) > 500000:
        return jsonify({
            "status": "error",
            "message": "Signature image is too large"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            UPDATE doctors
            SET signature_image = %s
            WHERE doctor_id = %s
            RETURNING doctor_id
        """, (signature, doctor_id))

        if not cursor.fetchone():
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "Doctor not found"
            }), 404

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Signature saved successfully"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Save Signature Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to save signature"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# GET A PATIENT'S HEALTH RECORD
# Returns the patient's consultation history and their saved
# records (allergies, conditions, immunizations, surgeries).
# ============================================================

@app.route("/api/patients/<int:patient_id>/health-record", methods=["GET"])
def get_patient_health_record(patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # ----- Past consultations, newest first -----
        cursor.execute("""
            SELECT
                c.consultation_id,
                a.appointment_date,
                c.consultation_type,
                c.chief_complaint,
                c.diagnosis,
                c.notes,
                c.advice,
                c.follow_up_date,
                u.full_name AS doctor_name,
                s.spec_name AS specialization
            FROM consultations c
            JOIN appointments a
                ON c.appointment_id = a.appointment_id
            JOIN doctors d
                ON a.doctor_id = d.doctor_id
            JOIN users u
                ON d.user_id = u.user_id
            JOIN specializations s
                ON d.specialization_id = s.spec_id
            WHERE a.patient_id = %s
            ORDER BY a.appointment_date DESC, c.consultation_id DESC
        """, (patient_id,))

        consultations = []

        for row in cursor.fetchall():
            consultations.append({
                "consultation_id": row[0],
                "appointment_date": str(row[1]),
                "consultation_type": row[2],
                "chief_complaint": row[3],
                "diagnosis": row[4],
                "notes": row[5],
                "advice": row[6],
                # follow_up_date can be empty, so only convert if it exists
                "follow_up_date": str(row[7]) if row[7] else None,
                "doctor_name": row[8],
                "specialization": row[9]
            })

        # ----- The patient's own records, newest first -----
        cursor.execute("""
            SELECT
                record_id,
                record_type,
                description,
                record_date
            FROM medical_records
            WHERE patient_id = %s
            ORDER BY created_at DESC, record_id DESC
        """, (patient_id,))

        records = []

        for row in cursor.fetchall():
            records.append({
                "record_id": row[0],
                "record_type": row[1],
                "description": row[2],
                "record_date": str(row[3]) if row[3] else None
            })

        return jsonify({
            "status": "success",
            "consultations": consultations,
            "records": records
        }), 200

    except Exception as e:
        print("Get Health Record Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load health record"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# ADD A MEDICAL RECORD
# The patient adds an allergy, condition, immunization, etc.
# ============================================================

@app.route("/api/patients/<int:patient_id>/medical-records", methods=["POST"])
def add_medical_record(patient_id):
    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    record_type = data.get("record_type")
    description = (data.get("description") or "").strip()
    record_date = data.get("record_date")  # Optional, like 2026-10-22

    # Only the types allowed by the database
    allowed_types = [
        "Allergy",
        "Condition",
        "Immunization",
        "Surgery",
        "Other"
    ]

    if record_type not in allowed_types:
        return jsonify({
            "status": "error",
            "message": "Please choose a valid record type"
        }), 400

    if not description:
        return jsonify({
            "status": "error",
            "message": "Please enter a description"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # The patient must exist
        cursor.execute(
            "SELECT patient_id FROM patients WHERE patient_id = %s",
            (patient_id,)
        )

        if not cursor.fetchone():
            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        cursor.execute("""
            INSERT INTO medical_records
                (patient_id, record_type, description, record_date)
            VALUES (%s, %s, %s, %s)
            RETURNING record_id
        """, (
            patient_id,
            record_type,
            description,
            record_date if record_date else None
        ))

        record_id = cursor.fetchone()[0]

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Record added successfully",
            "record_id": record_id
        }), 201

    except Exception as e:
        if conn:
            conn.rollback()

        print("Add Medical Record Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to add the record"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ============================================================
# DELETE A MEDICAL RECORD
# Removes one record, but only if it belongs to this patient.
# ============================================================

@app.route(
    "/api/patients/<int:patient_id>/medical-records/<int:record_id>",
    methods=["DELETE"]
)
def delete_medical_record(patient_id, record_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            DELETE FROM medical_records
            WHERE record_id = %s
              AND patient_id = %s
            RETURNING record_id
        """, (record_id, patient_id))

        if not cursor.fetchone():
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "Record not found"
            }), 404

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Record deleted"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Delete Medical Record Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to delete the record"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()
# ============================================================
# GET A DOCTOR'S PATIENTS
# Lists the patients who have (or had) an appointment with
# this doctor. Cancelled appointments do not count.
# ============================================================

@app.route("/api/doctors/<int:doctor_id>/patients", methods=["GET"])
def get_doctor_patients(doctor_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # One row per patient. MAX() picks the newest appointment date.
        # The age is worked out from the date of birth (empty if unknown).
        cursor.execute("""
            SELECT
                pt.patient_id,
                u.full_name,
                u.phone,
                pt.gender,
                CASE
                    WHEN pt.date_of_birth IS NULL THEN NULL
                    ELSE DATE_PART('year', AGE(pt.date_of_birth))::int
                END AS age,
                MAX(a.appointment_date) AS last_visit
            FROM appointments a
            JOIN patients pt
                ON a.patient_id = pt.patient_id
            JOIN users u
                ON pt.user_id = u.user_id
            WHERE a.doctor_id = %s
              AND a.status IN ('Scheduled', 'Completed', 'Rescheduled')
            GROUP BY
                pt.patient_id,
                u.full_name,
                u.phone,
                pt.gender,
                pt.date_of_birth
            ORDER BY MAX(a.appointment_date) DESC
        """, (doctor_id,))

        patients = []

        for row in cursor.fetchall():
            patients.append({
                "patient_id": row[0],
                "full_name": row[1],
                "phone": row[2],
                "gender": row[3],
                "age": row[4],
                "last_visit": str(row[5]) if row[5] else None
            })

        return jsonify({
            "status": "success",
            "patients": patients
        }), 200

    except Exception as e:
        print("Get Doctor Patients Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load patients"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()
# ============================================================
# GET ONE PATIENT'S RECORD (FOR A DOCTOR)
# The doctor can only open patients they have an appointment with.
# ============================================================

@app.route(
    "/api/doctors/<int:doctor_id>/patients/<int:patient_id>/record",
    methods=["GET"]
)
def get_patient_record_for_doctor(doctor_id, patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # ----- Access check: does this doctor have an appointment
        # with this patient? If not, refuse. -----
        cursor.execute("""
            SELECT 1
            FROM appointments
            WHERE doctor_id = %s
              AND patient_id = %s
              AND status IN ('Scheduled', 'Completed', 'Rescheduled')
            LIMIT 1
        """, (doctor_id, patient_id))

        if not cursor.fetchone():
            return jsonify({
                "status": "error",
                "message": "You do not have access to this patient's record"
            }), 403

        # ----- The patient's profile -----
        cursor.execute("""
            SELECT
                u.full_name,
                u.phone,
                pt.gender,
                CASE
                    WHEN pt.date_of_birth IS NULL THEN NULL
                    ELSE DATE_PART('year', AGE(pt.date_of_birth))::int
                END AS age,
                pt.blood_group,
                pt.address,
                pt.emergency_contact_name,
                pt.emergency_contact_phone
            FROM patients pt
            JOIN users u
                ON pt.user_id = u.user_id
            WHERE pt.patient_id = %s
        """, (patient_id,))

        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        patient = {
            "patient_id": patient_id,
            "full_name": row[0],
            "phone": row[1],
            "gender": row[2],
            "age": row[3],
            "blood_group": row[4],
            "address": row[5],
            "emergency_contact_name": row[6],
            "emergency_contact_phone": row[7]
        }

        # ----- Consultations carried out by THIS doctor -----
        # (To show every doctor's consultations, delete the line
        #  "AND a.doctor_id = %s" and the doctor_id after patient_id below.)
        cursor.execute("""
            SELECT
                c.consultation_id,
                a.appointment_date,
                c.consultation_type,
                c.chief_complaint,
                c.diagnosis,
                c.notes,
                c.advice,
                c.follow_up_date
            FROM consultations c
            JOIN appointments a
                ON c.appointment_id = a.appointment_id
            WHERE a.patient_id = %s
              AND a.doctor_id = %s
            ORDER BY a.appointment_date DESC, c.consultation_id DESC
        """, (patient_id, doctor_id))

        consultations = []

        for r in cursor.fetchall():
            consultations.append({
                "consultation_id": r[0],
                "appointment_date": str(r[1]),
                "consultation_type": r[2],
                "chief_complaint": r[3],
                "diagnosis": r[4],
                "notes": r[5],
                "advice": r[6],
                "follow_up_date": str(r[7]) if r[7] else None
            })

        # ----- The patient's own records (allergies, conditions...) -----
        cursor.execute("""
            SELECT
                record_id,
                record_type,
                description,
                record_date
            FROM medical_records
            WHERE patient_id = %s
            ORDER BY created_at DESC, record_id DESC
        """, (patient_id,))

        records = []

        for r in cursor.fetchall():
            records.append({
                "record_id": r[0],
                "record_type": r[1],
                "description": r[2],
                "record_date": str(r[3]) if r[3] else None
            })

        return jsonify({
            "status": "success",
            "patient": patient,
            "consultations": consultations,
            "records": records
        }), 200

    except Exception as e:
        print("Get Patient Record For Doctor Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the patient record"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# MEDICAL REPORTS (lab results, scans)
# The file is saved in the server's "uploads/reports" folder.
# The database stores only the saved file name.
# ============================================================

# Only these kinds of file are accepted
ALLOWED_REPORT_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png"}

# The biggest upload we accept: 10 MB
MAX_REPORT_BYTES = 10 * 1024 * 1024

# The folder where report files are kept
REPORTS_FOLDER = os.path.join(UPLOAD_FOLDER, "reports")


# ----- Upload a report -----
@app.route("/api/patients/<int:patient_id>/reports", methods=["POST"])
def upload_report(patient_id):
    # The text fields that come with the file
    report_type = request.form.get("report_type")
    description = (request.form.get("description") or "").strip()
    report_date = request.form.get("report_date")  # Optional

    # The file itself
    file = request.files.get("file")

    # Only the types allowed by the database
    if report_type not in ["Lab", "Imaging", "Other"]:
        return jsonify({
            "status": "error",
            "message": "Please choose a valid report type"
        }), 400

    if not description:
        return jsonify({
            "status": "error",
            "message": "Please enter a title for the report"
        }), 400

    if not file or not file.filename:
        return jsonify({
            "status": "error",
            "message": "Please choose a file"
        }), 400

    # Refuse files that are too big
    if request.content_length and request.content_length > MAX_REPORT_BYTES:
        return jsonify({
            "status": "error",
            "message": "The file is too big. The limit is 10 MB."
        }), 400

    # Check the file type from its name
    extension = os.path.splitext(secure_filename(file.filename))[1].lower()

    if extension not in ALLOWED_REPORT_EXTENSIONS:
        return jsonify({
            "status": "error",
            "message": "Only PDF, JPG and PNG files are allowed"
        }), 400

    conn = None
    cursor = None
    saved_path = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # The patient must exist
        cursor.execute(
            "SELECT patient_id FROM patients WHERE patient_id = %s",
            (patient_id,)
        )

        if not cursor.fetchone():
            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        # Save the file under a new random name, so two files with
        # the same name can never overwrite each other
        os.makedirs(REPORTS_FOLDER, exist_ok=True)
        stored_name = f"patient{patient_id}_{uuid.uuid4().hex}{extension}"
        saved_path = os.path.join(REPORTS_FOLDER, stored_name)
        file.save(saved_path)

        # Save the details in the database
        cursor.execute("""
            INSERT INTO medical_reports
                (patient_id, report_type, file_url, report_date, description)
            VALUES (%s, %s, %s, COALESCE(%s, CURRENT_DATE), %s)
            RETURNING report_id
        """, (
            patient_id,
            report_type,
            stored_name,
            report_date if report_date else None,
            description
        ))

        report_id = cursor.fetchone()[0]

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Report uploaded successfully",
            "report_id": report_id
        }), 201

    except Exception as e:
        if conn:
            conn.rollback()

        # If the database failed, remove the file we just saved
        if saved_path and os.path.exists(saved_path):
            os.remove(saved_path)

        print("Upload Report Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to upload the report"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- List a patient's reports -----
@app.route("/api/patients/<int:patient_id>/reports", methods=["GET"])
def get_patient_reports(patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                report_id,
                report_type,
                description,
                report_date,
                file_url
            FROM medical_reports
            WHERE patient_id = %s
            ORDER BY uploaded_at DESC, report_id DESC
        """, (patient_id,))

        reports = []

        for row in cursor.fetchall():
            # The app needs to know whether the file is a PDF or a picture
            extension = os.path.splitext(row[4])[1].lower()

            reports.append({
                "report_id": row[0],
                "report_type": row[1],
                "description": row[2],
                "report_date": str(row[3]) if row[3] else None,
                "file_kind": "pdf" if extension == ".pdf" else "image"
            })

        return jsonify({
            "status": "success",
            "reports": reports
        }), 200

    except Exception as e:
        print("Get Reports Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load reports"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ----- Open a report's file (PDF or picture) -----
@app.route(
    "/api/patients/<int:patient_id>/reports/<int:report_id>/file",
    methods=["GET"]
)
def get_report_file(patient_id, report_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # The report must belong to this patient
        cursor.execute("""
            SELECT file_url
            FROM medical_reports
            WHERE report_id = %s
              AND patient_id = %s
        """, (report_id, patient_id))

        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": "error",
                "message": "Report not found"
            }), 404

        # Send the saved file back to the app
        return send_from_directory(
            os.path.abspath(REPORTS_FOLDER),
            row[0]
        )

    except Exception as e:
        print("Get Report File Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to open the report"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- Delete a report (the database row and the file) -----
@app.route(
    "/api/patients/<int:patient_id>/reports/<int:report_id>",
    methods=["DELETE"]
)
def delete_report(patient_id, report_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Delete the row, but only if it belongs to this patient.
        # RETURNING gives us the file name so we can delete the file too.
        cursor.execute("""
            DELETE FROM medical_reports
            WHERE report_id = %s
              AND patient_id = %s
            RETURNING file_url
        """, (report_id, patient_id))

        row = cursor.fetchone()

        if not row:
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "Report not found"
            }), 404

        conn.commit()

        # Remove the file from the folder (ignore it if it is already gone)
        file_path = os.path.join(REPORTS_FOLDER, row[0])

        if os.path.exists(file_path):
            os.remove(file_path)

        return jsonify({
            "status": "success",
            "message": "Report deleted"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Delete Report Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to delete the report"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# PATIENT NOTIFICATIONS
# The patient's app asks every few seconds whether the doctor
# has started the consultation.
# ============================================================

# ----- Unread "consultation started" notices (last 30 minutes) -----
@app.route("/api/patients/<int:patient_id>/notifications/pending", methods=["GET"])
def get_pending_notifications(patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Only recent notices, so old ones never pop up later
        cursor.execute("""
            SELECT
                n.notification_id,
                n.title,
                n.message,
                n.type,
                n.appointment_id
            FROM notifications n
            JOIN patients p
                ON n.user_id = p.user_id
            WHERE p.patient_id = %s
              AND n.is_read = 'N'
              AND n.type = 'ConsultationStarted'
              AND n.created_at > CURRENT_TIMESTAMP - INTERVAL '30 minutes'
            ORDER BY n.created_at DESC
        """, (patient_id,))

        notifications = []

        for row in cursor.fetchall():
            notifications.append({
                "notification_id": row[0],
                "title": row[1],
                "message": row[2],
                "type": row[3],
                "appointment_id": row[4]
            })

        return jsonify({
            "status": "success",
            "notifications": notifications
        }), 200

    except Exception as e:
        print("Get Notifications Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load notifications"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- Mark a notice as read -----
@app.route(
    "/api/patients/<int:patient_id>/notifications/<int:notification_id>/read",
    methods=["PUT"]
)
def mark_notification_read(patient_id, notification_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Only the notice's owner can mark it as read
        cursor.execute("""
            UPDATE notifications
            SET is_read = 'Y'
            WHERE notification_id = %s
              AND user_id = (
                  SELECT user_id FROM patients WHERE patient_id = %s
              )
            RETURNING notification_id
        """, (notification_id, patient_id))

        if not cursor.fetchone():
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "Notification not found"
            }), 404

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Marked as read"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Mark Notification Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to update the notification"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# SAVE A PATIENT'S PHONE TOKEN
# The app sends the phone's Firebase token after the patient
# logs in, so the server knows where to send notifications.
# ============================================================

@app.route("/api/patients/<int:patient_id>/device-token", methods=["POST"])
def save_patient_device_token(patient_id):
    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    token = (data.get("token") or "").strip()

    # The token is a long piece of text. Reject empty or silly values.
    if not token or len(token) > 4096:
        return jsonify({
            "status": "error",
            "message": "A valid token is required"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Find the user that belongs to this patient
        cursor.execute(
            "SELECT user_id FROM patients WHERE patient_id = %s",
            (patient_id,)
        )

        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        user_id = row[0]

        # Save the token. If this phone is already in the table,
        # just update its owner and time (no duplicate rows).
        cursor.execute("""
            INSERT INTO device_tokens (user_id, token)
            VALUES (%s, %s)
            ON CONFLICT (token)
            DO UPDATE SET
                user_id = EXCLUDED.user_id,
                updated_at = CURRENT_TIMESTAMP
        """, (user_id, token))

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Token saved"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Save Device Token Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to save the token"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# NOTIFICATION TEXTS
# Every notification the server sends, written in the 8 app
# languages. {doctor_name} and similar blanks are filled in
# when the notification is sent.
# If a language or a kind is missing, English is used instead.
# Each kind has: a title, the message saved in the app's list,
# and a shorter message for the push on the lock screen.
# ============================================================

NOTIFICATION_TEXTS = {
     # ---- Doctor accepts an appointment request ----
    "AppointmentAccepted": {
        "en_IN": {
            "title": "Appointment accepted",
            "message": "{doctor_name} accepted your appointment on {date} at {time}.",
            "push": "{doctor_name} accepted your appointment on {date} at {time}.",
        },
        "hi_IN": {
            "title": "अपॉइंटमेंट स्वीकार किया गया",
            "message": "{doctor_name} ने {date} को {time} बजे आपकी अपॉइंटमेंट स्वीकार कर ली है।",
            "push": "{doctor_name} ने {date} को {time} बजे आपकी अपॉइंटमेंट स्वीकार कर ली है।",
        },
        "kn_IN": {
            "title": "ಅಪಾಯಿಂಟ್‌ಮೆಂಟ್ ಸ್ವೀಕರಿಸಲಾಗಿದೆ",
            "message": "{doctor_name} ಅವರು {date} ರಂದು {time} ಕ್ಕೆ ನಿಮ್ಮ ಅಪಾಯಿಂಟ್‌ಮೆಂಟ್ ಅನ್ನು ಸ್ವೀಕರಿಸಿದ್ದಾರೆ.",
            "push": "{doctor_name} ಅವರು {date} ರಂದು {time} ಕ್ಕೆ ನಿಮ್ಮ ಅಪಾಯಿಂಟ್‌ಮೆಂಟ್ ಅನ್ನು ಸ್ವೀಕರಿಸಿದ್ದಾರೆ.",
        },
        "ta_IN": {
            "title": "சந்திப்பு ஏற்கப்பட்டது",
            "message": "{doctor_name} {date} அன்று {time} மணிக்கு உங்கள் சந்திப்பை ஏற்றுக்கொண்டார்.",
            "push": "{doctor_name} {date} அன்று {time} மணிக்கு உங்கள் சந்திப்பை ஏற்றுக்கொண்டார்.",
        },
        "te_IN": {
            "title": "అపాయింట్‌మెంట్ అంగీకరించబడింది",
            "message": "{doctor_name} {date} న {time} కి మీ అపాయింట్‌మెంట్‌ను అంగీకరించారు.",
            "push": "{doctor_name} {date} న {time} కి మీ అపాయింట్‌మెంట్‌ను అంగీకరించారు.",
        },
        "ml_IN": {
            "title": "അപ്പോയിന്റ്മെന്റ് സ്വീകരിച്ചു",
            "message": "{doctor_name} {date} ന് {time} ന് നിങ്ങളുടെ അപ്പോയിന്റ്മെന്റ് സ്വീകരിച്ചു.",
            "push": "{doctor_name} {date} ന് {time} ന് നിങ്ങളുടെ അപ്പോയിന്റ്മെന്റ് സ്വീകരിച്ചു.",
        },
        "mr_IN": {
            "title": "अपॉइंटमेंट स्वीकारली",
            "message": "{doctor_name} यांनी {date} रोजी {time} वाजता तुमची अपॉइंटमेंट स्वीकारली आहे.",
            "push": "{doctor_name} यांनी {date} रोजी {time} वाजता तुमची अपॉइंटमेंट स्वीकारली आहे.",
        },
        "bn_IN": {
            "title": "অ্যাপয়েন্টমেন্ট গৃহীত হয়েছে",
            "message": "{doctor_name} {date} তারিখে {time} টায় আপনার অ্যাপয়েন্টমেন্ট গ্রহণ করেছেন।",
            "push": "{doctor_name} {date} তারিখে {time} টায় আপনার অ্যাপয়েন্টমেন্ট গ্রহণ করেছেন।",
        },
    },

    # ---- Doctor cannot accept an appointment request ----
    "AppointmentRejected": {
        "en_IN": {
            "title": "Appointment not accepted",
            "message": "{doctor_name} could not accept your appointment on {date} at {time}. Please book another time.",
            "push": "{doctor_name} could not accept your appointment on {date} at {time}. Please book another time.",
        },
        "hi_IN": {
            "title": "अपॉइंटमेंट स्वीकार नहीं हुआ",
            "message": "{doctor_name} {date} को {time} बजे आपकी अपॉइंटमेंट स्वीकार नहीं कर सके। कृपया कोई और समय बुक करें।",
            "push": "{doctor_name} {date} को {time} बजे आपकी अपॉइंटमेंट स्वीकार नहीं कर सके। कृपया कोई और समय बुक करें।",
        },
        "kn_IN": {
            "title": "ಅಪಾಯಿಂಟ್‌ಮೆಂಟ್ ಸ್ವೀಕರಿಸಲಾಗಿಲ್ಲ",
            "message": "{doctor_name} ಅವರು {date} ರಂದು {time} ಕ್ಕೆ ನಿಮ್ಮ ಅಪಾಯಿಂಟ್‌ಮೆಂಟ್ ಅನ್ನು ಸ್ವೀಕರಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ. ದಯವಿಟ್ಟು ಬೇರೆ ಸಮಯ ಬುಕ್ ಮಾಡಿ.",
            "push": "{doctor_name} ಅವರು {date} ರಂದು {time} ಕ್ಕೆ ನಿಮ್ಮ ಅಪಾಯಿಂಟ್‌ಮೆಂಟ್ ಅನ್ನು ಸ್ವೀಕರಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ. ದಯವಿಟ್ಟು ಬೇರೆ ಸಮಯ ಬುಕ್ ಮಾಡಿ.",
        },
        "ta_IN": {
            "title": "சந்திப்பு ஏற்கப்படவில்லை",
            "message": "{doctor_name} {date} அன்று {time} மணிக்கு உங்கள் சந்திப்பை ஏற்க முடியவில்லை. தயவுசெய்து வேறு நேரத்தை முன்பதிவு செய்யவும்.",
            "push": "{doctor_name} {date} அன்று {time} மணிக்கு உங்கள் சந்திப்பை ஏற்க முடியவில்லை. தயவுசெய்து வேறு நேரத்தை முன்பதிவு செய்யவும்.",
        },
        "te_IN": {
            "title": "అపాయింట్‌మెంట్ అంగీకరించబడలేదు",
            "message": "{doctor_name} {date} న {time} కి మీ అపాయింట్‌మెంట్‌ను అంగీకరించలేకపోయారు. దయచేసి మరో సమయాన్ని బుక్ చేయండి.",
            "push": "{doctor_name} {date} న {time} కి మీ అపాయింట్‌మెంట్‌ను అంగీకరించలేకపోయారు. దయచేసి మరో సమయాన్ని బుక్ చేయండి.",
        },
        "ml_IN": {
            "title": "അപ്പോയിന്റ്മെന്റ് സ്വീകരിച്ചില്ല",
            "message": "{doctor_name} {date} ന് {time} ന് നിങ്ങളുടെ അപ്പോയിന്റ്മെന്റ് സ്വീകരിക്കാൻ കഴിഞ്ഞില്ല. ദയവായി മറ്റൊരു സമയം ബുക്ക് ചെയ്യുക.",
            "push": "{doctor_name} {date} ന് {time} ന് നിങ്ങളുടെ അപ്പോയിന്റ്മെന്റ് സ്വീകരിക്കാൻ കഴിഞ്ഞില്ല. ദയവായി മറ്റൊരു സമയം ബുക്ക് ചെയ്യുക.",
        },
        "mr_IN": {
            "title": "अपॉइंटमेंट स्वीकारली नाही",
            "message": "{doctor_name} यांना {date} रोजी {time} वाजता तुमची अपॉइंटमेंट स्वीकारता आली नाही. कृपया दुसरी वेळ बुक करा.",
            "push": "{doctor_name} यांना {date} रोजी {time} वाजता तुमची अपॉइंटमेंट स्वीकारता आली नाही. कृपया दुसरी वेळ बुक करा.",
        },
        "bn_IN": {
            "title": "অ্যাপয়েন্টমেন্ট গৃহীত হয়নি",
            "message": "{doctor_name} {date} তারিখে {time} টায় আপনার অ্যাপয়েন্টমেন্ট গ্রহণ করতে পারেননি। অনুগ্রহ করে অন্য সময় বুক করুন।",
            "push": "{doctor_name} {date} তারিখে {time} টায় আপনার অ্যাপয়েন্টমেন্ট গ্রহণ করতে পারেননি। অনুগ্রহ করে অন্য সময় বুক করুন।",
        },
    },  
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
    # Returns (title, message, push) for one notification kind.
    #   kind     - the notification type, for example "ConsultationStarted"
    #   language - the user's language code, for example "ta_IN"
    #   values   - the blanks to fill in, for example doctor_name="Dr. Rao"

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

# ============================================================
# SAVE THE LANGUAGE A PATIENT CHOSE
# The app calls this whenever the patient picks a language.
# The server uses it to write notifications in that language.
# ============================================================

# The 8 languages the app supports (anything else is rejected)
SUPPORTED_LANGUAGES = (
    "en_IN", "hi_IN", "kn_IN", "ta_IN",
    "te_IN", "ml_IN", "mr_IN", "bn_IN",
)

@app.route("/api/patients/<int:patient_id>/language", methods=["POST"])
def save_patient_language(patient_id):
    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    language = (data.get("language") or "").strip()

    # Only accept one of our 8 language codes
    if language not in SUPPORTED_LANGUAGES:
        return jsonify({
            "status": "error",
            "message": "Unsupported language"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Find the user that belongs to this patient
        cursor.execute(
            "SELECT user_id FROM patients WHERE patient_id = %s",
            (patient_id,)
        )

        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        user_id = row[0]

        # Save the language on that user ("Users" needs double quotes
        # because the table name starts with a capital letter)
        cursor.execute(
            # The table is called users (no quotes, same as the login code)
            'UPDATE users SET language = %s WHERE user_id = %s',
            (language, user_id)
        )

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Language saved"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Save Language Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to save the language"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# SEND A PUSH NOTIFICATION TO ONE USER
# Sends the message to every phone saved for that user.
# It never raises an error, so a notification problem can
# never break the feature that called it.
# ============================================================

def send_push_to_user(user_id, title, body, data=None):
    # Firebase must have started correctly (see the top of this file)
    if not firebase_ready:
        print("Push skipped: Firebase is not ready")
        return

    # Respect the person's notification settings (the Alerts screen).
    # A muted kind of notification is still saved in their list,
    # it just does not arrive as a push.
    category = NOTIFICATION_CATEGORY.get((data or {}).get("type"))

    if category and not push_is_enabled(user_id, category):
        print("Push skipped: user", user_id, "muted", category)
        return

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # All the phones this user has logged in on
        cursor.execute(
            "SELECT token FROM device_tokens WHERE user_id = %s",
            (user_id,)
        )

        tokens = [row[0] for row in cursor.fetchall()]

        if not tokens:
            print("Push skipped: no phone token saved for user", user_id)
            return

        for token in tokens:
            try:
                message = messaging.Message(
                    token=token,
                    # The text the patient sees on the lock screen
                    notification=messaging.Notification(
                        title=title,
                        body=body
                    ),
                    # Extra values the app reads when the patient taps it
                    # (values must be text)
                    data=data or {},
                    android=messaging.AndroidConfig(
                        priority="high",
                        notification=messaging.AndroidNotification(
                            channel_id="consultation_alerts",
                            sound="default"
                        )
                    )
                )

                messaging.send(message)
                print("Push sent to one phone of user", user_id)

            except Exception as send_error:
                # A token of an uninstalled app or a logged-out phone stops
                # working. Remove such tokens so we do not keep trying.
                error_name = type(send_error).__name__

                if error_name in ("UnregisteredError", "SenderIdMismatchError"):
                    cursor.execute(
                        "DELETE FROM device_tokens WHERE token = %s",
                        (token,)
                    )
                    conn.commit()
                    print("Removed an expired phone token")
                else:
                    print("Push send error:", send_error)

    except Exception as e:
        print("Push error:", e)

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()            

# ============================================================
# SAVE A DOCTOR'S PHONE TOKEN
# Same idea as the patient route: the doctor's app sends the
# phone's Firebase token so the server can send notifications.
# ============================================================

@app.route("/api/doctors/<int:doctor_id>/device-token", methods=["POST"])
def save_doctor_device_token(doctor_id):
    data = request.get_json()

    if not data:
        return jsonify({
            "status": "error",
            "message": "No data received"
        }), 400

    token = (data.get("token") or "").strip()

    # The token is a long piece of text. Reject empty or silly values.
    if not token or len(token) > 4096:
        return jsonify({
            "status": "error",
            "message": "A valid token is required"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Find the user that belongs to this doctor
        cursor.execute(
            "SELECT user_id FROM doctors WHERE doctor_id = %s",
            (doctor_id,)
        )

        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": "error",
                "message": "Doctor not found"
            }), 404

        user_id = row[0]

        # Save the token. If this phone is already in the table,
        # just update its owner and time (no duplicate rows).
        cursor.execute("""
            INSERT INTO device_tokens (user_id, token)
            VALUES (%s, %s)
            ON CONFLICT (token)
            DO UPDATE SET
                user_id = EXCLUDED.user_id,
                updated_at = CURRENT_TIMESTAMP
        """, (user_id, token))

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Token saved"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Save Doctor Device Token Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to save the token"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ============================================================
# FORGET A PHONE TOKEN (used when someone logs out)
# So a logged-out phone no longer receives that person's alerts.
# ============================================================

@app.route("/api/device-token", methods=["DELETE"])
def delete_device_token():
    data = request.get_json(silent=True) or {}
    token = (data.get("token") or "").strip()

    if not token:
        return jsonify({
            "status": "error",
            "message": "A token is required"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute(
            "DELETE FROM device_tokens WHERE token = %s",
            (token,)
        )

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Token removed"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Delete Device Token Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to remove the token"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# DOCTOR ACCEPTS OR REJECTS A BOOKING
# Only an appointment that is "Pending" can be answered.
# Accept -> "Scheduled", Reject -> "Rejected".
# The patient gets a notice and a push notification.
# ============================================================

@app.route(
    "/api/doctors/<int:doctor_id>/appointments/<int:appointment_id>/respond",
    methods=["PUT"]
)
def respond_to_appointment(doctor_id, appointment_id):
    data = request.get_json(silent=True) or {}
    decision = data.get("decision")

    # The answer must be "accept" or "reject"
    if decision not in ("accept", "reject"):
        return jsonify({
            "status": "error",
            "message": "decision must be accept or reject"
        }), 400

    new_status = "Scheduled" if decision == "accept" else "Rejected"

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Change the status, but only for this doctor's Pending appointment
        cursor.execute("""
            UPDATE appointments
            SET status = %s
            WHERE appointment_id = %s
              AND doctor_id = %s
              AND status = 'Pending'
            RETURNING appointment_id
        """, (new_status, appointment_id, doctor_id))

        if not cursor.fetchone():
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "Appointment not found or is not waiting for a decision"
            }), 404

        conn.commit()

        # ----- Tell the patient. A problem here must never undo or
        # block the doctor's answer, so it has its own try/except. -----
        try:
            cursor.execute("""
                SELECT p.user_id, du.full_name, a.appointment_date, a.start_time
                FROM appointments a
                JOIN patients p
                    ON a.patient_id = p.patient_id
                JOIN doctors d
                    ON a.doctor_id = d.doctor_id
                JOIN users du
                    ON d.user_id = du.user_id
                WHERE a.appointment_id = %s
            """, (appointment_id,))

            info = cursor.fetchone()

            if info:
                patient_user_id = info[0]
                doctor_name = info[1]
                when = f"{info[2]} at {str(info[3])[:5]}"

                if decision == "accept":
                    title = "Appointment accepted"
                    message = f"{doctor_name} accepted your appointment on {when}."
                    notice_type = "AppointmentAccepted"
                else:
                    title = "Appointment not accepted"
                    message = (
                        f"{doctor_name} could not accept your appointment on "
                        f"{when}. Please book another time."
                    )
                    notice_type = "AppointmentRejected"

                # Save the notice (for the Alerts list in the profile)
                cursor.execute("""
                    INSERT INTO notifications
                        (user_id, title, message, type, appointment_id)
                    VALUES (%s, %s, %s, %s, %s)
                """, (
                    patient_user_id, title, message, notice_type, appointment_id
                ))

                conn.commit()

                # Send the push notification to the patient's phone(s)
                send_push_to_user(
                    patient_user_id,
                    title,
                    message,
                    {
                        "type": notice_type,
                        "appointment_id": str(appointment_id)
                    }
                )

        except Exception as notice_error:
            conn.rollback()
            print("Appointment answer notice error:", notice_error)

        return jsonify({
            "status": "success",
            "message": "Appointment accepted" if decision == "accept"
                       else "Appointment rejected",
            "new_status": new_status
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Respond To Appointment Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to answer the appointment"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()
# ============================================================
# APPOINTMENT REMINDERS
# A small timer inside the server checks every minute for
# appointments that start within the next 10 minutes. The doctor
# and the patient each get one push notification per appointment.
# It only works while the server is running.
# ============================================================

# How many minutes before the start the reminder is sent
REMINDER_MINUTES = 10


def send_due_reminders():
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Scheduled appointments that start within the next few minutes.
        # (appointment_date + start_time) is the exact start date and time.
        cursor.execute("""
            SELECT
                a.appointment_id,
                a.start_time,
                pu.user_id,
                pu.full_name,
                du.user_id,
                du.full_name
            FROM appointments a
            JOIN patients p
                ON a.patient_id = p.patient_id
            JOIN users pu
                ON p.user_id = pu.user_id
            JOIN doctors d
                ON a.doctor_id = d.doctor_id
            JOIN users du
                ON d.user_id = du.user_id
            WHERE a.status = 'Scheduled'
              AND (a.appointment_date + a.start_time) > CURRENT_TIMESTAMP
              AND (a.appointment_date + a.start_time)
                    <= CURRENT_TIMESTAMP + (%s * INTERVAL '1 minute')
        """, (REMINDER_MINUTES,))

        rows = cursor.fetchall()

        for row in rows:
            appointment_id = row[0]
            start = str(row[1])[:5]  # For example 11:30
            patient_user_id, patient_name = row[2], row[3]
            doctor_user_id, doctor_name = row[4], row[5]

            # Each person gets their own message
            recipients = [
                (
                    doctor_user_id,
                    f"Consultation with {patient_name} starts at {start}.",
                ),
                (
                    patient_user_id,
                    f"Your appointment with {doctor_name} starts at {start}.",
                ),
            ]

            for user_id, message in recipients:
                # Skip if this person was already reminded about this
                # appointment (the notifications table remembers it)
                cursor.execute("""
                    SELECT 1
                    FROM notifications
                    WHERE user_id = %s
                      AND appointment_id = %s
                      AND type = 'AppointmentReminder'
                    LIMIT 1
                """, (user_id, appointment_id))

                if cursor.fetchone():
                    continue

                # Save the notice first, so it can never be sent twice
                cursor.execute("""
                    INSERT INTO notifications
                        (user_id, title, message, type, appointment_id)
                    VALUES (%s, %s, %s, 'AppointmentReminder', %s)
                """, (
                    user_id,
                    "Appointment starting soon",
                    message,
                    appointment_id
                ))

                conn.commit()

                # Then send the push notification
                send_push_to_user(
                    user_id,
                    "Appointment starting soon",
                    message,
                    {
                        "type": "AppointmentReminder",
                        "appointment_id": str(appointment_id)
                    }
                )

    except Exception as e:
        if conn:
            conn.rollback()

        print("Reminder check error:", e)

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# Follow-up reminders are sent from this hour of the day on
# (9 means 9:00 AM)
FOLLOWUP_FROM_HOUR = 9


# Tells each patient whose follow-up date is TOMORROW. Every patient
# gets it once, because the notifications table remembers it.
def send_followup_reminders():
    # Too early in the day: wait until the set hour
    if dt.datetime.now().hour < FOLLOWUP_FROM_HOUR:
        return

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                c.appointment_id,
                c.follow_up_date,
                pu.user_id,
                du.full_name
            FROM consultations c
            JOIN appointments a
                ON c.appointment_id = a.appointment_id
            JOIN patients p
                ON a.patient_id = p.patient_id
            JOIN users pu
                ON p.user_id = pu.user_id
            JOIN doctors d
                ON a.doctor_id = d.doctor_id
            JOIN users du
                ON d.user_id = du.user_id
            WHERE c.follow_up_date = CURRENT_DATE + 1
        """)

        for row in cursor.fetchall():
            appointment_id, follow_date, user_id, doctor_name = row

            # Skip if this patient was already reminded about it
            cursor.execute("""
                SELECT 1
                FROM notifications
                WHERE user_id = %s
                  AND appointment_id = %s
                  AND type = 'FollowUpReminder'
                LIMIT 1
            """, (user_id, appointment_id))

            if cursor.fetchone():
                continue

            title = "Follow-up due tomorrow"
            message = (
                f"Your follow-up with {doctor_name} is due tomorrow "
                f"({follow_date}). Please book an appointment."
            )

            # Save the notice first, so it can never be sent twice
            cursor.execute("""
                INSERT INTO notifications
                    (user_id, title, message, type, appointment_id)
                VALUES (%s, %s, %s, 'FollowUpReminder', %s)
            """, (user_id, title, message, appointment_id))

            conn.commit()

            # Then send the push notification
            send_push_to_user(
                user_id,
                title,
                message,
                {
                    "type": "FollowUpReminder",
                    "appointment_id": str(appointment_id)
                }
            )

    except Exception as e:
        if conn:
            conn.rollback()

        print("Follow-up reminder error:", e)

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ------------------------------------------------------------
# "TIME TO START" ALERT FOR THE DOCTOR
# Checked every minute. When an accepted appointment's start time
# has just arrived, the doctor gets one push notification.
# It is only sent within a few minutes after the start time, so
# old appointments do not trigger alerts after the server restarts.
# ------------------------------------------------------------
START_ALERT_WINDOW_MINUTES = 5


def send_start_time_alerts():
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Accepted appointments that started within the last few minutes
        cursor.execute("""
            SELECT
                a.appointment_id,
                a.start_time,
                pu.full_name,
                du.user_id
            FROM appointments a
            JOIN patients p
                ON a.patient_id = p.patient_id
            JOIN users pu
                ON p.user_id = pu.user_id
            JOIN doctors d
                ON a.doctor_id = d.doctor_id
            JOIN users du
                ON d.user_id = du.user_id
            WHERE a.status = 'Scheduled'
              AND (a.appointment_date + a.start_time) <= CURRENT_TIMESTAMP
              AND (a.appointment_date + a.start_time)
                    > CURRENT_TIMESTAMP - (%s * INTERVAL '1 minute')
        """, (START_ALERT_WINDOW_MINUTES,))
        # TEMPORARY: shows in the terminal every minute that this check runs
        print("Start-time check ran. Matching appointments:", cursor.rowcount)
        for row in cursor.fetchall():
            appointment_id, start_time, patient_name, doctor_user_id = row

            title = "Time to start the consultation"
            message = (
                f"It is time for your consultation with {patient_name} "
                f"({str(start_time)[:5]}). Open Consultations to start."
            )

            # Skip if the doctor already got this alert for this appointment
            cursor.execute("""
                SELECT 1
                FROM notifications
                WHERE user_id = %s
                  AND appointment_id = %s
                  AND type = 'AppointmentReminder'
                  AND title = %s
                LIMIT 1
            """, (doctor_user_id, appointment_id, title))

            if cursor.fetchone():
                continue

            # Save the notice first, so it can never be sent twice
            cursor.execute("""
                INSERT INTO notifications
                    (user_id, title, message, type, appointment_id)
                VALUES (%s, %s, %s, 'AppointmentReminder', %s)
            """, (doctor_user_id, title, message, appointment_id))

            conn.commit()

            # Then send the push notification to the doctor's phone(s)
            send_push_to_user(
                doctor_user_id,
                title,
                message,
                {
                    "type": "AppointmentReminder",
                    "appointment_id": str(appointment_id)
                }
            )

    except Exception as e:
        if conn:
            conn.rollback()

        print("Start time alert error:", e)

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# Runs forever in the background: check, sleep one minute, repeat
def reminder_loop():
    while True:
        try:
            send_due_reminders()
        except Exception as e:
            print("Reminder loop error:", e)

        try:
            send_followup_reminders()
        except Exception as e:
            print("Follow-up loop error:", e)

        try:
            send_start_time_alerts()
        except Exception as e:
            print("Start time alert error:", e)

        time.sleep(60)


# Starts the background timer (called once when the server starts)
def start_reminder_thread():
    thread = threading.Thread(target=reminder_loop, daemon=True)
    thread.start()
    print("Reminder timer started")

# ============================================================
# DOCTOR SCHEDULE AND FREE SLOTS
# The doctor saves working days, hours and days off. The patient's
# booking screen asks for the free slots of a doctor on a date.
# ============================================================

# Used when a doctor has not saved a schedule yet.
# These are the same fixed slots the app showed before.
DEFAULT_SLOT_STARTS = [
    dt.time(9, 0), dt.time(9, 30), dt.time(10, 0),
    dt.time(10, 30), dt.time(11, 0), dt.time(11, 30),
    dt.time(13, 0), dt.time(13, 30), dt.time(14, 0),
    dt.time(14, 30), dt.time(15, 0), dt.time(15, 30),
    dt.time(17, 0), dt.time(17, 30), dt.time(18, 0), dt.time(18, 30),
]

DEFAULT_SLOT_MINUTES = 30


# Turns a time into the text the app uses, for example "09:30 AM"
def slot_label(t):
    return t.strftime("%I:%M %p")


# Cuts the working hours into slots. Only slots that END before the
# working hours end are kept.
def make_slot_starts(start, end, minutes):
    slots = []
    today = dt.date.today()
    current = dt.datetime.combine(today, start)
    limit = dt.datetime.combine(today, end)
    step = dt.timedelta(minutes=minutes)

    while current + step <= limit:
        slots.append(current.time())
        current += step

    return slots


# ----- Read a doctor's saved schedule -----
@app.route("/api/doctors/<int:doctor_id>/schedule", methods=["GET"])
def get_doctor_schedule(doctor_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT working_days, start_time, end_time, slot_minutes
            FROM doctor_schedules
            WHERE doctor_id = %s
        """, (doctor_id,))

        row = cursor.fetchone()

        # Is the doctor switched on as available for consultations?
        cursor.execute(
            "SELECT is_available FROM doctors WHERE doctor_id = %s",
            (doctor_id,)
        )
        availability_row = cursor.fetchone()
        is_available = (availability_row[0] == 'Y') if availability_row else True

        # No schedule saved yet
        if not row:
            return jsonify({
                "status": "success",
                "schedule": None,
                "is_available": is_available
            }), 200

        # Only days off that are today or later are interesting
        cursor.execute("""
            SELECT off_date
            FROM doctor_days_off
            WHERE doctor_id = %s
              AND off_date >= CURRENT_DATE
            ORDER BY off_date
        """, (doctor_id,))

        days_off = [str(r[0]) for r in cursor.fetchall()]

        return jsonify({
            "status": "success",
            "schedule": {
                "working_days": list(row[0]),
                "start_time": row[1].strftime("%H:%M"),
                "end_time": row[2].strftime("%H:%M"),
                "slot_minutes": row[3],
                "days_off": days_off
            },
            "is_available": is_available
        }), 200

    except Exception as e:
        print("Get Schedule Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the schedule"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- Save a doctor's schedule -----
@app.route("/api/doctors/<int:doctor_id>/schedule", methods=["PUT"])
def save_doctor_schedule(doctor_id):
    data = request.get_json(silent=True) or {}

    # --- Check what the app sent ---
    working_days = data.get("working_days")

    if (
        not isinstance(working_days, list)
        or not working_days
        or any(
            (not isinstance(d, int)) or d < 1 or d > 7
            for d in working_days
        )
    ):
        return jsonify({
            "status": "error",
            "message": "Please choose at least one working day"
        }), 400

    try:
        start = dt.datetime.strptime(data.get("start_time", ""), "%H:%M").time()
        end = dt.datetime.strptime(data.get("end_time", ""), "%H:%M").time()
    except ValueError:
        return jsonify({
            "status": "error",
            "message": "Please send the times like 09:00"
        }), 400

    if end <= start:
        return jsonify({
            "status": "error",
            "message": "The end time must be after the start time"
        }), 400

    slot_minutes = data.get("slot_minutes")

    if (
        not isinstance(slot_minutes, int)
        or slot_minutes < 10
        or slot_minutes > 120
    ):
        return jsonify({
            "status": "error",
            "message": "The slot length must be between 10 and 120 minutes"
        }), 400

    days_off_input = data.get("days_off") or []

    if not isinstance(days_off_input, list) or len(days_off_input) > 366:
        return jsonify({
            "status": "error",
            "message": "Days off must be a list of dates"
        }), 400

    days_off = []

    try:
        for text in days_off_input:
            days_off.append(dt.date.fromisoformat(text))
    except (ValueError, TypeError):
        return jsonify({
            "status": "error",
            "message": "Please send the days off like 2026-12-25"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute(
            "SELECT doctor_id FROM doctors WHERE doctor_id = %s",
            (doctor_id,)
        )

        if not cursor.fetchone():
            return jsonify({
                "status": "error",
                "message": "Doctor not found"
            }), 404

        # Save the schedule (create it, or replace the old one)
        cursor.execute("""
            INSERT INTO doctor_schedules
                (doctor_id, working_days, start_time, end_time, slot_minutes)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (doctor_id)
            DO UPDATE SET
                working_days = EXCLUDED.working_days,
                start_time = EXCLUDED.start_time,
                end_time = EXCLUDED.end_time,
                slot_minutes = EXCLUDED.slot_minutes,
                updated_at = CURRENT_TIMESTAMP
        """, (doctor_id, working_days, start, end, slot_minutes))

        # Replace the days off with the new list
        cursor.execute(
            "DELETE FROM doctor_days_off WHERE doctor_id = %s",
            (doctor_id,)
        )

        for day in set(days_off):
            cursor.execute("""
                INSERT INTO doctor_days_off (doctor_id, off_date)
                VALUES (%s, %s)
            """, (doctor_id, day))

        # The "available for consultations" switch. When it is off,
        # patients cannot see or book this doctor.
        cursor.execute("""
            UPDATE doctors
            SET is_available = %s
            WHERE doctor_id = %s
        """, (
            'N' if data.get("is_available") is False else 'Y',
            doctor_id
        ))

        # Everything above is saved together, or not at all   
        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Schedule saved"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Save Schedule Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to save the schedule"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- The free slots of a doctor on one date -----
@app.route("/api/doctors/<int:doctor_id>/slots", methods=["GET"])
def get_free_slots(doctor_id):
    # The date comes like ?date=2026-10-26
    try:
        day = dt.date.fromisoformat(request.args.get("date", ""))
    except ValueError:
        return jsonify({
            "status": "error",
            "message": "Please send the date like 2026-10-26"
        }), 400

    # A date that has already passed has no slots
    if day < dt.date.today():
        return jsonify({
            "status": "success",
            "slots": [],
            "message": "This date has already passed."
        }), 200

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # 1. The doctor's schedule (or the default slots)
        cursor.execute("""
            SELECT working_days, start_time, end_time, slot_minutes
            FROM doctor_schedules
            WHERE doctor_id = %s
        """, (doctor_id,))

        schedule = cursor.fetchone()

        if schedule:
            working_days, start, end, minutes = schedule

            # isoweekday(): Monday = 1 ... Sunday = 7
            if day.isoweekday() not in working_days:
                return jsonify({
                    "status": "success",
                    "slots": [],
                    "message": "The doctor does not work on this day."
                }), 200

            starts = make_slot_starts(start, end, minutes)
        else:
            minutes = DEFAULT_SLOT_MINUTES
            starts = DEFAULT_SLOT_STARTS

        # 2. Is it one of the doctor's days off?
        cursor.execute("""
            SELECT 1
            FROM doctor_days_off
            WHERE doctor_id = %s
              AND off_date = %s
        """, (doctor_id, day))

        if cursor.fetchone():
            return jsonify({
                "status": "success",
                "slots": [],
                "message": "The doctor is not available on this date."
            }), 200

        # 3. Times that are already booked (Pending or Scheduled)
        cursor.execute("""
            SELECT
                start_time,
                COALESCE(end_time, start_time + INTERVAL '30 minutes')
            FROM appointments
            WHERE doctor_id = %s
              AND appointment_date = %s
              AND status IN ('Pending', 'Scheduled')
        """, (doctor_id, day))

        booked = cursor.fetchall()

        # 4. Keep only the free slots that are still in the future
        now = dt.datetime.now()
        free = []

        for s in starts:
            slot_start = dt.datetime.combine(day, s)
            slot_end = (slot_start + dt.timedelta(minutes=minutes)).time()

            # Today: hide slots that have already started
            if slot_start <= now:
                continue

            # Hide the slot if it overlaps an existing booking
            taken = any(
                s < b_end and slot_end > b_start
                for b_start, b_end in booked
            )

            if not taken:
                free.append(slot_label(s))

        return jsonify({
            "status": "success",
            "slots": free,
            "message": "" if free else "No free slots on this date."
        }), 200

    except Exception as e:
        print("Get Free Slots Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the slots"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# CHANGE THE STATUS OF A MEDICINE ORDER
# Used by the pharmacy or admin (a screen for it comes later).
# It needs the secret ADMIN_KEY from the .env file in the
# "X-Admin-Key" header. The patient gets a notice and a push.
# ============================================================

ORDER_STATUS_MESSAGES = {
    "Confirmed": "has been confirmed by the pharmacy.",
    "Dispatched": "is on its way to you.",
    "Delivered": "has been delivered. Take the medicines as prescribed.",
    "Cancelled": "was cancelled.",
}


@app.route("/api/medicine-orders/<int:order_id>/status", methods=["PUT"])
def update_order_status(order_id):
    # --- Only someone who knows the secret key may use this route ---
    admin_key = os.getenv("ADMIN_KEY")

    if not admin_key:
        return jsonify({
            "status": "error",
            "message": "ADMIN_KEY is not set on the server"
        }), 503

    if request.headers.get("X-Admin-Key") != admin_key:
        return jsonify({
            "status": "error",
            "message": "Not allowed"
        }), 403

    data = request.get_json(silent=True) or {}
    new_status = data.get("status")

    if new_status not in ORDER_STATUS_MESSAGES:
        return jsonify({
            "status": "error",
            "message": "Status must be Confirmed, Dispatched, Delivered or Cancelled"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # The order must exist, and must not be finished already
        cursor.execute("""
            SELECT o.status, p.user_id
            FROM medicine_orders o
            JOIN patients p
                ON o.patient_id = p.patient_id
            WHERE o.order_id = %s
        """, (order_id,))

        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": "error",
                "message": "Order not found"
            }), 404

        current_status, patient_user_id = row

        if current_status in ("Delivered", "Cancelled"):
            return jsonify({
                "status": "error",
                "message": f"This order is already {current_status}"
            }), 400

        cursor.execute("""
            UPDATE medicine_orders
            SET status = %s
            WHERE order_id = %s
        """, (new_status, order_id))

        conn.commit()

        # ----- Tell the patient. A problem here must never undo the
        # status change, so it has its own try/except. -----
        try:
            title = f"Order {new_status}"
            message = f"Your order #{order_id} {ORDER_STATUS_MESSAGES[new_status]}"

            # Save the notice (for the Alerts list)
            cursor.execute("""
                INSERT INTO notifications
                    (user_id, title, message, type)
                VALUES (%s, %s, %s, 'OrderStatus')
            """, (patient_user_id, title, message))

            conn.commit()

            # Send the push notification to the patient's phone(s)
            send_push_to_user(
                patient_user_id,
                title,
                message,
                {
                    "type": "OrderStatus",
                    "order_id": str(order_id)
                }
            )

        except Exception as notice_error:
            conn.rollback()
            print("Order notice error:", notice_error)

        return jsonify({
            "status": "success",
            "message": "Order status updated",
            "new_status": new_status
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Update Order Status Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to update the order"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# NOTIFICATION LIST AND SETTINGS (the Alerts screen)
# ============================================================

# Which kind of setting each notification belongs to
NOTIFICATION_CATEGORY = {
    "AppointmentRequest": "appointments",
    "AppointmentAccepted": "appointments",
    "AppointmentRejected": "appointments",
    "AppointmentCancelled": "appointments",
    "ConsultationStarted": "appointments",
    "AppointmentReminder": "reminders",
    "FollowUpReminder": "reminders",
    "PrescriptionIssued": "prescriptions",
    "OrderStatus": "orders",
}

# The four switches shown on the Alerts screen
ALL_CATEGORIES = ["appointments", "reminders", "prescriptions", "orders"]


# True if the person has not muted this kind of notification
def push_is_enabled(user_id, category):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT enabled
            FROM notification_preferences
            WHERE user_id = %s
              AND category = %s
        """, (user_id, category))

        row = cursor.fetchone()

        # No row means nothing was ever changed: everything is on
        return True if not row else row[0] == 'Y'

    except Exception as e:
        # If the settings cannot be read, send the push anyway
        print("Notification settings error:", e)
        return True

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- The patient's notifications, newest first -----
@app.route("/api/patients/<int:patient_id>/notifications", methods=["GET"])
def get_patient_notifications(patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                n.notification_id,
                n.title,
                n.message,
                n.type,
                n.appointment_id,
                n.is_read,
                n.created_at
            FROM notifications n
            JOIN patients p
                ON n.user_id = p.user_id
            WHERE p.patient_id = %s
            ORDER BY n.created_at DESC, n.notification_id DESC
            LIMIT 50
        """, (patient_id,))

        notifications = []

        for row in cursor.fetchall():
            notifications.append({
                "notification_id": row[0],
                "title": row[1],
                "message": row[2],
                "type": row[3],
                "appointment_id": row[4],
                "is_read": row[5] == 'Y',
                # For example "2026-10-26 17:22"
                "created_at": str(row[6])[:16]
            })

        return jsonify({
            "status": "success",
            "notifications": notifications
        }), 200

    except Exception as e:
        print("Get Notifications List Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load notifications"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- Mark all of the patient's notifications as read -----
@app.route("/api/patients/<int:patient_id>/notifications/read-all", methods=["PUT"])
def mark_all_notifications_read(patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            UPDATE notifications
            SET is_read = 'Y'
            WHERE is_read = 'N'
              AND user_id = (
                  SELECT user_id FROM patients WHERE patient_id = %s
              )
        """, (patient_id,))

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "All marked as read"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Mark All Read Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to update the notifications"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- Read the patient's four switches -----
@app.route("/api/patients/<int:patient_id>/notification-settings", methods=["GET"])
def get_notification_settings(patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT np.category, np.enabled
            FROM notification_preferences np
            JOIN patients p
                ON np.user_id = p.user_id
            WHERE p.patient_id = %s
        """, (patient_id,))

        saved = {row[0]: row[1] == 'Y' for row in cursor.fetchall()}

        # Anything not saved yet is on
        settings = {c: saved.get(c, True) for c in ALL_CATEGORIES}

        return jsonify({
            "status": "success",
            "settings": settings
        }), 200

    except Exception as e:
        print("Get Notification Settings Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the settings"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- Save one or more of the patient's switches -----
@app.route("/api/patients/<int:patient_id>/notification-settings", methods=["PUT"])
def save_notification_settings(patient_id):
    data = request.get_json(silent=True) or {}

    # Only the four known switches are accepted
    changes = {
        key: value for key, value in data.items()
        if key in ALL_CATEGORIES and isinstance(value, bool)
    }

    if not changes:
        return jsonify({
            "status": "error",
            "message": "No valid settings received"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute(
            "SELECT user_id FROM patients WHERE patient_id = %s",
            (patient_id,)
        )

        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": "error",
                "message": "Patient not found"
            }), 404

        user_id = row[0]

        for category, enabled in changes.items():
            cursor.execute("""
                INSERT INTO notification_preferences
                    (user_id, category, enabled)
                VALUES (%s, %s, %s)
                ON CONFLICT (user_id, category)
                DO UPDATE SET
                    enabled = EXCLUDED.enabled,
                    updated_at = CURRENT_TIMESTAMP
            """, (user_id, category, 'Y' if enabled else 'N'))

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "Settings saved"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Save Notification Settings Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to save the settings"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# DOCTOR CANCELS A SCHEDULED APPOINTMENT
# Only the doctor's own Scheduled appointments can be cancelled.
# The patient gets a notice and a push notification.
# ============================================================

@app.route(
    "/api/doctors/<int:doctor_id>/appointments/<int:appointment_id>/cancel",
    methods=["PUT"]
)
def doctor_cancel_appointment(doctor_id, appointment_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Change the status, but only for this doctor's Scheduled appointment
        cursor.execute("""
            UPDATE appointments
            SET status = 'Cancelled'
            WHERE appointment_id = %s
              AND doctor_id = %s
              AND status = 'Scheduled'
            RETURNING appointment_id
        """, (appointment_id, doctor_id))

        if not cursor.fetchone():
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "Appointment not found or cannot be cancelled"
            }), 404

        conn.commit()

        # ----- Tell the patient. A problem here must never undo the
        # cancellation, so it has its own try/except. -----
        try:
            cursor.execute("""
                SELECT p.user_id, du.full_name,
                       a.appointment_date, a.start_time
                FROM appointments a
                JOIN patients p
                    ON a.patient_id = p.patient_id
                JOIN doctors d
                    ON a.doctor_id = d.doctor_id
                JOIN users du
                    ON d.user_id = du.user_id
                WHERE a.appointment_id = %s
            """, (appointment_id,))

            info = cursor.fetchone()

            if info:
                patient_user_id = info[0]
                doctor_name = info[1]
                when = f"{info[2]} at {str(info[3])[:5]}"

                title = "Appointment cancelled by the doctor"
                message = (
                    f"{doctor_name} cancelled your appointment on {when}. "
                    "Please book another time."
                )

                # Save the notice (for the Alerts list)
                cursor.execute("""
                    INSERT INTO notifications
                        (user_id, title, message, type, appointment_id)
                    VALUES (%s, %s, %s, 'AppointmentCancelled', %s)
                """, (patient_user_id, title, message, appointment_id))

                conn.commit()

                # Send the push notification to the patient's phone(s)
                send_push_to_user(
                    patient_user_id,
                    title,
                    message,
                    {
                        "type": "AppointmentCancelled",
                        "appointment_id": str(appointment_id)
                    }
                )

        except Exception as notice_error:
            conn.rollback()
            print("Doctor cancel notice error:", notice_error)

        return jsonify({
            "status": "success",
            "message": "Appointment cancelled"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Doctor Cancel Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to cancel the appointment"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# DOCTOR VIEWS A PATIENT'S REPORTS (read only)
# Only for patients the doctor has actually accepted.
# ============================================================

# True if this doctor has an accepted appointment with this patient.
# Pending, Rejected and Cancelled bookings do not count.
def doctor_has_access(cursor, doctor_id, patient_id):
    cursor.execute("""
        SELECT 1
        FROM appointments
        WHERE doctor_id = %s
          AND patient_id = %s
          AND status IN ('Scheduled', 'Completed', 'Rescheduled')
        LIMIT 1
    """, (doctor_id, patient_id))

    return cursor.fetchone() is not None


# ----- The list of a patient's reports -----
@app.route(
    "/api/doctors/<int:doctor_id>/patients/<int:patient_id>/reports",
    methods=["GET"]
)
def doctor_get_patient_reports(doctor_id, patient_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        if not doctor_has_access(cursor, doctor_id, patient_id):
            return jsonify({
                "status": "error",
                "message": "You do not have access to this patient's reports"
            }), 403

        cursor.execute("""
            SELECT
                report_id,
                report_type,
                description,
                report_date,
                file_url
            FROM medical_reports
            WHERE patient_id = %s
            ORDER BY uploaded_at DESC, report_id DESC
        """, (patient_id,))

        reports = []

        for row in cursor.fetchall():
            # The app needs to know whether the file is a PDF or a picture
            extension = os.path.splitext(row[4])[1].lower()

            reports.append({
                "report_id": row[0],
                "report_type": row[1],
                "description": row[2],
                "report_date": str(row[3]) if row[3] else None,
                "file_kind": "pdf" if extension == ".pdf" else "image"
            })

        return jsonify({
            "status": "success",
            "reports": reports
        }), 200

    except Exception as e:
        print("Doctor Get Reports Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load reports"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- Open one report's file (PDF or picture) -----
@app.route(
    "/api/doctors/<int:doctor_id>/patients/<int:patient_id>/reports/<int:report_id>/file",
    methods=["GET"]
)
def doctor_get_report_file(doctor_id, patient_id, report_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        if not doctor_has_access(cursor, doctor_id, patient_id):
            return jsonify({
                "status": "error",
                "message": "You do not have access to this patient's reports"
            }), 403

        # The report must belong to this patient
        cursor.execute("""
            SELECT file_url
            FROM medical_reports
            WHERE report_id = %s
              AND patient_id = %s
        """, (report_id, patient_id))

        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": "error",
                "message": "Report not found"
            }), 404

        # Send the saved file back to the app
        return send_from_directory(
            os.path.abspath(REPORTS_FOLDER),
            row[0]
        )

    except Exception as e:
        print("Doctor Get Report File Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to open the report"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# PHARMACY: LIST OF ALL MEDICINE ORDERS
# Protected by the secret ADMIN_KEY from the .env file, sent in
# the "X-Admin-Key" header. (The status route is further above.)
# ============================================================

# True if the request carries the correct ADMIN_KEY
def is_admin_request():
    import hmac

    admin_key = os.getenv("ADMIN_KEY") or ""
    sent_key = request.headers.get("X-Admin-Key") or ""

    # compare_digest compares in a way that cannot be timed
    return bool(admin_key) and hmac.compare_digest(admin_key, sent_key)


@app.route("/api/pharmacy/orders", methods=["GET"])
def pharmacy_list_orders():
    if not is_admin_request():
        return jsonify({
            "status": "error",
            "message": "Not allowed"
        }), 403

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # The newest 100 orders, with the patient's name and phone.
        # One row comes back per medicine, so we group them below.
        cursor.execute("""
            SELECT
                o.order_id,
                o.order_date,
                o.status,
                o.total_amount,
                o.payment_method,
                o.delivery_address,
                u.full_name,
                u.phone,
                mc.medicine_name,
                oi.quantity
            FROM (
                SELECT *
                FROM medicine_orders
                ORDER BY order_date DESC, order_id DESC
                LIMIT 100
            ) o
            JOIN patients p
                ON o.patient_id = p.patient_id
            JOIN users u
                ON p.user_id = u.user_id
            LEFT JOIN medicine_order_items oi
                ON oi.order_id = o.order_id
            LEFT JOIN medicine_catalog mc
                ON oi.medicine_id = mc.medicine_id
            ORDER BY o.order_date DESC, o.order_id DESC, oi.id ASC
        """)

        orders = {}

        for row in cursor.fetchall():
            order_id = row[0]

            if order_id not in orders:
                orders[order_id] = {
                    "order_id": order_id,
                    "order_date": str(row[1])[:16],
                    "status": row[2],
                    "total_amount": float(row[3]),
                    "payment_method": row[4],
                    "delivery_address": row[5],
                    "patient_name": row[6],
                    "patient_phone": row[7],
                    "items": []
                }

            if row[8] is not None:
                orders[order_id]["items"].append({
                    "medicine": row[8],
                    "quantity": row[9]
                })

        return jsonify({
            "status": "success",
            "orders": list(orders.values())
        }), 200

    except Exception as e:
        print("Pharmacy List Orders Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the orders"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# PHARMACY WEB PAGE
# Open  http://<server address>:5000/pharmacy  in any browser.
# The page itself holds no data. It asks for the pharmacy key,
# and every request it makes to the server carries that key.
# ============================================================

PHARMACY_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pharmacy - Rural Telemedicine</title>
<style>
  body { font-family: Arial, Helvetica, sans-serif; margin: 0;
         background: #f7fafc; color: #26384a; }
  header { background: #3f6fa8; color: #fff; padding: 16px 20px;
           display: flex; align-items: center; justify-content: space-between; }
  h1 { font-size: 20px; margin: 0; }
  main { max-width: 900px; margin: 0 auto; padding: 20px; }
  .card { background: #fff; border: 1px solid #dce5ee; border-radius: 14px;
          padding: 16px; margin-bottom: 14px; }
  .row { display: flex; justify-content: space-between; align-items: center;
         flex-wrap: wrap; gap: 8px; }
  .muted { color: #6b7c8c; font-size: 13px; }
  .badge { padding: 3px 12px; border-radius: 20px; font-size: 12px;
           font-weight: bold; color: #fff; }
  .Placed { background: #3f6fa8; } .Confirmed { background: #5c6bc0; }
  .Dispatched { background: #ef8f1a; } .Delivered { background: #2e9e5b; }
  .Cancelled { background: #d64545; }
  button { border: 0; border-radius: 10px; padding: 10px 16px; font-size: 14px;
           font-weight: bold; cursor: pointer; background: #3f6fa8; color: #fff; }
  button.light { background: #fff; color: #3f6fa8; border: 1px solid #3f6fa8; }
  button.danger { background: #fff; color: #d64545; border: 1px solid #d64545; }
  input, select { padding: 10px; border-radius: 10px; border: 1px solid #c4d1de;
                  font-size: 15px; }
  ul { margin: 8px 0; padding-left: 20px; }
  #message { padding: 10px 14px; border-radius: 10px; margin-bottom: 14px;
             display: none; }
  #message.ok { background: #e6f6ec; color: #1f7a45; display: block; }
  #message.bad { background: #fde8e8; color: #b93030; display: block; }
</style>
</head>
<body>
<header>
  <h1>Pharmacy orders</h1>
  <button class="light" id="logoutButton" style="display:none">Log out</button>
</header>
<main>
  <div id="message"></div>

  <div id="loginBox" class="card">
    <p>Enter the pharmacy key to see the orders.</p>
    <input id="keyInput" type="password" placeholder="Pharmacy key" autocomplete="off">
    <button id="loginButton">Open</button>
  </div>

  <div id="ordersBox" style="display:none">
    <div class="row" style="margin-bottom:14px">
      <div>
        <label for="filter">Show: </label>
        <select id="filter">
          <option value="">All orders</option>
          <option value="Placed">New (Placed)</option>
          <option value="Confirmed">Confirmed</option>
          <option value="Dispatched">Dispatched</option>
          <option value="Delivered">Delivered</option>
          <option value="Cancelled">Cancelled</option>
        </select>
      </div>
      <div class="muted" id="countText"></div>
    </div>
    <div id="orderList"></div>
  </div>
</main>

<script>
  // The key lives only in this variable. It is forgotten when the page closes.
  var adminKey = "";
  var allOrders = [];
  var refreshTimer = null;

  // The next steps an order can take
  var nextSteps = {
    Placed: ["Confirmed", "Cancelled"],
    Confirmed: ["Dispatched", "Cancelled"],
    Dispatched: ["Delivered", "Cancelled"]
  };
  var buttonText = {
    Confirmed: "Confirm", Dispatched: "Dispatch",
    Delivered: "Mark delivered", Cancelled: "Cancel order"
  };

  // Creates an element with plain text (never raw HTML, so names and
  // addresses typed by patients cannot run as code)
  function el(tag, text, cls) {
    var e = document.createElement(tag);
    if (text !== undefined) e.textContent = text;
    if (cls) e.className = cls;
    return e;
  }

  function showMessage(text, bad) {
    var box = document.getElementById("message");
    box.textContent = text;
    box.className = bad ? "bad" : "ok";
    setTimeout(function () { box.className = ""; box.textContent = ""; }, 5000);
  }

  // Sends a request to the server with the pharmacy key
  async function api(path, options) {
    options = options || {};
    var response = await fetch(path, {
      method: options.method || "GET",
      headers: { "X-Admin-Key": adminKey, "Content-Type": "application/json" },
      body: options.body
    });
    var data = {};
    try { data = await response.json(); } catch (e) {}
    if (!response.ok) { throw new Error(data.message || ("Error " + response.status)); }
    return data;
  }

  // Draws the list of orders
  function render() {
    var filter = document.getElementById("filter").value;
    var list = document.getElementById("orderList");
    list.textContent = "";

    var shown = allOrders.filter(function (o) { return !filter || o.status === filter; });
    document.getElementById("countText").textContent = shown.length + " order(s)";

    if (shown.length === 0) {
      list.appendChild(el("p", "No orders to show.", "muted"));
      return;
    }

    shown.forEach(function (order) {
      var card = el("div", undefined, "card");

      var top = el("div", undefined, "row");
      top.appendChild(el("strong", "Order #" + order.order_id));
      top.appendChild(el("span", order.status, "badge " + order.status));
      card.appendChild(top);

      card.appendChild(el("div", order.patient_name + "  |  " + order.patient_phone));
      card.appendChild(el("div", "Address: " + order.delivery_address, "muted"));
      card.appendChild(el("div", "Ordered: " + order.order_date + "  |  Payment: " + order.payment_method, "muted"));

      var ul = el("ul");
      order.items.forEach(function (item) {
        ul.appendChild(el("li", item.medicine + " x " + item.quantity));
      });
      card.appendChild(ul);

      card.appendChild(el("div",
        order.total_amount > 0 ? "Total: Rs " + order.total_amount.toFixed(2)
                             : "Price to be confirmed by the pharmacy",
        "muted"));

      // One button for each next step
      var steps = nextSteps[order.status] || [];
      if (steps.length > 0) {
        var actions = el("div", undefined, "row");
        actions.style.marginTop = "12px";
        actions.style.justifyContent = "flex-start";
        steps.forEach(function (step) {
          var b = el("button", buttonText[step], step === "Cancelled" ? "danger" : "");
          b.onclick = function () { changeStatus(order.order_id, step); };
          actions.appendChild(b);
        });
        card.appendChild(actions);
      }

      list.appendChild(card);
    });
  }

  // Loads the orders from the server
  async function loadOrders() {
    var data = await api("/api/pharmacy/orders");
    allOrders = data.orders;
    render();
  }

  // Moves an order to its next stage. The patient gets a notification.
  async function changeStatus(orderId, status) {
    if (status === "Cancelled" && !confirm("Cancel order #" + orderId + "? The patient will be told.")) {
      return;
    }
    try {
      await api("/api/medicine-orders/" + orderId + "/status", {
        method: "PUT",
        body: JSON.stringify({ status: status })
      });
      showMessage("Order #" + orderId + " is now " + status + ".", false);
      await loadOrders();
    } catch (e) {
      showMessage(e.message, true);
    }
  }

  async function login() {
    adminKey = document.getElementById("keyInput").value.trim();
    document.getElementById("keyInput").value = "";
    try {
      await loadOrders();
      document.getElementById("loginBox").style.display = "none";
      document.getElementById("ordersBox").style.display = "block";
      document.getElementById("logoutButton").style.display = "inline-block";
      // Refresh the list every 15 seconds
      refreshTimer = setInterval(function () { loadOrders().catch(function () {}); }, 15000);
    } catch (e) {
      adminKey = "";
      showMessage(e.message === "Not allowed" ? "Wrong key." : e.message, true);
    }
  }

  function logout() {
    adminKey = "";
    allOrders = [];
    clearInterval(refreshTimer);
    document.getElementById("orderList").textContent = "";
    document.getElementById("ordersBox").style.display = "none";
    document.getElementById("logoutButton").style.display = "none";
    document.getElementById("loginBox").style.display = "block";
  }

  document.getElementById("loginButton").onclick = login;
  document.getElementById("keyInput").onkeydown = function (e) { if (e.key === "Enter") { login(); } };
  document.getElementById("logoutButton").onclick = logout;
  document.getElementById("filter").onchange = render;
</script>
</body>
</html>"""


@app.route("/pharmacy", methods=["GET"])
def pharmacy_page():
    from flask import Response

    response = Response(PHARMACY_PAGE, mimetype="text/html")

    # The page may only talk to this server, and must not be cached
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Content-Security-Policy"] = (
        "default-src 'none'; connect-src 'self'; "
        "style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
        "base-uri 'none'; form-action 'none'"
    )

    return response

# ============================================================
# FIRST AID GUIDE
# General information only, with nothing private in it, so these
# two routes need no login (first aid must be quick to reach).
# ============================================================

# ----- The list of topics (names only) -----
@app.route("/api/first-aid", methods=["GET"])
def first_aid_list():
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # One row for each topic name (exact repeats are hidden).
        # DISTINCT ON keeps the first row of each name, and the ORDER BY
        # makes that the priority one, then the oldest.
        cursor.execute("""
            SELECT DISTINCT ON (LOWER(condition_name))
                first_aid_id,
                condition_name,
                COALESCE(category, 'More topics'),
                is_priority,
                reviewed
            FROM first_aid_guidance
            ORDER BY LOWER(condition_name),
                     (is_priority = 'Y') DESC,
                     first_aid_id
        """)

        topics = []

        for row in cursor.fetchall():
            topics.append({
                "first_aid_id": row[0],
                "name": row[1],
                "category": row[2],
                "is_priority": row[3] == 'Y',
                "reviewed": row[4] == 'Y'
            })

        # Important topics first, then the rest, each in alphabetical order
        topics.sort(key=lambda t: (not t["is_priority"], t["name"].lower()))

        return jsonify({
            "status": "success",
            "topics": topics
        }), 200

    except Exception as e:
        print("First Aid List Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the first aid topics"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# ----- The full text of one topic -----
@app.route("/api/first-aid/<int:first_aid_id>", methods=["GET"])
def first_aid_detail(first_aid_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                first_aid_id,
                condition_name,
                symptoms,
                first_aid_steps,
                do_not_do,
                when_to_seek_help,
                emergency_warning,
                COALESCE(category, 'More topics'),
                reviewed
            FROM first_aid_guidance
            WHERE first_aid_id = %s
        """, (first_aid_id,))

        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": "error",
                "message": "Topic not found"
            }), 404

        return jsonify({
            "status": "success",
            "topic": {
                "first_aid_id": row[0],
                "name": row[1],
                "symptoms": row[2],
                "steps": row[3],
                "do_not_do": row[4],
                "when_to_seek_help": row[5],
                "emergency_warning": row[6],
                "category": row[7],
                "reviewed": row[8] == 'Y'
            }
        }), 200

    except Exception as e:
        print("First Aid Detail Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the topic"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()



# ----- The patient closes their own SOS (they are safe) -----
@app.route(
    "/api/patients/<int:patient_id>/sos/<int:sos_id>/close",
    methods=["PUT"]
)
def patient_close_sos(patient_id, sos_id):
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Only this patient's own request, and only if still open
        cursor.execute("""
            UPDATE sos_requests
            SET status = 'Closed',
                updated_at = CURRENT_TIMESTAMP
            WHERE sos_id = %s
              AND patient_id = %s
              AND status <> 'Closed'
            RETURNING sos_id
        """, (sos_id, patient_id))

        if not cursor.fetchone():
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "SOS request not found or already closed"
            }), 404

        conn.commit()

        return jsonify({
            "status": "success",
            "message": "SOS request closed"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Patient Close SOS Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to close the SOS request"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ============================================================
# ADMIN PORTAL
# Login with username and password gives a signed token (8 hours).
# Every other admin route needs that token in the Authorization header.
# ============================================================

ADMIN_TOKEN_SECRET = os.getenv("ADMIN_TOKEN_SECRET")
ADMIN_TOKEN_HOURS = 8

admin_serializer = URLSafeTimedSerializer(
    ADMIN_TOKEN_SECRET or "unused", salt="admin-login"
)

# Too many wrong passwords: lock that address + username for 15 minutes
MAX_LOGIN_FAILS = 5
LOGIN_LOCK_SECONDS = 15 * 60
login_failures = {}  # key -> (number of failures, time of the first one)


def login_is_locked(key):
    entry = login_failures.get(key)

    if not entry:
        return False

    count, since = entry

    if time.time() - since > LOGIN_LOCK_SECONDS:
        login_failures.pop(key, None)
        return False

    return count >= MAX_LOGIN_FAILS


def note_login_failure(key):
    count, since = login_failures.get(key, (0, time.time()))
    login_failures[key] = (count + 1, since)


def admin_required(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        # Without a secret, tokens could be forged, so refuse everything
        if not ADMIN_TOKEN_SECRET:
            return jsonify({
                "status": "error",
                "message": "Admin login is not configured on the server"
            }), 503

        header = request.headers.get("Authorization", "")

        if not header.startswith("Bearer "):
            return jsonify({
                "status": "error",
                "message": "Please login"
            }), 401

        try:
            admin_serializer.loads(
                header[7:], max_age=ADMIN_TOKEN_HOURS * 3600
            )
        except (SignatureExpired, BadSignature):
            return jsonify({
                "status": "error",
                "message": "Session expired. Please login again."
            }), 401

        return f(*args, **kwargs)

    return wrapper


@app.route("/api/admin/login", methods=["POST"])
def admin_login():
    if not ADMIN_TOKEN_SECRET:
        return jsonify({
            "status": "error",
            "message": "Admin login is not configured on the server"
        }), 503

    data = request.get_json(silent=True) or {}
    username = (data.get("username") or "").strip()
    password = data.get("password") or ""

    key = f"{request.remote_addr}|{username.lower()}"

    if login_is_locked(key):
        return jsonify({
            "status": "error",
            "message": "Too many wrong attempts. Try again in 15 minutes."
        }), 429

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT admin_id, password_hash
            FROM admins
            WHERE username = %s
              AND is_active = TRUE
        """, (username,))

        row = cursor.fetchone()

        # Same message for a wrong username and a wrong password
        if not row or not check_password_hash(row[1], password):
            note_login_failure(key)
            return jsonify({
                "status": "error",
                "message": "Incorrect username or password"
            }), 401

        login_failures.pop(key, None)

        token = admin_serializer.dumps({"admin_id": row[0]})

        return jsonify({
            "status": "success",
            "token": token
        }), 200

    except Exception as e:
        print("Admin Login Error:", e)

        return jsonify({
            "status": "error",
            "message": "Login failed"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()
            


@app.route("/api/admin/stats", methods=["GET"])
@admin_required
def admin_stats():
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                (SELECT COUNT(*) FROM patients),
                (SELECT COUNT(*) FROM doctors WHERE approval_status = 'Approved'),
                (SELECT COUNT(*) FROM doctors WHERE approval_status = 'Pending'),
                (SELECT COUNT(*) FROM sos_requests WHERE status <> 'Closed')
        """)

        row = cursor.fetchone()

        return jsonify({
            "status": "success",
            "stats": {
                "patients": row[0],
                "doctors": row[1],
                "pending_doctors": row[2],
                "active_sos": row[3]
            }
        }), 200

    except Exception as e:
        print("Admin Stats Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the numbers"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


@app.route("/api/admin/doctors/pending", methods=["GET"])
@admin_required
def admin_pending_doctors():
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                d.doctor_id,
                u.full_name,
                u.phone,
                s.spec_name,
                d.qualification,
                d.experience_years,
                d.license_number
            FROM doctors d
            JOIN users u
                ON d.user_id = u.user_id
            JOIN specializations s
                ON d.specialization_id = s.spec_id
            WHERE d.approval_status = 'Pending'
            ORDER BY d.doctor_id
        """)

        doctors = []

        for row in cursor.fetchall():
            doctors.append({
                "doctor_id": row[0],
                "full_name": row[1],
                "phone": row[2],
                "specialization": row[3],
                "qualification": row[4],
                "experience_years": row[5],
                "license_number": row[6]
            })

        return jsonify({
            "status": "success",
            "doctors": doctors
        }), 200

    except Exception as e:
        print("Admin Pending Doctors Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the requests"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


@app.route("/api/admin/doctors/<int:doctor_id>/decision", methods=["PUT"])
@admin_required
def admin_decide_doctor(doctor_id):
    data = request.get_json(silent=True) or {}
    decision = data.get("decision")

    if decision not in ("approve", "reject"):
        return jsonify({
            "status": "error",
            "message": "decision must be approve or reject"
        }), 400

    new_status = "Approved" if decision == "approve" else "Rejected"

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Only a Pending request can be decided, and only once
        cursor.execute("""
            UPDATE doctors
            SET approval_status = %s
            WHERE doctor_id = %s
              AND approval_status = 'Pending'
            RETURNING doctor_id
        """, (new_status, doctor_id))

        if not cursor.fetchone():
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "Request not found or already decided"
            }), 404

        conn.commit()

        return jsonify({
            "status": "success",
            "approval_status": new_status
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Admin Decide Doctor Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to save the decision"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


@app.route("/api/admin/sos", methods=["GET"])
@admin_required
def admin_list_sos():
    # Fixed pieces of SQL only, nothing from the request goes into the query
    flt = request.args.get("filter", "all")

    if flt == "active":
        where = "WHERE s.status <> 'Closed'"
    elif flt == "closed":
        where = "WHERE s.status = 'Closed'"
    else:
        where = ""

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute(f"""
            SELECT
                s.sos_id,
                s.request_time,
                s.updated_at,
                s.status,
                s.location_lat,
                s.location_lng,
                s.emergency_type,
                u.full_name,
                u.phone,
                p.emergency_contact_name,
                p.emergency_contact_phone
            FROM sos_requests s
            JOIN patients p
                ON s.patient_id = p.patient_id
            JOIN users u
                ON p.user_id = u.user_id
            {where}
            ORDER BY s.request_time DESC
            LIMIT 100
        """)

        sos_list = []

        for row in cursor.fetchall():
            sos_list.append({
                "sos_id": row[0],
                "request_time": str(row[1])[:16],
                "updated_at": str(row[2])[:16] if row[2] else None,
                "status": row[3],
                "latitude": float(row[4]) if row[4] is not None else None,
                "longitude": float(row[5]) if row[5] is not None else None,
                "emergency_type": row[6],
                "patient_name": row[7],
                "patient_phone": row[8],
                "contact_name": row[9],
                "contact_phone": row[10]
            })

        return jsonify({
            "status": "success",
            "sos": sos_list
        }), 200

    except Exception as e:
        print("Admin List SOS Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the SOS requests"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


@app.route("/api/admin/sos/<int:sos_id>/status", methods=["PUT"])
@admin_required
def admin_update_sos_status(sos_id):
    data = request.get_json(silent=True) or {}
    new_status = data.get("status")

    if new_status not in ["Requested", "Assigned", "Enroute", "Arrived", "Closed"]:
        return jsonify({
            "status": "error",
            "message": "Invalid SOS status"
        }), 400

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            UPDATE sos_requests
            SET status = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE sos_id = %s
            RETURNING sos_id
        """, (new_status, sos_id))

        if not cursor.fetchone():
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "SOS request not found"
            }), 404

        conn.commit()

        return jsonify({
            "status": "success",
            "new_status": new_status
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Admin Update SOS Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to update the SOS status"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


@app.route("/api/admin/users/<group>", methods=["GET"])
@admin_required
def admin_list_users(group):
    if group == "patients":
        sql = """
            SELECT p.patient_id, u.full_name, u.phone, u.status, NULL
            FROM patients p
            JOIN users u ON p.user_id = u.user_id
            ORDER BY u.full_name
            LIMIT 500
        """
    elif group == "doctors":
        sql = """
            SELECT d.doctor_id, u.full_name, u.phone, u.status, d.approval_status
            FROM doctors d
            JOIN users u ON d.user_id = u.user_id
            ORDER BY u.full_name
            LIMIT 500
        """
    else:
        return jsonify({
            "status": "error",
            "message": "Unknown group"
        }), 404

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(sql)

        users = []

        for row in cursor.fetchall():
            users.append({
                "id": row[0],
                "full_name": row[1],
                "phone": row[2],
                "active": row[3] == "Active",
                "approval_status": row[4]
            })

        return jsonify({
            "status": "success",
            "users": users
        }), 200

    except Exception as e:
        print("Admin List Users Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to load the users"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


@app.route("/api/admin/users/<group>/<int:record_id>/active", methods=["PUT"])
@admin_required
def admin_set_user_active(group, record_id):
    data = request.get_json(silent=True) or {}
    active = data.get("active")

    if not isinstance(active, bool):
        return jsonify({
            "status": "error",
            "message": "active must be true or false"
        }), 400

    if group == "patients":
        sql = """
            UPDATE users SET status = %s
            WHERE user_id = (SELECT user_id FROM patients WHERE patient_id = %s)
            RETURNING user_id
        """
    elif group == "doctors":
        sql = """
            UPDATE users SET status = %s
            WHERE user_id = (SELECT user_id FROM doctors WHERE doctor_id = %s)
            RETURNING user_id
        """
    else:
        return jsonify({
            "status": "error",
            "message": "Unknown group"
        }), 404

    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute(sql, ("Active" if active else "Inactive", record_id))

        if not cursor.fetchone():
            conn.rollback()
            return jsonify({
                "status": "error",
                "message": "User not found"
            }), 404

        conn.commit()

        return jsonify({
            "status": "success"
        }), 200

    except Exception as e:
        if conn:
            conn.rollback()

        print("Admin Set User Active Error:", e)

        return jsonify({
            "status": "error",
            "message": "Failed to update the user"
        }), 500

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()

# ------------------------------------------------------------
# MAKE SURE THE DOCTORS TABLE HAS THE approval_status COLUMN
# Runs every time the server starts. If the column already
# exists, nothing changes. Doctors are "Approved" by default,
# so nobody is blocked from logging in.
# ------------------------------------------------------------
def ensure_approval_column():
    conn = None
    cursor = None

    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Adds the column only if it is missing
        cursor.execute("""
            ALTER TABLE doctors
            ADD COLUMN IF NOT EXISTS approval_status VARCHAR(20)
            NOT NULL DEFAULT 'Approved'
        """)

        conn.commit()
        print("Doctors approval column is ready")

    except Exception as e:
        if conn:
            conn.rollback()

        print("Approval column setup error:", e)

    finally:
        if cursor:
            cursor.close()

        if conn:
            conn.close()


# Run it once when the server starts
ensure_approval_column()

if __name__ == "__main__":
    # Start the reminder timer (appointment and follow-up reminders)
    start_reminder_thread()

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False
    )
