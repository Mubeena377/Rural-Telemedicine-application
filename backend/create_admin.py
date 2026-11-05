import os
import getpass
import psycopg2
from dotenv import load_dotenv
from werkzeug.security import generate_password_hash

load_dotenv()

username = input("Admin username: ").strip()
password = getpass.getpass("Password (at least 10 characters): ")

if not username or len(password) < 10:
    raise SystemExit("Username is required and the password must be at least 10 characters.")

conn = psycopg2.connect(
    dbname=os.getenv("DB_NAME"),
    user=os.getenv("DB_USER"),
    password=os.getenv("DB_PASSWORD"),
    host=os.getenv("DB_HOST"),
    port=os.getenv("DB_PORT"),
)
cur = conn.cursor()
cur.execute(
    "INSERT INTO admins (username, password_hash, full_name) VALUES (%s, %s, %s)",
    (username, generate_password_hash(password), username),
)
conn.commit()
conn.close()
print("Admin created.")