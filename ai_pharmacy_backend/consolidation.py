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


def get_clinic_name(clinic_id):
    doc = db.collection("clinics").document(clinic_id).get()

    if doc.exists:
        return doc.to_dict().get("name", clinic_id)

    return clinic_id


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


def build_recommendation_message(based_on, summary):
    if based_on == "HIGH":
        count = summary.get("high_priority_count", 0)
        return (
            f"Order immediately. {count} clinics have high-priority shortages."
        )

    if based_on == "MEDIUM":
        count = summary.get("medium_priority_count", 0)
        return (
            f"Plan to order soon. {count} clinics have moderately low stock."
        )

    count = summary.get("low_priority_count", 0)
    return (
        f"Stock is sufficient. {count} clinics have low-priority stock levels, "
        f"so no urgent order is needed."
    )


def consolidate_order_date(current_clinic_id):

    clinic_doc = db.collection("clinics").document(current_clinic_id).get()

    if clinic_doc.exists:
        if clinic_doc.to_dict().get("has_pending_order"):
            print("⛔ Order already pending → skip consolidation")
            return None

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
    summary = {
        "total_clinics": len(clinic_list),
        "high_priority_count": 0,
        "medium_priority_count": 0,
        "low_priority_count": 0
    }
    most_urgent_clinic = None

    for clinic in clinic_list:
        clinic_name = get_clinic_name(clinic)
        suggestion = get_suggested_order_date(clinic)

        if suggestion and suggestion["date"]:
            date = suggestion["date"]
            priority = suggestion["priority"]
        else:
            date = None
            priority = "LOW"

        details.append({
            "clinic": clinic_name,
            "clinic_id": clinic,
            "date": str(date) if date else None,
            "priority": priority
        })

        if priority == "HIGH":
            summary["high_priority_count"] += 1
            high.append(date)
            if most_urgent_clinic is None or date < most_urgent_clinic["date"]:
                most_urgent_clinic = {
                    "clinic": clinic_name,
                    "date": date
                }
        elif priority == "MEDIUM":
            summary["medium_priority_count"] += 1
            medium.append(date)
        else:
            summary["low_priority_count"] += 1
            if date:
                low.append(date)

    if high:
        return {
            "date": min(high),
            "based_on": "HIGH",
            "summary": summary,
            "most_urgent_clinic": most_urgent_clinic["clinic"] if most_urgent_clinic else None,
            "recommendation_message": build_recommendation_message("HIGH", summary),
            "details": details
        }

    if medium:
        return {
            "date": min(medium),
            "based_on": "MEDIUM",
            "summary": summary,
            "most_urgent_clinic": None,
            "recommendation_message": build_recommendation_message("MEDIUM", summary),
            "details": details
        }

    if low:
        return {
            "date": min(low),
            "based_on": "LOW",
            "summary": summary,
            "most_urgent_clinic": None,
            "recommendation_message": build_recommendation_message("LOW", summary),
            "details": details
        }

    return None
