from flask import Flask, request, jsonify
from firebase_admin import firestore
from consolidation import consolidate_order_date
from firebase_config import db  
from migrate_inventory import (
    build_match_index,
    initialize_clinic_inventory,
    list_medicines,
    match_medicine,
)
from datetime import timedelta
from datetime import datetime
from flask_cors import CORS  
from collections import defaultdict
import sys
import os

# Allow import from ai_prediction parent directory
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'ai_prediction')))

AI_FEATURES_AVAILABLE = True
AI_IMPORT_ERROR = None

try:
    from ai_engine import generate_forecast, detect_anomalies, calculate_smart_inventory
except ModuleNotFoundError as exc:
    AI_FEATURES_AVAILABLE = False
    AI_IMPORT_ERROR = str(exc)
    generate_forecast = None
    detect_anomalies = None
    calculate_smart_inventory = None

try:
    from weather_service import get_7_day_weather
except ModuleNotFoundError:
    def get_7_day_weather():
        return {"max_rain_mm": 0.0}

app = Flask(__name__)
CORS(app)


def ai_unavailable_response():
    if AI_FEATURES_AVAILABLE:
        return None

    return jsonify({
        "error": "AI features are unavailable",
        "details": (
            "Install the AI dependencies from requirements.txt "
            f"to enable forecasting endpoints. Missing module: {AI_IMPORT_ERROR}"
        )
    }), 503


def get_medicine_catalog():
    medicines = list_medicines()
    medicine_lookup = {
        medicine["medicine_id"]: medicine
        for medicine in medicines
        if medicine.get("medicine_id")
    }
    match_index = build_match_index(medicines)
    return medicines, medicine_lookup, match_index


def resolve_medicine(medicine_id=None, item_name=None, medicines=None, medicine_lookup=None, match_index=None):
    medicines = medicines or []
    medicine_lookup = medicine_lookup or {}

    if medicine_id and medicine_id in medicine_lookup:
        return medicine_lookup[medicine_id]

    if not item_name:
        return None

    return match_medicine(
        item_name,
        medicines=medicines,
        match_index=match_index,
    )


def standardize_inventory_entry(data, medicines=None, medicine_lookup=None, match_index=None):
    medicine = resolve_medicine(
        medicine_id=data.get("medicine_id"),
        item_name=data.get("item_name"),
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )

    return {
        "medicine_id": medicine["medicine_id"] if medicine else data.get("medicine_id", ""),
        "item_name": medicine["name"] if medicine else data.get("item_name", "Unknown Medicine"),
        "category": medicine.get("category") if medicine else data.get("category", "Uncategorized"),
        "product_code": (
            medicine.get("product_code", medicine.get("medicine_id", ""))
            if medicine else data.get("product_code", "")
        ),
        "unit": medicine.get("unit") if medicine else data.get("unit", ""),
        "current_stock": data.get("current_stock", 0),
        "min_order_qty": data.get(
            "min_order_qty",
            medicine.get("standard_min_qty", 100) if medicine else 100,
        ),
        "last_updated": data.get("last_updated"),
    }


def standardize_log_entry(data, medicines=None, medicine_lookup=None, match_index=None):
    medicine = resolve_medicine(
        medicine_id=data.get("medicine_id"),
        item_name=data.get("item_name"),
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )

    item_name = medicine["name"] if medicine else data.get("item_name", "Unknown Medicine")
    medicine_id = medicine["medicine_id"] if medicine else data.get("medicine_id", "")

    return {
        "medicine_id": medicine_id,
        "item_name": item_name,
    }


def standardize_order_item(item, medicines=None, medicine_lookup=None, match_index=None):
    medicine = resolve_medicine(
        medicine_id=item.get("medicine_id"),
        item_name=item.get("item_name"),
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )

    quantity = item.get("qty")
    if quantity is None:
        quantity = item.get("suggested_qty", item.get("quantity", 0))

    standardized_name = medicine["name"] if medicine else item.get("item_name", "Unknown Medicine")
    standardized_id = medicine["medicine_id"] if medicine else item.get("medicine_id", "")

    return {
        "medicine_id": standardized_id,
        "item_name": standardized_name,
        "qty": quantity,
        "suggested_qty": item.get("suggested_qty", quantity),
    }


def matches_medicine_reference(data, medicine_id=None, item_name=None, medicines=None, medicine_lookup=None, match_index=None):
    if medicine_id and data.get("medicine_id") == medicine_id:
        return True

    if item_name and data.get("item_name") == item_name:
        return True

    resolved = resolve_medicine(
        medicine_id=data.get("medicine_id"),
        item_name=data.get("item_name"),
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )
    requested = resolve_medicine(
        medicine_id=medicine_id,
        item_name=item_name,
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )

    if resolved and requested:
        return resolved["medicine_id"] == requested["medicine_id"]

    return False


def get_inventory_docs_for_clinic(clinic_id):
    return list(
        db.collection("inventory")
        .where("clinic_id", "==", clinic_id)
        .stream()
    )


def get_district_clinics(district):
    docs = db.collection("clinics") \
             .where("district", "==", district) \
             .stream()

    clinics = []

    for doc in docs:
        data = doc.to_dict()
        clinics.append({
            "clinic_id": doc.id,
            "name": data.get("name", doc.id),
            "route_id": data.get("route_id", "Unassigned")
        })

    clinics.sort(key=lambda clinic: clinic["name"].lower())
    return clinics


def analyze_clinic_risk(clinic_id):
    docs = db.collection("inventory") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    high_items = 0
    medium_items = 0

    for doc in docs:
        data = doc.to_dict()
        stock = data.get("current_stock", 0)

        if stock < 100:
            high_items += 1
        elif stock < 200:
            medium_items += 1

    if high_items > 0:
        return {
            "risk_level": "HIGH",
            "next_order_date": datetime.utcnow(),
            "high_item_count": high_items,
            "medium_item_count": medium_items
        }

    if medium_items > 0:
        return {
            "risk_level": "MEDIUM",
            "next_order_date": datetime.utcnow() + timedelta(days=5),
            "high_item_count": high_items,
            "medium_item_count": medium_items
        }

    return {
        "risk_level": "LOW",
        "next_order_date": datetime.utcnow() + timedelta(days=14),
        "high_item_count": high_items,
        "medium_item_count": medium_items
    }


def count_orders_for_clinic(clinic_id, status):
    docs = db.collection("orders") \
             .where("clinic_id", "==", clinic_id) \
             .where("status", "==", status) \
             .stream()

    return sum(1 for _ in docs)


def build_pkd_clinic_analysis(district):
    clinics = get_district_clinics(district)
    analysis = []

    for clinic in clinics:
        risk = analyze_clinic_risk(clinic["clinic_id"])
        pending_orders = count_orders_for_clinic(clinic["clinic_id"], "PENDING")

        analysis.append({
            "clinic_id": clinic["clinic_id"],
            "name": clinic["name"],
            "route_id": clinic["route_id"],
            "risk_level": risk["risk_level"],
            "next_order_date": risk["next_order_date"].strftime("%Y-%m-%d"),
            "pending_orders": pending_orders,
            "high_item_count": risk["high_item_count"],
            "medium_item_count": risk["medium_item_count"]
        })

    risk_priority = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
    analysis.sort(key=lambda clinic: (risk_priority.get(clinic["risk_level"], 3), clinic["name"].lower()))
    return analysis

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json(silent=True) or {}
    user_id = (data.get("user_id") or "").strip()
    password = data.get("password")

    if not user_id or not password:
        return jsonify({"error": "user_id and password are required"}), 400

    doc = db.collection("users").document(user_id).get()

    if not doc.exists:
        return jsonify({"error": "User not found"}), 404

    user = doc.to_dict()

    if user.get("password") != password:
        return jsonify({"error": "Invalid password"}), 401

    return jsonify({
        "success": True,
        "role": user.get("role"),
        "clinic_id": user.get("clinic_id"),
        "district": user.get("district")
    })


@app.route('/clinics_by_district', methods=['GET'])
def clinics_by_district():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    return jsonify({"clinics": get_district_clinics(district)})


@app.route('/pkd_summary', methods=['GET'])
def pkd_summary():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    clinic_analysis = build_pkd_clinic_analysis(district)

    total_clinics = len(clinic_analysis)
    high_risk_clinics = sum(1 for clinic in clinic_analysis if clinic["risk_level"] == "HIGH")
    pending_orders = sum(clinic["pending_orders"] for clinic in clinic_analysis)
    submitted_orders = sum(
        count_orders_for_clinic(clinic["clinic_id"], "SUBMITTED")
        for clinic in clinic_analysis
    )

    return jsonify({
        "total_clinics": total_clinics,
        "high_risk_clinics": high_risk_clinics,
        "pending_orders": pending_orders,
        "submitted_orders": submitted_orders
    })


@app.route('/pkd_clinic_analysis', methods=['GET'])
def pkd_clinic_analysis():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    clinic_analysis = build_pkd_clinic_analysis(district)

    return jsonify({
        "clinics": [
            {
                "clinic_id": clinic["clinic_id"],
                "name": clinic["name"],
                "route_id": clinic["route_id"],
                "risk_level": clinic["risk_level"],
                "next_order_date": clinic["next_order_date"],
                "pending_orders": clinic["pending_orders"]
            }
            for clinic in clinic_analysis
        ]
    })


@app.route('/pkd_route_analysis', methods=['GET'])
def pkd_route_analysis():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    clinic_analysis = build_pkd_clinic_analysis(district)
    routes = defaultdict(list)

    for clinic in clinic_analysis:
        routes[clinic["route_id"]].append(clinic)

    route_results = []

    for route_id, clinics in routes.items():
        urgent_date = min(clinic["next_order_date"] for clinic in clinics)
        route_results.append({
            "route_id": route_id,
            "total_clinics": len(clinics),
            "high_risk_clinics": sum(1 for clinic in clinics if clinic["risk_level"] == "HIGH"),
            "urgent_date": urgent_date
        })

    route_results.sort(key=lambda route: route["route_id"])

    return jsonify({"routes": route_results})


@app.route('/pkd_alerts', methods=['GET'])
def pkd_alerts():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    clinic_analysis = build_pkd_clinic_analysis(district)
    alerts = []

    for clinic in clinic_analysis:
        if clinic["risk_level"] == "HIGH":
            if clinic["high_item_count"] > 1:
                alerts.append(
                    f"{clinic['name']} has multiple HIGH-risk medicines"
                )
            else:
                alerts.append(
                    f"{clinic['name']} has a HIGH-risk medicine that may need urgent attention"
                )

    route_map = defaultdict(list)
    for clinic in clinic_analysis:
        route_map[clinic["route_id"]].append(clinic)

    for route_id, clinics in route_map.items():
        if any(clinic["risk_level"] == "HIGH" for clinic in clinics):
            alerts.append(f"{route_id} may require urgent replenishment")

    upcoming_clinics = sum(
        1 for clinic in clinic_analysis if clinic["risk_level"] in ["HIGH", "MEDIUM"]
    )
    alerts.append(
        f"{upcoming_clinics} clinics expected to submit orders within 5 days"
    )

    return jsonify({"alerts": alerts[:6]})

@app.route('/clinic_info', methods=['GET'])
def clinic_info():
    clinic_id = request.args.get('clinic_id')

    doc = db.collection("clinics").document(clinic_id).get()

    if not doc.exists:
        return jsonify({"error": "Clinic not found"}), 404

    data = doc.to_dict()

    return jsonify({
        "clinic_id": clinic_id,
        "clinic_name": data.get("name", clinic_id)
    })

@app.route('/consolidate', methods=['GET'])
def consolidate():

    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400

    result = consolidate_order_date(clinic_id)

    if not result:
        return jsonify({
            "consolidated_date": "No urgent orders",
            "based_on": "None",
            "summary": {},
            "most_urgent_clinic": None,
            "recommendation_message": "No urgent orders detected.",
            "details": []
        })

    from datetime import timedelta

    malaysia_time = result["date"] + timedelta(hours=8)

    print("Final Consolidated Date:", malaysia_time)

    return jsonify({
        "clinic_id": clinic_id,
        "consolidated_date": malaysia_time.strftime("%Y-%m-%d"),
        "based_on": result["based_on"],
        "summary": result.get("summary", {}),
        "most_urgent_clinic": result.get("most_urgent_clinic"),
        "recommendation_message": result.get("recommendation_message", ""),
        "details": result["details"]
    })


@app.route('/medicines', methods=['GET'])
def get_medicines():
    medicines = list_medicines()

    return jsonify({
        "medicines": medicines
    })

@app.route('/inventory', methods=['GET'])
def get_inventory():

    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400

    docs = db.collection("inventory") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    inventory_list = []

    for doc in docs:
        data = doc.to_dict()
        inventory_list.append(
            standardize_inventory_entry(
                data,
                medicines=medicines,
                medicine_lookup=medicine_lookup,
                match_index=match_index,
            )
        )

    inventory_list.sort(
        key=lambda item: (
            item.get("category", ""),
            item.get("current_stock", 0),
            item.get("item_name", ""),
        )
    )
    
    clinic_doc = db.collection("clinics").document(clinic_id).get()
    clinic_name = clinic_doc.to_dict().get("name", clinic_id)

    return jsonify({
        "clinic_id": clinic_id,
        "clinic_name": clinic_name,  
        "inventory": inventory_list
    })


@app.route('/inventory_summary', methods=['GET'])
def get_inventory_summary():
    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    inventory_docs = get_inventory_docs_for_clinic(clinic_id)
    inventory_items = [
        standardize_inventory_entry(
            doc.to_dict(),
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        for doc in inventory_docs
    ]

    low_stock_count = sum(
        1 for item in inventory_items if 0 < item["current_stock"] < item["min_order_qty"]
    )
    out_of_stock_count = sum(
        1 for item in inventory_items if item["current_stock"] <= 0
    )

    usage_docs = list(
        db.collection("usage_logs")
        .where("clinic_id", "==", clinic_id)
        .stream()
    )
    usage_by_medicine = defaultdict(int)
    for doc in usage_docs:
        data = doc.to_dict()
        standardized = standardize_log_entry(
            data,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        quantity = data.get("quantity_used", data.get("qty_used", 0))
        usage_by_medicine[standardized["medicine_id"]] += quantity

    top_used = []
    for medicine_id, total_used in sorted(
        usage_by_medicine.items(),
        key=lambda entry: entry[1],
        reverse=True,
    )[:5]:
        medicine = medicine_lookup.get(medicine_id)
        top_used.append({
            "medicine_id": medicine_id,
            "item_name": medicine["name"] if medicine else medicine_id,
            "total_used": total_used,
        })

    return jsonify({
        "clinic_id": clinic_id,
        "total_medicines": len(inventory_items),
        "low_stock_count": low_stock_count,
        "out_of_stock_count": out_of_stock_count,
        "top_used_medicines": top_used,
    })

@app.route('/order_suggestions', methods=['GET'])
def get_order_suggestions():

    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400
    
    clinic_doc = db.collection("clinics").document(clinic_id).get()

    if clinic_doc.exists and clinic_doc.to_dict().get("has_pending_order"):
        return jsonify({
            "clinic_id": clinic_id,
            "order_suggestions": []
        })

    docs = db.collection("inventory") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    suggestions = []

    for doc in docs:
        data = doc.to_dict()
        inventory_item = standardize_inventory_entry(
            data,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        stock = inventory_item.get("current_stock", 0)
        item = inventory_item.get("item_name")
        medicine_id = inventory_item.get("medicine_id", "")
        min_order_qty = inventory_item.get("min_order_qty", 100)

        # 🔥 LOW STOCK RULE
        if stock < min_order_qty:
            suggestions.append({
                "medicine_id": medicine_id,
                "item_name": item,
                "suggested_qty": max(min_order_qty * 2 - stock, min_order_qty),
                "priority": "HIGH"
            })

        elif stock < min_order_qty * 2:
            suggestions.append({
                "medicine_id": medicine_id,
                "item_name": item,
                "suggested_qty": max(min_order_qty * 3 - stock, min_order_qty),
                "priority": "MEDIUM"
            })

    return jsonify({
        "clinic_id": clinic_id,
        "order_suggestions": suggestions
    })

@app.route('/usage_logs', methods=['GET'])
def get_usage_logs():

    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400

    docs = db.collection("usage_logs") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    logs = []

    for doc in docs:
        data = doc.to_dict()
        standardized = standardize_log_entry(
            data,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )

        # Convert timestamp → Malaysia time
        timestamp = data.get("timestamp")
        if timestamp:
            malaysia_time = timestamp + timedelta(hours=8)
            formatted_time = malaysia_time.strftime("%Y-%m-%d %H:%M:%S")
        else:
            formatted_time = None

        logs.append({
            "medicine_id": standardized["medicine_id"],
            "item_name": standardized["item_name"],
            "quantity_used": data.get("quantity_used", data.get("qty_used", 0)),
            "timestamp": formatted_time
        })

    return jsonify({
        "clinic_id": clinic_id,
        "usage_logs": logs
    })

@app.route('/usage_logs', methods=['POST'])
def add_usage_log():

    data = request.get_json()

    clinic_id = data.get("clinic_id")
    medicine_id = data.get("medicine_id")
    item_name = data.get("item_name")
    quantity_used = data.get("quantity_used", data.get("qty_used"))

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    medicine = resolve_medicine(
        medicine_id=medicine_id,
        item_name=item_name,
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )

    if not clinic_id or quantity_used is None or (not medicine and not item_name):
        return jsonify({"error": "Missing data"}), 400

    standardized_name = medicine["name"] if medicine else item_name
    standardized_id = medicine["medicine_id"] if medicine else medicine_id

    db.collection("usage_logs").add({
        "clinic_id": clinic_id,
        "medicine_id": standardized_id,
        "item_name": standardized_name,
        "quantity_used": quantity_used,
        "qty_used": quantity_used,
        "timestamp": datetime.utcnow()
    })

    return jsonify({
        "message": "Usage log added successfully"
    })


@app.route('/stock_in_logs', methods=['GET'])
def get_stock_in_logs():
    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400

    docs = db.collection("stock_in_logs") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    logs = []

    for doc in docs:
        data = doc.to_dict()
        standardized = standardize_log_entry(
            data,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        logs.append({
            "medicine_id": standardized["medicine_id"],
            "item_name": standardized["item_name"],
            "quantity_received": data.get(
                "quantity_received",
                data.get("qty_received", data.get("qty_added", data.get("quantity_added", 0))),
            ),
            "timestamp": str(data.get("timestamp")),
        })

    return jsonify({
        "clinic_id": clinic_id,
        "stock_in_logs": logs,
    })

@app.route('/stock_in', methods=['POST'])
def stock_in():

    data = request.get_json()

    print("🔥 RECEIVED:", data)

    clinic_id = data.get("clinic_id")
    medicine_id = data.get("medicine_id")
    item_name = data.get("item_name")
    quantity_added = int(data.get("quantity_added", 0))  

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    medicine = resolve_medicine(
        medicine_id=medicine_id,
        item_name=item_name,
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )

    if clinic_id is None or quantity_added is None or (not medicine and item_name is None):
        return jsonify({"error": "Missing data"}), 400

    standardized_name = medicine["name"] if medicine else item_name
    standardized_id = medicine["medicine_id"] if medicine else medicine_id

    docs = get_inventory_docs_for_clinic(clinic_id)

    found = False

    for doc in docs:
        data_db = doc.to_dict()
        if not matches_medicine_reference(
            data_db,
            medicine_id=standardized_id,
            item_name=standardized_name,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        ):
            continue

        found = True
        current_stock = data_db.get("current_stock", 0)

        new_stock = current_stock + quantity_added

        db.collection("inventory").document(doc.id).update({
            "medicine_id": standardized_id,
            "item_name": standardized_name,
            "category": medicine.get("category", data_db.get("category", "")) if medicine else data_db.get("category", ""),
            "product_code": (
                medicine.get("product_code", medicine.get("medicine_id", standardized_id))
                if medicine else data_db.get("product_code", standardized_id)
            ),
            "unit": medicine.get("unit", data_db.get("unit", "")) if medicine else data_db.get("unit", ""),
            "current_stock": new_stock,
            "min_order_qty": data_db.get(
                "min_order_qty",
                medicine.get("standard_min_qty", 100) if medicine else 100,
            ),
            "last_updated": firestore.SERVER_TIMESTAMP,
        })

    if not found:
        db.collection("inventory").add({
            "clinic_id": clinic_id,
            "medicine_id": standardized_id,
            "item_name": standardized_name,
            "category": medicine.get("category", "") if medicine else "",
            "product_code": medicine.get("product_code", standardized_id) if medicine else standardized_id,
            "unit": medicine.get("unit", "") if medicine else "",
            "current_stock": quantity_added,
            "min_order_qty": medicine.get("standard_min_qty", 100) if medicine else 100,
            "last_updated": firestore.SERVER_TIMESTAMP,
        })

    db.collection("stock_in_logs").add({
        "clinic_id": clinic_id,
        "medicine_id": standardized_id,
        "item_name": standardized_name,
        "quantity_added": quantity_added,
        "quantity_received": quantity_added,
        "qty_received": quantity_added,
        "timestamp": datetime.utcnow()
    })

    return jsonify({
        "message": "Stock-in successful"
    })

@app.route('/stock_out', methods=['POST'])
def stock_out():

    data = request.get_json()
    print("🔥 STOCK OUT:", data)

    clinic_id = data.get("clinic_id")
    medicine_id = data.get("medicine_id")
    item_name = data.get("item_name")
    quantity_used = int(data.get("quantity_used", 0)) 

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    medicine = resolve_medicine(
        medicine_id=medicine_id,
        item_name=item_name,
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )

    if clinic_id is None or quantity_used is None or (not medicine and item_name is None):
        return jsonify({"error": "Missing data"}), 400

    quantity_used = int(quantity_used)  

    standardized_name = medicine["name"] if medicine else item_name
    standardized_id = medicine["medicine_id"] if medicine else medicine_id

    docs = get_inventory_docs_for_clinic(clinic_id)

    found = False

    for doc in docs:
        data_db = doc.to_dict()
        if not matches_medicine_reference(
            data_db,
            medicine_id=standardized_id,
            item_name=standardized_name,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        ):
            continue

        found = True
        current_stock = data_db.get("current_stock", 0)

        # ❗ Prevent negative stock
        if current_stock < quantity_used:
            return jsonify({
                "error": "Not enough stock"
            }), 400

        new_stock = current_stock - quantity_used

        db.collection("inventory").document(doc.id).update({
            "medicine_id": standardized_id,
            "item_name": standardized_name,
            "category": medicine.get("category", data_db.get("category", "")) if medicine else data_db.get("category", ""),
            "product_code": (
                medicine.get("product_code", medicine.get("medicine_id", standardized_id))
                if medicine else data_db.get("product_code", standardized_id)
            ),
            "unit": medicine.get("unit", data_db.get("unit", "")) if medicine else data_db.get("unit", ""),
            "current_stock": new_stock,
            "last_updated": firestore.SERVER_TIMESTAMP,
        })

    if not found:
        return jsonify({
            "error": "Item not found in inventory"
        }), 404

    db.collection("usage_logs").add({
        "clinic_id": clinic_id,
        "medicine_id": standardized_id,
        "item_name": standardized_name,
        "quantity_used": quantity_used,
        "qty_used": quantity_used,
        "timestamp": datetime.utcnow()
    })

    return jsonify({
        "message": "Stock-out successful"
    })

@app.route('/ai/forecast', methods=['GET'])
def ai_forecast():
    unavailable = ai_unavailable_response()
    if unavailable:
        return unavailable

    clinic_id = request.args.get('clinic_id')
    medicine_id = request.args.get('medicine_id')
    item_name = request.args.get('item_name')

    if not clinic_id or (not medicine_id and not item_name):
        return jsonify({"error": "Missing clinic_id and medicine reference"}), 400

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    requested_medicine = resolve_medicine(
        medicine_id=medicine_id,
        item_name=item_name,
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )

    docs = db.collection("usage_logs") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    usage_data = []
    for doc in docs:
        data = doc.to_dict()
        standardized = standardize_log_entry(
            data,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        if requested_medicine and standardized["medicine_id"] != requested_medicine["medicine_id"]:
            continue
        usage_data.append({
            "medicine_id": standardized["medicine_id"],
            "item_name": standardized["item_name"],
            "quantity_used": data.get("quantity_used", data.get("qty_used", 0)),
            "timestamp": data.get("timestamp")
        })

    forecast = generate_forecast(usage_data, predict_days=7)

    return jsonify({
        "clinic_id": clinic_id,
        "medicine_id": requested_medicine["medicine_id"] if requested_medicine else medicine_id,
        "item_name": requested_medicine["name"] if requested_medicine else item_name,
        "forecast_7_days": forecast
    })

@app.route('/ai/anomalies', methods=['GET'])
def ai_anomalies():
    unavailable = ai_unavailable_response()
    if unavailable:
        return unavailable

    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "Missing clinic_id"}), 400

    docs = db.collection("usage_logs") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    usage_data = []
    for doc in docs:
        data = doc.to_dict()
        standardized = standardize_log_entry(
            data,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        usage_data.append({
            "medicine_id": standardized["medicine_id"],
            "item_name": standardized["item_name"],
            "quantity_used": data.get("quantity_used", data.get("qty_used", 0)),
            "timestamp": data.get("timestamp")
        })

    # Group by item and detect anomalies
    anomalies_report = []
    item_groups = {}
    for entry in usage_data:
        item = entry['medicine_id'] or entry['item_name']
        if item not in item_groups:
            item_groups[item] = []
        item_groups[item].append(entry)
        
    for item, item_data in item_groups.items():
        anomalies = detect_anomalies(item_data)
        if anomalies:
            sample = item_data[0]
            anomalies_report.append({
                "medicine_id": sample.get("medicine_id", ""),
                "item_name": sample.get("item_name", item),
                "anomalies": anomalies
            })

    return jsonify({
        "clinic_id": clinic_id,
        "epidemic_warnings": anomalies_report
    })

@app.route('/ai/smart_inventory', methods=['GET'])
def ai_smart_inventory():
    unavailable = ai_unavailable_response()
    if unavailable:
        return unavailable

    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "Missing clinic_id"}), 400

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    # 1. High-Performance Bulk Load
    all_inv_docs = db.collection("inventory").stream()
    global_inv = {} # { clinic_id: { medicine_id: {stock, item_name} } }
    for doc in all_inv_docs:
        d = doc.to_dict()
        cid = d.get('clinic_id')
        standardized = standardize_inventory_entry(
            d,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        med_id = standardized["medicine_id"] or standardized["item_name"]
        if cid not in global_inv:
            global_inv[cid] = {}
        global_inv[cid][med_id] = {
            "current_stock": standardized["current_stock"],
            "item_name": standardized["item_name"],
            "medicine_id": standardized["medicine_id"],
        }

    # 1.5 Fetch Meteorological Data once
    weather_data = get_7_day_weather()

    # 2. Bulk Load Usage Logs
    all_usage_docs = db.collection("usage_logs").stream()
    global_usage = {} # { clinic_id: { medicine_id: [logs] } }
    for doc in all_usage_docs:
        d = doc.to_dict()
        cid = d.get('clinic_id')
        standardized = standardize_log_entry(
            d,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        med_id = standardized["medicine_id"] or standardized["item_name"]
        if cid not in global_usage:
            global_usage[cid] = {}
        if med_id not in global_usage[cid]:
            global_usage[cid][med_id] = []
        log_entry = dict(d)
        log_entry["medicine_id"] = standardized["medicine_id"]
        log_entry["item_name"] = standardized["item_name"]
        log_entry["quantity_used"] = d.get("quantity_used", d.get("qty_used", 0))
        global_usage[cid][med_id].append(log_entry)

    # 3. Process each item for the local clinic
    smart_list = []
    my_inventory = global_inv.get(clinic_id, {})

    for med_id, item_data in my_inventory.items():
        stock = item_data["current_stock"]
        item_name = item_data["item_name"]
        logs = global_usage.get(clinic_id, {}).get(med_id, [])
        anomalies = detect_anomalies(logs)
        metrics = calculate_smart_inventory(logs, stock, item_name=item_name, weather_data=weather_data)
        
        has_warning = len(anomalies) > 0
        
        # Cross-Clinic Balancing Logic
        transfer_candidates = []
        if metrics['recommend_order'] > 0:
            for other_clinic, other_items in global_inv.items():
                if other_clinic == clinic_id:
                    continue
                other_inventory = other_items.get(med_id)
                if other_inventory and other_inventory["current_stock"] > 0:
                    other_logs = global_usage.get(other_clinic, {}).get(med_id, [])
                    other_metrics = calculate_smart_inventory(
                        other_logs,
                        other_inventory["current_stock"],
                        item_name=item_name,
                        weather_data=weather_data,
                    )
                    if other_metrics['surplus_stock'] >= 20: # Only bother if they have a meaningful surplus > 20
                        transfer_candidates.append({
                            "clinic_id": other_clinic,
                            "surplus_stock": other_metrics['surplus_stock']
                        })

        # Sort transfer candidates by largest surplus
        transfer_candidates.sort(key=lambda x: x['surplus_stock'], reverse=True)

        smart_list.append({
            "medicine_id": item_data["medicine_id"],
            "item_name": item_name,
            "current_stock": stock,
            "run_out_days": metrics['run_out_days'],
            "run_out_date": metrics['run_out_date'],
            "recommend_order": metrics['recommend_order'],
            "surplus_stock": metrics['surplus_stock'],
            "forecast_7_days": metrics['forecast_7_days'],
            "has_epidemic_warning": has_warning,
            "anomalies": anomalies,
            "transfer_candidates": transfer_candidates,
            "weather_warning": metrics.get("weather_warning", "")
        })

    # Sort logic: 
    # Items with shortest run_out_days > 0 first.
    # If run_out_days == -1 (Safe), push to bottom.
    def sort_key(x):
        days = x['run_out_days']
        if days == -1: return 9999
        return days
        
    smart_list.sort(key=sort_key)

    return jsonify({
        "clinic_id": clinic_id,
        "smart_inventory": smart_list
    })

@app.route('/pkd/request_transfer', methods=['POST'])
def pkd_request_transfer():
    data = request.get_json()
    from_clinic = data.get('from_clinic')
    to_clinic = data.get('clinic_id') # The one making the request
    medicine_id = data.get('medicine_id')
    item_name = data.get('item_name')
    quantity = data.get('quantity')

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    medicine = resolve_medicine(
        medicine_id=medicine_id,
        item_name=item_name,
        medicines=medicines,
        medicine_lookup=medicine_lookup,
        match_index=match_index,
    )

    if not from_clinic or not to_clinic or not quantity or (not medicine and not item_name):
        return jsonify({"error": "Missing data"}), 400

    standardized_name = medicine["name"] if medicine else item_name
    standardized_id = medicine["medicine_id"] if medicine else medicine_id

    db.collection("interclinic_transfers").add({
        "from_clinic": from_clinic,
        "to_clinic": to_clinic,
        "medicine_id": standardized_id,
        "item_name": standardized_name,
        "quantity": int(quantity),
        "status": "Pending Acceptance",
        "timestamp": datetime.utcnow()
    })

    return jsonify({"message": f"Transfer request for {quantity} {standardized_name} sent to {from_clinic}!"})

@app.route('/pkd/request_order', methods=['POST'])
def pkd_request_order():
    data = request.get_json()
    clinic_id = data.get('clinic_id')
    orders = data.get('orders', []) # list of {"item_name": "x", "quantity": int}

    if not clinic_id or not orders:
        return jsonify({"error": "Missing data"}), 400

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    standardized_orders = []
    for item in orders:
        medicine = resolve_medicine(
            medicine_id=item.get("medicine_id"),
            item_name=item.get("item_name"),
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        quantity = item.get("quantity", item.get("qty", item.get("suggested_qty", 0)))
        standardized_orders.append({
            "medicine_id": medicine["medicine_id"] if medicine else item.get("medicine_id", ""),
            "item_name": medicine["name"] if medicine else item.get("item_name", "Unknown Medicine"),
            "quantity": quantity,
        })

    db.collection("pkd_orders").add({
        "clinic_id": clinic_id,
        "orders": standardized_orders,
        "status": "Pending Verification",
        "timestamp": datetime.utcnow()
    })

    return jsonify({"message": "Order sent to PKD!"})

@app.route('/generate_order', methods=['POST'])
def generate_order():
    data = request.json

    clinic_id = data.get("clinic_id")
    items = data.get("items")

    if not clinic_id or not items:
        return jsonify({"error": "Missing data"}), 400

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    standardized_items = [
        standardize_order_item(
            item,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        for item in items
    ]

    order_data = {
        "clinic_id": clinic_id,
        "items": standardized_items,
        "status": "PENDING",
        "created_at": datetime.utcnow()
    }

    db.collection("orders").add(order_data)
    db.collection("clinics").document(clinic_id).update({
        "has_pending_order": True
    })

    return jsonify({
        "message": "Order generated successfully"
    })

@app.route('/orders', methods=['GET'])
def get_orders():
    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id required"}), 400

    docs = db.collection("orders") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    medicines, medicine_lookup, match_index = get_medicine_catalog()
    orders = []

    for doc in docs:
        data = doc.to_dict()
        standardized_items = [
            standardize_order_item(
                item,
                medicines=medicines,
                medicine_lookup=medicine_lookup,
                match_index=match_index,
            )
            for item in data.get("items", [])
        ]

        orders.append({
            "id": doc.id,
            "items": standardized_items,
            "status": data.get("status", "PENDING"),
            "created_at": str(data.get("created_at"))
        })

    return jsonify({"orders": orders})

@app.route('/complete_order', methods=['POST'])
def complete_order():
    data = request.json
    clinic_id = data.get("clinic_id")

    if not clinic_id:
        return jsonify({"error": "clinic_id required"}), 400

    orders = db.collection("orders") \
        .where("clinic_id", "==", clinic_id) \
        .where("status", "==", "SUBMITTED") \
        .stream()

    medicines, medicine_lookup, match_index = get_medicine_catalog()

    for doc in orders:
        order_data = doc.to_dict()
        items = order_data.get("items", [])

        # 🔥 UPDATE INVENTORY HERE
        for item in items:
            standardized_item = standardize_order_item(
                item,
                medicines=medicines,
                medicine_lookup=medicine_lookup,
                match_index=match_index,
            )
            item_name = standardized_item.get("item_name")
            medicine_id = standardized_item.get("medicine_id")
            qty = standardized_item.get("qty", 0)

            inv_docs = get_inventory_docs_for_clinic(clinic_id)
            matched_inventory = False

            for inv_doc in inv_docs:
                inv_data = inv_doc.to_dict()
                if not matches_medicine_reference(
                    inv_data,
                    medicine_id=medicine_id,
                    item_name=item_name,
                    medicines=medicines,
                    medicine_lookup=medicine_lookup,
                    match_index=match_index,
                ):
                    continue

                matched_inventory = True
                current_stock = inv_data.get("current_stock", 0)

                inv_doc.reference.update({
                    "medicine_id": medicine_id,
                    "item_name": item_name,
                    "category": medicine_lookup.get(medicine_id, {}).get("category", inv_data.get("category", "")),
                    "product_code": medicine_lookup.get(medicine_id, {}).get("product_code", inv_data.get("product_code", medicine_id)),
                    "unit": medicine_lookup.get(medicine_id, {}).get("unit", inv_data.get("unit", "")),
                    "current_stock": current_stock + qty,
                    "last_updated": firestore.SERVER_TIMESTAMP,
                })
                # 📝 LOG STOCK IN
                db.collection("stock_in_logs").add({
                    "clinic_id": clinic_id,
                    "medicine_id": medicine_id,
                    "item_name": item_name,
                    "qty_added": qty,
                    "quantity_received": qty,
                    "qty_received": qty,
                    "timestamp": datetime.utcnow()
                })

            if not matched_inventory:
                db.collection("inventory").add({
                    "clinic_id": clinic_id,
                    "medicine_id": medicine_id,
                    "item_name": item_name,
                    "category": medicine_lookup.get(medicine_id, {}).get("category", ""),
                    "product_code": medicine_lookup.get(medicine_id, {}).get("product_code", medicine_id),
                    "unit": medicine_lookup.get(medicine_id, {}).get("unit", ""),
                    "current_stock": qty,
                    "min_order_qty": medicine_lookup.get(medicine_id, {}).get("standard_min_qty", 100),
                    "last_updated": firestore.SERVER_TIMESTAMP,
                })

        # ✅ Mark order Received
        doc.reference.update({
            "status": "RECEIVED",
            "items": [
                standardize_order_item(
                    item,
                    medicines=medicines,
                    medicine_lookup=medicine_lookup,
                    match_index=match_index,
                )
                for item in items
            ],
        })

    # 🔁 Reset flag
    db.collection("clinics").document(clinic_id).update({
        "has_pending_order": False
    })

    return jsonify({"message": "Order received & inventory updated"})

@app.route('/update_order_status', methods=['POST'])
def update_order_status():
    data = request.json

    order_id = data.get("order_id")
    new_status = data.get("status")

    if not order_id or not new_status:
        return jsonify({"error": "Missing data"}), 400

    db.collection("orders").document(order_id).update({
        "status": new_status
    })

    if new_status == "SUBMITTED":
        order = db.collection("orders").document(order_id).get().to_dict()
        clinic_id = order.get("clinic_id")

        db.collection("clinics").document(clinic_id).update({
            "has_pending_order": True
        })

    return jsonify({"message": "Order status updated"})
    return jsonify({"message": "Order status updated"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
