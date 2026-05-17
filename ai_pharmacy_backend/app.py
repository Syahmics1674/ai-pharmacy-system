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
import math
import requests as ext_requests

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

# ============================================================
# CLINIC NETWORK — Coordinates, Haversine, Weather
# ============================================================

CLINIC_COORDINATES = {
    'clinicA': {'lat': 3.1336, 'lng': 101.6869, 'name': 'Kuala Lumpur Health Clinic_A', 'area': 'KL Sentral'},
    'clinicB': {'lat': 3.1623, 'lng': 101.7024, 'name': 'Kuala Lumpur Health Clinic_B', 'area': 'Chow Kit'},
    'clinicC': {'lat': 3.1290, 'lng': 101.6740, 'name': 'Kuala Lumpur Health Clinic_C', 'area': 'Bangsar'},
    'clinicD': {'lat': 3.1569, 'lng': 101.7655, 'name': 'Kuala Lumpur Health Clinic_D', 'area': 'Ampang'},
    'clinicE': {'lat': 3.0565, 'lng': 101.5850, 'name': 'Kuala Lumpur Health Clinic_E', 'area': 'Subang'},
}

def haversine_km(lat1, lng1, lat2, lng2):
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlng/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return round(R * c, 1)

def get_clinic_weather(lat, lng):
    url = (
        f"https://api.open-meteo.com/v1/forecast"
        f"?latitude={lat}&longitude={lng}"
        f"&current=temperature_2m,precipitation,weathercode"
        f"&timezone=auto"
    )
    try:
        resp = ext_requests.get(url, timeout=5)
        if resp.status_code == 200:
            current = resp.json().get('current', {})
            temp = current.get('temperature_2m')
            rain = current.get('precipitation', 0)
            wcode = current.get('weathercode', 0)
            if wcode == 0:
                condition = 'Clear Sky'
            elif wcode <= 3:
                condition = 'Partly Cloudy'
            elif wcode <= 67:
                condition = 'Rainy'
            elif wcode <= 77:
                condition = 'Snowy'
            elif wcode <= 82:
                condition = 'Heavy Rain'
            else:
                condition = 'Thunderstorm'
            return {'temperature': temp, 'rain_mm': rain, 'condition': condition}
    except Exception as e:
        print(f"Clinic weather fetch failed: {e}")
    return {'temperature': None, 'rain_mm': 0, 'condition': 'Unknown'}

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


def count_orders_for_clinic(clinic_id, status):
    docs = db.collection("orders") \
             .where("clinic_id", "==", clinic_id) \
             .where("status", "==", status) \
             .stream()

    return sum(1 for _ in docs)


def coerce_int(value, default=0):
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if value is None:
        return default
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return default


def parse_timestamp(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if hasattr(value, "to_datetime"):
        try:
            return value.to_datetime()
        except Exception:
            return None
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def extract_log_quantity(data, quantity_keys):
    for key in quantity_keys:
        if key in data:
            return coerce_int(data.get(key))
    return 0


def risk_level_from_score(score):
    if score >= 3:
        return "HIGH"
    if score >= 2:
        return "MEDIUM"
    return "SAFE"


def format_risk_reason(reason, fallback="Operating within safe limits"):
    return reason or fallback


def build_usage_summary_for_clinic(clinic_id, medicines, medicine_lookup, match_index):
    usage_docs = db.collection("usage_logs") \
        .where("clinic_id", "==", clinic_id) \
        .stream()

    now = datetime.utcnow()
    monthly_usage_by_medicine = defaultdict(int)
    weekly_usage_by_medicine = defaultdict(int)
    monthly_log_count = 0

    for doc in usage_docs:
        data = doc.to_dict()
        standardized = standardize_log_entry(
            data,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        quantity = extract_log_quantity(data, ["quantity_used", "qty_used"])
        timestamp = parse_timestamp(data.get("timestamp") or data.get("created_at"))

        if not timestamp:
            continue

        if (now - timestamp).days <= 30:
            monthly_log_count += 1
            monthly_usage_by_medicine[standardized["medicine_id"]] += quantity

        if (now - timestamp).days <= 7:
            weekly_usage_by_medicine[standardized["medicine_id"]] += quantity

    return {
        "monthly_usage_by_medicine": monthly_usage_by_medicine,
        "weekly_usage_by_medicine": weekly_usage_by_medicine,
        "monthly_log_count": monthly_log_count,
    }


def analyze_clinic_risk(clinic, medicines, medicine_lookup, match_index):
    clinic_id = clinic["clinic_id"]
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
    usage_summary = build_usage_summary_for_clinic(
        clinic_id,
        medicines,
        medicine_lookup,
        match_index,
    )
    monthly_usage_by_medicine = usage_summary["monthly_usage_by_medicine"]

    pending_orders = count_orders_for_clinic(clinic_id, "PENDING")
    submitted_orders = count_orders_for_clinic(clinic_id, "SUBMITTED")

    low_stock_count = 0
    high_depletion_count = 0
    stockout_7d_count = 0
    stockout_14d_count = 0
    latest_inventory_update = None
    top_pressure_reason = ""
    top_pressure_score = -1.0

    for item in inventory_items:
        current_stock = coerce_int(item.get("current_stock"))
        min_order_qty = max(coerce_int(item.get("min_order_qty"), 100), 1)
        medicine_id = item.get("medicine_id", "")
        monthly_used = monthly_usage_by_medicine.get(medicine_id, 0)
        daily_usage = monthly_used / 30 if monthly_used > 0 else 0
        depletion_ratio = current_stock / min_order_qty if min_order_qty else 1
        item_last_updated = parse_timestamp(item.get("last_updated"))

        if item_last_updated and (
            latest_inventory_update is None or item_last_updated > latest_inventory_update
        ):
            latest_inventory_update = item_last_updated

        if current_stock <= 0 or depletion_ratio < 0.75:
            low_stock_count += 1

        if daily_usage >= 3:
            high_depletion_count += 1

        if daily_usage > 0:
            run_out_days = current_stock / daily_usage if current_stock > 0 else 0
            if run_out_days <= 7:
                stockout_7d_count += 1
            elif run_out_days <= 14:
                stockout_14d_count += 1

            pressure_score = (daily_usage * 2) + max(0, (1 - depletion_ratio) * 10)
            if pressure_score > top_pressure_score:
                top_pressure_score = pressure_score
                top_pressure_reason = (
                    f"{item.get('item_name', 'Unknown medicine')} is depleting quickly"
                )

    risk_score = 1
    risk_reason = ""

    if stockout_7d_count > 0:
        risk_score = 3
        risk_reason = f"{stockout_7d_count} medicines may stock out within 7 days"
    elif pending_orders >= 3:
        risk_score = 3
        risk_reason = "Multiple pending orders are still unresolved"
    elif low_stock_count >= 4:
        risk_score = 3
        risk_reason = f"{low_stock_count} medicines are below safe stock levels"
    elif stockout_14d_count > 0:
        risk_score = 2
        risk_reason = f"{stockout_14d_count} medicines may stock out within 14 days"
    elif high_depletion_count >= 3:
        risk_score = 2
        risk_reason = "Medicine depletion is accelerating across several items"
    elif pending_orders > 0:
        risk_score = 2
        risk_reason = "Pending orders still need operational follow-up"
    elif top_pressure_reason:
        risk_reason = top_pressure_reason

    risk_level = risk_level_from_score(risk_score)
    if risk_level == "HIGH":
        next_order_date = datetime.utcnow() + timedelta(days=2)
    elif risk_level == "MEDIUM":
        next_order_date = datetime.utcnow() + timedelta(days=5)
    else:
        next_order_date = datetime.utcnow() + timedelta(days=12)

    ai_status = {
        "HIGH": "Urgent attention needed",
        "MEDIUM": "Monitor closely",
        "SAFE": "Stable",
    }[risk_level]

    return {
        "clinic_id": clinic_id,
        "name": clinic["name"],
        "district": clinic.get("district", ""),
        "route_id": clinic["route_id"],
        "risk_level": risk_level,
        "risk_score": risk_score,
        "risk_reason": format_risk_reason(risk_reason),
        "pending_orders": pending_orders,
        "submitted_orders": submitted_orders,
        "next_order_date": next_order_date.strftime("%Y-%m-%d"),
        "last_inventory_update": (
            latest_inventory_update.isoformat() if latest_inventory_update else None
        ),
        "low_stock_count": low_stock_count,
        "high_depletion_count": high_depletion_count,
        "stockout_7d_count": stockout_7d_count,
        "stockout_14d_count": stockout_14d_count,
        "ai_status": ai_status,
        "monthly_usage_logs": usage_summary["monthly_log_count"],
    }


def build_pkd_clinic_analysis(district):
    medicines, medicine_lookup, match_index = get_medicine_catalog()
    clinics = get_district_clinics(district)
    analysis = []

    for clinic in clinics:
        clinic_with_context = {
            **clinic,
            "district": district,
        }
        analysis.append(
            analyze_clinic_risk(
                clinic_with_context,
                medicines,
                medicine_lookup,
                match_index,
            )
        )

    risk_priority = {"HIGH": 0, "MEDIUM": 1, "SAFE": 2}
    analysis.sort(
        key=lambda clinic: (
            risk_priority.get(clinic["risk_level"], 3),
            clinic["name"].lower(),
        )
    )
    return analysis


def build_pkd_top_medicines(district):
    medicines, medicine_lookup, match_index = get_medicine_catalog()
    clinics = get_district_clinics(district)
    usage_by_medicine = defaultdict(int)

    for clinic in clinics:
        usage_docs = db.collection("usage_logs") \
            .where("clinic_id", "==", clinic["clinic_id"]) \
            .stream()

        for doc in usage_docs:
            data = doc.to_dict()
            standardized = standardize_log_entry(
                data,
                medicines=medicines,
                medicine_lookup=medicine_lookup,
                match_index=match_index,
            )
            quantity = extract_log_quantity(data, ["quantity_used", "qty_used"])
            if standardized["medicine_id"]:
                usage_by_medicine[standardized["medicine_id"]] += quantity

    top_items = []
    for rank, (medicine_id, total_used) in enumerate(
        sorted(
            usage_by_medicine.items(),
            key=lambda entry: entry[1],
            reverse=True,
        )[:5],
        start=1,
    ):
        medicine = medicine_lookup.get(medicine_id, {})
        top_items.append({
            "rank": rank,
            "medicine_id": medicine_id,
            "item_name": medicine.get("name", medicine_id),
            "category": medicine.get("category", "Uncategorized"),
            "usage_quantity": total_used,
        })

    return top_items


def build_pkd_route_analysis(district, clinic_analysis=None):
    clinic_analysis = clinic_analysis or build_pkd_clinic_analysis(district)
    grouped_routes = defaultdict(list)

    for clinic in clinic_analysis:
        grouped_routes[clinic["route_id"]].append(clinic)

    routes = []
    for route_id, route_clinics in grouped_routes.items():
        clinic_count = len(route_clinics)
        pending_orders = sum(clinic["pending_orders"] for clinic in route_clinics)
        monthly_usage_logs = sum(
            clinic["monthly_usage_logs"] for clinic in route_clinics
        )
        average_risk_score = round(
            sum(clinic["risk_score"] for clinic in route_clinics) / clinic_count,
            2,
        ) if clinic_count else 0
        high_risk_clusters = sum(
            1 for clinic in route_clinics if clinic["risk_level"] == "HIGH"
        )
        delivery_priority_score = round(
            (average_risk_score * 20) + (pending_orders * 3) + (high_risk_clusters * 10),
            1,
        )

        routes.append({
            "route_id": route_id,
            "clinic_count": clinic_count,
            "total_clinics": clinic_count,
            "average_risk_level": risk_level_from_score(round(average_risk_score)),
            "average_risk_score": average_risk_score,
            "pending_orders": pending_orders,
            "delivery_priority_score": delivery_priority_score,
            "stockout_risk_clusters": high_risk_clusters,
            "high_risk_clinics": high_risk_clusters,
            "total_monthly_usage_logs": monthly_usage_logs,
            "urgent_date": min(
                clinic["next_order_date"] for clinic in route_clinics
            ) if route_clinics else None,
            "clinics": route_clinics,
        })

    routes.sort(key=lambda route: route["delivery_priority_score"], reverse=True)
    return routes


def build_pkd_insights(district, clinic_analysis=None, route_analysis=None, top_medicines=None):
    clinic_analysis = clinic_analysis or build_pkd_clinic_analysis(district)
    route_analysis = route_analysis or build_pkd_route_analysis(
        district,
        clinic_analysis=clinic_analysis,
    )
    top_medicines = top_medicines or build_pkd_top_medicines(district)

    insights = []

    if route_analysis:
        top_route = route_analysis[0]
        insights.append(
            f"{top_route['route_id']} should be prioritized first with a delivery score of "
            f"{top_route['delivery_priority_score']}."
        )

    clinics_stocking_out = sum(
        1 for clinic in clinic_analysis if clinic["stockout_7d_count"] > 0
    )
    if clinics_stocking_out:
        insights.append(
            f"{clinics_stocking_out} clinics may stock out within 7 days if no action is taken."
        )

    if top_medicines:
        top_medicine = top_medicines[0]
        insights.append(
            f"{top_medicine['item_name']} is the top dispensed medicine in {district} "
            f"with {top_medicine['usage_quantity']} recent uses."
        )

    high_risk_clinics = [
        clinic["name"] for clinic in clinic_analysis if clinic["risk_level"] == "HIGH"
    ]
    if high_risk_clinics:
        insights.append(
            f"High-risk clinics needing close monitoring: {', '.join(high_risk_clinics[:3])}."
        )

    return insights[:4]


def build_pkd_overview(district):
    medicines, _, _ = get_medicine_catalog()
    clinic_analysis = build_pkd_clinic_analysis(district)
    route_analysis = build_pkd_route_analysis(
        district,
        clinic_analysis=clinic_analysis,
    )
    top_medicines = build_pkd_top_medicines(district)
    insights = build_pkd_insights(
        district,
        clinic_analysis=clinic_analysis,
        route_analysis=route_analysis,
        top_medicines=top_medicines,
    )

    total_clinics = len(clinic_analysis)
    clinics_at_risk = sum(
        1 for clinic in clinic_analysis if clinic["risk_level"] in {"HIGH", "MEDIUM"}
    )
    pending_orders = sum(clinic["pending_orders"] for clinic in clinic_analysis)
    submitted_orders = sum(clinic["submitted_orders"] for clinic in clinic_analysis)
    total_medicines_tracked = len(medicines)
    monthly_usage_logs = sum(clinic["monthly_usage_logs"] for clinic in clinic_analysis)
    active_routes = len(route_analysis)

    risk_counts = {
        "safe": sum(1 for clinic in clinic_analysis if clinic["risk_level"] == "SAFE"),
        "medium": sum(1 for clinic in clinic_analysis if clinic["risk_level"] == "MEDIUM"),
        "high": sum(1 for clinic in clinic_analysis if clinic["risk_level"] == "HIGH"),
    }

    return {
        "district": district,
        "total_clinics": total_clinics,
        "clinics_at_risk": clinics_at_risk,
        "high_risk_clinics": risk_counts["high"],
        "pending_orders": pending_orders,
        "submitted_orders": submitted_orders,
        "total_medicines_tracked": total_medicines_tracked,
        "monthly_usage_logs": monthly_usage_logs,
        "active_routes": active_routes,
        "risk_counts": risk_counts,
        "top_medicines": top_medicines,
        "insights": insights,
        "trend": {
            "high_risk": [
                max(risk_counts["high"] - 2, 0),
                max(risk_counts["high"] - 1, 0),
                risk_counts["high"],
            ],
            "orders": [
                max(submitted_orders - 4, 0),
                max(submitted_orders - 2, 0),
                submitted_orders,
            ],
        },
    }

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

    overview = build_pkd_overview(district)

    return jsonify({
        "total_clinics": overview["total_clinics"],
        "high_risk_clinics": overview["high_risk_clinics"],
        "pending_orders": overview["pending_orders"],
        "submitted_orders": overview["submitted_orders"]
    })


@app.route('/pkd_clinic_analysis', methods=['GET'])
def pkd_clinic_analysis():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    clinic_analysis = build_pkd_clinic_analysis(district)

    return jsonify({
        "clinics": clinic_analysis
    })


@app.route('/pkd_route_analysis', methods=['GET'])
def pkd_route_analysis():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    route_results = build_pkd_route_analysis(district)

    return jsonify({"routes": route_results})


@app.route('/pkd_alerts', methods=['GET'])
def pkd_alerts():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    return jsonify({"alerts": build_pkd_insights(district)})


@app.route('/pkd/overview', methods=['GET'])
def pkd_overview():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    return jsonify(build_pkd_overview(district))


@app.route('/pkd/clinic_risks', methods=['GET'])
def pkd_clinic_risks():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    return jsonify({
        "district": district,
        "clinics": build_pkd_clinic_analysis(district),
    })


@app.route('/pkd/routes', methods=['GET'])
def pkd_routes():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    return jsonify({
        "district": district,
        "routes": build_pkd_route_analysis(district),
    })


@app.route('/pkd/top_medicines', methods=['GET'])
def pkd_top_medicines():
    district = (request.args.get('district') or '').strip()

    if not district:
        return jsonify({"error": "district is required"}), 400

    return jsonify({
        "district": district,
        "medicines": build_pkd_top_medicines(district),
    })

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

@app.route('/clinic_network', methods=['GET'])
def clinic_network():
    clinic_id = request.args.get('clinic_id')

    if not clinic_id or clinic_id not in CLINIC_COORDINATES:
        return jsonify({"error": "Invalid or missing clinic_id"}), 400

    my_info = CLINIC_COORDINATES[clinic_id]

    result = []
    for cid, info in CLINIC_COORDINATES.items():
        is_self = (cid == clinic_id)
        dist = 0.0 if is_self else haversine_km(
            my_info['lat'], my_info['lng'],
            info['lat'], info['lng']
        )
        weather = get_clinic_weather(info['lat'], info['lng'])
        result.append({
            'clinic_id': cid,
            'name': info['name'],
            'area': info['area'],
            'lat': info['lat'],
            'lng': info['lng'],
            'distance_km': dist,
            'is_self': is_self,
            'weather': weather
        })

    # Sort: own clinic first, then by distance
    result.sort(key=lambda x: (0 if x['is_self'] else 1, x['distance_km']))

    return jsonify({
        'clinic_id': clinic_id,
        'my_location': my_info,
        'clinics': result
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
