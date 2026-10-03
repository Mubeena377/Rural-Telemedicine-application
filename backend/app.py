import os
from dotenv import load_dotenv
from flask import Flask,request,jsonify
from flask_cors import CORS
import psycopg2
from werkzeug.utils import secure_filename
from werkzeug.security import generate_password_hash
import joblib
import time
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

        conn.commit()

        print(
            "APPOINTMENT CREATED. Appointment ID =",
            appointment_id
        )

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
                d.is_available
            FROM doctors d
            JOIN users u
                ON d.user_id = u.user_id
            JOIN specializations s
                ON d.specialization_id = s.spec_id
            WHERE u.role_id = 1
              AND d.is_available = 'Y'
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
                d.is_available
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
if __name__ == "__main__":

        app.run(
        host="0.0.0.0",
        port=5000,
        debug=False
    )
