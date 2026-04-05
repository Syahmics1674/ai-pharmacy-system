import firebase_admin
from firebase_admin import credentials, firestore

# Load Firebase key
cred = credentials.Certificate("firebase_key.json")

# Initialize Firebase app (only once)
firebase_admin.initialize_app(cred)

# Firestore database reference
db = firestore.client()
