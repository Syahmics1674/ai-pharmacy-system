from firebase_config import db

# Write test data
db.collection("test_connection").add({
    "message": "Backend connected!",
    "status": "success"
})

print("✅ Firebase connected successfully!")