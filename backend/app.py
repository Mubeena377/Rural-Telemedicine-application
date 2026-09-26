import os
from dotenv import load_dotenv
from flask import Flask,request,jsonify
from flask_cors import CORS
import psycopg2
from werkzeug.utils import secure_filename
from werkzeug.security import generate_password_hash
import joblib

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

if __name__ == "__main__":

        app.run(
        host="0.0.0.0",
        port=5000,
        debug=False
    )
