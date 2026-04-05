from firebase_config import db

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
    docs = db.collection("order_suggestions") \
        .where("clinic_id", "==", clinic_id) \
        .stream()

    for doc in docs:
        data = doc.to_dict()
        return {
            "date": data.get("suggested_date"),
            "priority": data.get("priority", "LOW")
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
        return {"date": min(high), "based_on": "HIGH", "details": details}

    if medium:
        return {"date": min(medium), "based_on": "MEDIUM", "details": details}

    if low:
        return {"date": min(low), "based_on": "LOW", "details": details}

    return None