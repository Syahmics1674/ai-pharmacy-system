from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

# Load Firebase key
BASE_DIR = Path(__file__).resolve().parent
cred = credentials.Certificate(str(BASE_DIR / "firebase_key.json"))

# Initialize Firebase app (only once)
firebase_admin.initialize_app(cred)

# Firestore database reference
db = firestore.client()
