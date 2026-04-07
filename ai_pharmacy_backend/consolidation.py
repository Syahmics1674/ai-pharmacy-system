from firebase_config import db
from datetime import datetime

def get_route_id(clinic_id):
    doc = db.collection("clinics").document(clinic_id).get()
    
    if doc.exists:
        return doc.to_dict().get("route_id")
    
    return None

def get_clinics_in_route(route_id):
    clinics = []

    docs = db.collection("clinics") \
             .where("route_id", "==", route_id) \
             .stream()

    for doc in docs:
        clinics.append(doc.id)

    return clinics

def get_suggested_order_date(clinic_id):
    docs = db.collection("inventory") \
        .where("clinic_id", "==", clinic_id) \
        .stream()

    highest_priority = None
    earliest_date = None

    for doc in docs:
        data = doc.to_dict()
        stock = data.get("current_stock", 0)

        if stock < 100:
            priority = "HIGH"
        elif stock < 200:
            priority = "MEDIUM"
        else:
            continue

        date = datetime.utcnow() 

        # 🔥 PRIORITY HANDLING
        if priority == "HIGH":
            if highest_priority != "HIGH":
                highest_priority = "HIGH"
                earliest_date = date

        elif priority == "MEDIUM":
            if highest_priority not in ["HIGH", "MEDIUM"]:
                highest_priority = "MEDIUM"
                earliest_date = date

    if highest_priority:
        return {
            "date": earliest_date,
            "priority": highest_priority
        }

    return None

def consolidate_order_date(current_clinic_id):

    route_id = get_route_id(current_clinic_id)

    if not route_id:
        print("No route found")
        return None

    clinic_list = get_clinics_in_route(route_id)

    # 🔹 Collect all suggestions
    high = []
    medium = []
    low = []

    details = []

    for clinic in clinic_list:
        suggestion = get_suggested_order_date(clinic)

        if not suggestion or not suggestion["date"]:
            continue

        date = suggestion["date"]
        priority = suggestion["priority"]

        details.append({
            "clinic": clinic,
            "date": str(date),
            "priority": priority
        })

        if priority == "HIGH":
            high.append(date)
        elif priority == "MEDIUM":
            medium.append(date)
        else:
            low.append(date)

    # 🔥 PRIORITY LOGIC
    if high:
        filtered_details = [d for d in details if d["priority"] == "HIGH"]
        return {
            "date": min(high),
            "based_on": "HIGH",
            "details": filtered_details
        }

    if medium:
        filtered_details = [d for d in details if d["priority"] == "MEDIUM"]
        return {
            "date": min(medium),
            "based_on": "MEDIUM",
            "details": filtered_details
        }

    if low:
        filtered_details = [d for d in details if d["priority"] == "LOW"]
        return {
            "date": min(low),
            "based_on": "LOW",
            "details": filtered_details
        }

    return None