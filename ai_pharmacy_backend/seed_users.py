from firebase_config import db


def upsert_user(user_id, data):
    db.collection("users").document(user_id).set(data, merge=True)
    print(f"Upserted user: {user_id}")


def seed_clinic_users():
    clinic_ids = [
        "clinic_bangkit",
        "clinic_bena",
        "clinic_chemenong",
        "clinic_engkuah",
        "clinic_entawau",
        "clinic_gaat",
        "clinic_mujong",
        "clinic_song",
        "clinic_tekalit",
    ]

    for clinic_id in clinic_ids:
        upsert_user(
            clinic_id,
            {
                "user_id": clinic_id,
                "name": clinic_id,
                "role": "clinic",
                "clinic_id": clinic_id,
                "password": "1234",
            },
        )


def seed_pkd_user():
    upsert_user(
        "pkd_kapit",
        {
            "user_id": "pkd_kapit",
            "name": "PKD Kapit",
            "role": "pkd",
            "district": "Kapit",
            "password": "admin123",
        },
    )


def seed_users():
    seed_clinic_users()
    seed_pkd_user()


if __name__ == "__main__":
    seed_users()
