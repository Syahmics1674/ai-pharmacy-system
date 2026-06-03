from flask import Flask, request, jsonify
from consolidation import consolidate_order_date
from firebase_config import db
from services.supabase_service import (
    get_joined_inventory,
    update_inventory_quantity,
    fetch_dispense_transactions,
    fetch_medicines,
    fetch_clinic,
)
from migrate_inventory import (
    build_match_index,
    list_medicines,
    match_medicine,
)
from datetime import timedelta
from datetime import datetime
from datetime import timezone
from collections import defaultdict
from flask_cors import CORS  
import sys
import os
import time
import threading
import logging

from routes.supabase_routes import supabase_bp
import math
import google.api_core.exceptions
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

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)
app.register_blueprint(supabase_bp)

# In-memory TTL cache
_cache = {}
_cache_hits = 0
_cache_misses = 0
_firestore_reads = 0

def count_firestore_read(inc=1):
    global _firestore_reads
    _firestore_reads += inc

def cached(ttl_seconds=60):
    def decorator(f):
        def wrapped(*args, **kwargs):
            try:
                path = request.path
                qs = request.query_string.decode('utf-8') if request.query_string else ''
                cache_key = f"{path}:{qs}"
            except RuntimeError:
                cache_key = f"{f.__name__}:{args}:{kwargs}"
            cached_data = cache_get(cache_key)
            if cached_data is not None:
                return cached_data
            result = f(*args, **kwargs)
            cache_set(cache_key, result, ttl_seconds)
            return result
        wrapped.__name__ = f.__name__
        return wrapped
    return decorator

CACHE_TTL = 300  # 5 minutes

def cache_get(key):
    entry = _cache.get(key)
    if entry and time.time() - entry["time"] < entry["ttl"]:
        return entry["data"]
    return None

def cache_set(key, data, ttl_seconds=None):
    _cache[key] = {"data": data, "time": time.time(), "ttl": ttl_seconds or CACHE_TTL}

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

FALLBACK_OVERALL_USAGE = {
    "daily": [10, 12, 8, 15, 20, 18, 22],
    "weekly": [80, 95, 70, 110],
    "monthly": [300, 420, 390]
}

FALLBACK_STOCK_SUMMARY = {
    "critical": 3,
    "low": 5,
    "safe": 12
}

FALLBACK_INSIGHT_MESSAGE = {
    "message": "Paracetamol demand is increasing. Consider increasing stock."
}


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


def get_usage_logs_for_clinic(clinic_id):
    query = db.collection("usage_logs")

    if clinic_id:
        query = query.where("clinic_id", "==", clinic_id)

    logs = []
    for doc in query.stream():
        data = doc.to_dict()
        logs.append({
            "item_name": data.get("item_name"),
            "quantity_used": int(data.get("quantity_used", 0)),
            "timestamp": data.get("timestamp")
        })

    return logs


def get_inventory_for_clinic(clinic_id):
    joined = get_joined_inventory(clinic_id=clinic_id)
    items = []
    for item in joined:
        items.append({
            "item_name": (
                item.get("full_brand_name")
                or item.get("brand_name")
                or item.get("match_name")
                or item.get("item_code", "")
            ),
            "current_stock": int(item.get("quantity", 0)),
        })
    return items


def build_overall_usage_payload(logs):
    dated_logs = [log for log in logs if log.get("timestamp")]
    if len(dated_logs) < 7:
        return FALLBACK_OVERALL_USAGE

    today = datetime.utcnow().date()
    daily = []
    for offset in range(6, -1, -1):
        target_date = today - timedelta(days=offset)
        total = sum(
            log["quantity_used"]
            for log in dated_logs
            if log["timestamp"].date() == target_date
        )
        daily.append(total)

    weekly = []
    for week_index in range(3, -1, -1):
        end_date = today - timedelta(days=week_index * 7)
        start_date = end_date - timedelta(days=6)
        total = sum(
            log["quantity_used"]
            for log in dated_logs
            if start_date <= log["timestamp"].date() <= end_date
        )
        weekly.append(total)

    monthly = []
    month_keys = []
    for month_offset in range(2, -1, -1):
        month_anchor = today.month - month_offset
        year = today.year
        while month_anchor <= 0:
            month_anchor += 12
            year -= 1
        month_keys.append((year, month_anchor))

    for year, month in month_keys:
        total = sum(
            log["quantity_used"]
            for log in dated_logs
            if log["timestamp"].year == year and log["timestamp"].month == month
        )
        monthly.append(total)

    if sum(daily) == 0 and sum(weekly) == 0 and sum(monthly) == 0:
        return FALLBACK_OVERALL_USAGE

    return {
        "daily": daily,
        "weekly": weekly,
        "monthly": monthly
    }


def dispense_txns_to_usage_list(dispense_txns):
    if not dispense_txns:
        return []

    medicines = fetch_medicines()
    medicine_map = {}
    for m in medicines:
        code = m.get("item_code")
        if code:
            medicine_map[code] = (
                m.get("full_brand_name")
                or m.get("brand_name")
                or m.get("match_name")
                or code
            )

    usage = []
    for txn in dispense_txns:
        ts = txn.get("local_created_at")
        qty = abs(int(txn.get("quantity_change", 0)))
        if not ts or qty == 0:
            continue
        code = txn.get("item_code", "")
        name = medicine_map.get(code, txn.get("matched_name", code))
        try:
            parsed_ts = datetime.fromisoformat(ts)
        except (ValueError, TypeError):
            continue
        usage.append({
            "item_name": name,
            "quantity_used": qty,
            "timestamp": parsed_ts,
        })

    return usage


def build_stock_summary_payload(inventory_items):
    if not inventory_items:
        return FALLBACK_STOCK_SUMMARY

    critical = 0
    low = 0
    safe = 0

    for item in inventory_items:
        stock = item["current_stock"]
        if stock < 20:
            critical += 1
        elif stock < 50:
            low += 1
        else:
            safe += 1

    return {
        "critical": critical,
        "low": low,
        "safe": safe
    }


def build_top_products_from_dispense(dispense_txns):
    if not dispense_txns:
        return []

    medicines = fetch_medicines()
    medicine_map = {}
    for m in medicines:
        code = m.get("item_code")
        if code:
            medicine_map[code] = (
                m.get("full_brand_name")
                or m.get("brand_name")
                or m.get("match_name")
                or code
            )

    totals = {}
    for txn in dispense_txns:
        code = txn.get("item_code")
        if not code:
            continue
        name = medicine_map.get(code, txn.get("matched_name", code))
        totals[name] = totals.get(name, 0) + 1

    if not totals:
        return []

    ranked = sorted(
        ({"item_name": name, "total_used": count} for name, count in totals.items()),
        key=lambda x: x["total_used"],
        reverse=True,
    )

    return ranked[:5]


def build_insight_message_payload(stock_summary, top_products):
    if not top_products:
        return FALLBACK_INSIGHT_MESSAGE

    top_item = top_products[0]["item_name"]
    critical = stock_summary.get("critical", 0)
    low = stock_summary.get("low", 0)

    if critical > 0:
        return {
            "message": (
                f"{top_item} demand is rising while {critical} items are already "
                "critical. Consider urgent replenishment."
            )
        }

    if low > 0:
        return {
            "message": (
                f"{top_item} remains one of the most dispensed products. "
                "Monitor low stock items and plan the next replenishment soon."
            )
        }

    return {
        "message": (
            f"{top_item} leads current usage, but overall stock levels look stable."
        )
    }


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
        return ensure_utc_datetime(value)
    if hasattr(value, "to_datetime"):
        try:
            return ensure_utc_datetime(value.to_datetime())
        except Exception:
            return None
    if isinstance(value, str):
        try:
            return ensure_utc_datetime(
                datetime.fromisoformat(value.replace("Z", "+00:00"))
            )
        except ValueError:
            return None
    return None


def ensure_utc_datetime(value):
    if value is None or not isinstance(value, datetime):
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def utc_now():
    return datetime.now(timezone.utc)


def days_since(timestamp, reference=None):
    normalized_timestamp = ensure_utc_datetime(timestamp)
    if normalized_timestamp is None:
        return None

    normalized_reference = ensure_utc_datetime(reference or utc_now())
    if normalized_reference is None:
        return None

    return (normalized_reference - normalized_timestamp).days


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

    now = utc_now()
    monthly_usage_by_medicine = defaultdict(int)
    weekly_usage_by_medicine = defaultdict(int)
    monthly_log_count = 0

    for doc in usage_docs:
        data = doc.to_dict()
        if not isinstance(data, dict):
            continue

        standardized = standardize_log_entry(
            data,
            medicines=medicines,
            medicine_lookup=medicine_lookup,
            match_index=match_index,
        )
        quantity = extract_log_quantity(data, ["quantity_used", "qty_used"])
        timestamp = parse_timestamp(data.get("timestamp") or data.get("created_at"))

        if not timestamp or not standardized["medicine_id"] or quantity <= 0:
            continue

        age_in_days = days_since(timestamp, now)
        if age_in_days is None or age_in_days < 0:
            continue

        if age_in_days <= 30:
            monthly_log_count += 1
            monthly_usage_by_medicine[standardized["medicine_id"]] += quantity

        if age_in_days <= 7:
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
    current_time = utc_now()
    if risk_level == "HIGH":
        next_order_date = current_time + timedelta(days=2)
    elif risk_level == "MEDIUM":
        next_order_date = current_time + timedelta(days=5)
    else:
        next_order_date = current_time + timedelta(days=12)

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
    start = time.time()
    medicines, medicine_lookup, match_index = get_medicine_catalog()
    clinics = get_district_clinics(district)
    usage_by_medicine = defaultdict(int)

    thirty_days_ago = utc_now() - timedelta(days=30)
    total_logs_read = 0
    MAX_LOGS = 500

    for clinic in clinics:
        if total_logs_read >= MAX_LOGS:
            break

        try:
            usage_docs = db.collection("usage_logs") \
                .where("clinic_id", "==", clinic["clinic_id"]) \
                .limit(MAX_LOGS) \
                .stream()
        except google.api_core.exceptions.ResourceExhausted:
            print(f"[PKD] Firestore quota error reading usage_logs for {clinic['clinic_id']}")
            continue

        for doc in usage_docs:
            if total_logs_read >= MAX_LOGS:
                break

            data = doc.to_dict()
            timestamp = parse_timestamp(data.get("timestamp") or data.get("created_at"))
            if not timestamp or timestamp < thirty_days_ago:
                continue

            standardized = standardize_log_entry(
                data,
                medicines=medicines,
                medicine_lookup=medicine_lookup,
                match_index=match_index,
            )
            quantity = extract_log_quantity(data, ["quantity_used", "qty_used"])
            if standardized["medicine_id"]:
                usage_by_medicine[standardized["medicine_id"]] += quantity
            total_logs_read += 1

    elapsed = time.time() - start
    print(f"[PKD] top_medicines district={district} logs_read={total_logs_read} time={elapsed:.3f}s")

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


@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    user_id = data.get("user_id") or data.get("username")
    password = data.get("password")
    if not user_id or not password:
        return jsonify({"success": False, "error": "Missing credentials"}), 400

    print(f"[LOGIN] Attempting login for user_id={user_id}")

    docs = db.collection("users") \
        .where("user_id", "==", user_id) \
        .where("password", "==", password) \
        .stream()

    user = None

    for doc in docs:
        user = doc.to_dict()
        break

    if not user:
        return jsonify({
            "success": False,
            "error": "Invalid credentials"
        }), 401

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


@app.route('/clinic_info', methods=['GET'])
@cached(ttl_seconds=300)
def clinic_info():
    clinic_id = request.args.get('clinic_id')
    try:
        doc = db.collection("clinics").document(clinic_id).get()
        if not doc.exists:
            return jsonify({"error": "Clinic not found"}), 404
        data = doc.to_dict()
        return jsonify({
            "clinic_id": clinic_id,
            "clinic_name": data.get("name", clinic_id),
            "district": data.get("district", "")
        })
    except Exception as e:
        return jsonify({"error": f"Clinic info failed: {str(e)}"}), 500


@app.route('/consolidate', methods=['GET'])
@cached(ttl_seconds=180)
def consolidate():
    clinic_id = request.args.get('clinic_id')
    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400
    try:
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
        malaysia_time = result["date"] + timedelta(hours=8)
        return jsonify({
            "clinic_id": clinic_id,
            "consolidated_date": malaysia_time.strftime("%Y-%m-%d"),
            "based_on": result["based_on"],
            "summary": result.get("summary", {}),
            "most_urgent_clinic": result.get("most_urgent_clinic"),
            "recommendation_message": result.get("recommendation_message", ""),
            "details": result["details"]
        })
    except Exception as e:
        return jsonify({"error": f"Consolidation failed: {str(e)}"}), 500


def compute_expiry_info(data):
    expiry_date = data.get("expiry_date")
    if not expiry_date:
        return {"days_remaining": None, "expiry_status": "unknown"}
    now = datetime.utcnow()
    if isinstance(expiry_date, datetime):
        expiry_dt = expiry_date
    else:
        try:
            expiry_dt = datetime.strptime(str(expiry_date)[:10], "%Y-%m-%d")
        except (ValueError, TypeError):
            return {"days_remaining": None, "expiry_status": "unknown"}
    days_remaining = (expiry_dt - now).days
    if days_remaining < 0:
        status = "expired"
    elif days_remaining <= 30:
        status = "expiring_soon"
    elif days_remaining <= 90:
        status = "warning"
    else:
        status = "safe"
    return {"days_remaining": days_remaining, "expiry_status": status}


@app.route('/inventory', methods=['GET'])
@cached(ttl_seconds=180)
def get_inventory():
    clinic_id = request.args.get('clinic_id')
    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400
    try:
        joined = get_joined_inventory(clinic_id=clinic_id)
        inventory_list = []
        for item in joined:
            display = (
                item.get("full_brand_name")
                or item.get("brand_name")
                or item.get("match_name")
                or item.get("item_code", "")
            )
            inventory_list.append({
                "id": "",
                "item_name": display,
                "item_code": item.get("item_code", ""),
                "current_stock": int(item.get("quantity", 0)),
                "category": "",
                "batch_no": "",
                "expiry_date": None,
                "stock_level": "",
                "last_updated": item.get("updated_at", ""),
                "days_remaining": None,
                "expiry_status": "unknown",
            })
        clinic_doc = db.collection("clinics").document(clinic_id).get()
        clinic_data = clinic_doc.to_dict() if clinic_doc.exists else {}
        clinic_name = clinic_data.get("name", clinic_id)
        district = clinic_data.get("district", "")
        return jsonify({
            "clinic_id": clinic_id,
            "clinic_name": clinic_name,
            "district": district,
            "inventory": inventory_list
        })
    except Exception as e:
        return jsonify({"error": f"Inventory load failed: {str(e)}"}), 500


@app.route('/dashboard/summary', methods=['GET'])
@cached(ttl_seconds=300)
def dashboard_summary():
    clinic_id = request.args.get('clinic_id')
    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400
    try:
        clinic_data = fetch_clinic(clinic_id)
        clinic_name = clinic_data.get("clinic_name") or clinic_data.get("name", clinic_id)
        district = clinic_data.get("district", "")

        supabase_items = get_inventory_for_clinic(clinic_id)

        inventory_items = []
        low_stock_count = 0
        moderate_count = 0
        adequate_count = 0

        for item in supabase_items:
            item_name = item['item_name']
            stock = item['current_stock']
            inventory_items.append({
                "item_name": item_name,
                "current_stock": stock,
            })
            if stock < 20:
                low_stock_count += 1
            elif stock < 50:
                moderate_count += 1
            else:
                adequate_count += 1

        pending_orders_count = 0
        for doc in db.collection("orders") \
                .where("clinic_id", "==", clinic_id) \
                .stream():
            data = doc.to_dict()
            if data.get("status") in ("PENDING", "SUBMITTED"):
                pending_orders_count += 1

        dispense_txns = fetch_dispense_transactions(clinic_id=clinic_id, limit=1000)
        usage_list = dispense_txns_to_usage_list(dispense_txns)
        stock_in_data = []
        for u in usage_list:
            stock_in_data.append({
                "type": "stock_out",
                "item_name": u["item_name"],
                "quantity": u["quantity_used"],
                "timestamp": str(u["timestamp"]) if u["timestamp"] else None,
            })

        for doc in db.collection("stock_in_logs") \
                .where("clinic_id", "==", clinic_id) \
                .stream():
            data = doc.to_dict()
            stock_in_data.append({
                "type": "stock_in",
                "item_name": data.get("item_name"),
                "quantity": data.get("quantity_added") or data.get("qty_added") or 0,
                "timestamp": str(data.get("timestamp")) if data.get("timestamp") else None,
            })

        recent_activity = list(stock_in_data)
        for doc in db.collection("orders") \
                .where("clinic_id", "==", clinic_id) \
                .stream():
            data = doc.to_dict()
            recent_activity.append({
                "type": "order",
                "status": data.get("status", "PENDING"),
                "timestamp": str(data.get("created_at")) if data.get("created_at") else None,
            })

        recent_activity.sort(key=lambda e: e.get("timestamp") or "", reverse=True)
        recent_activity = recent_activity[:20]

        top_products = build_top_products_from_dispense(dispense_txns)
        stock_summary = {
            "critical": low_stock_count,
            "low": moderate_count,
            "safe": adequate_count
        }
        insight_message_data = build_insight_message_payload(stock_summary, top_products)

        now = datetime.utcnow()
        days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        current_hour = now.hour
        if current_hour < 12:
            greeting = "Good Morning"
        elif current_hour < 17:
            greeting = "Good Afternoon"
        else:
            greeting = "Good Evening"

        return jsonify({
            "clinic_id": clinic_id,
            "clinic_name": clinic_name,
            "district": district,
            "greeting": greeting,
            "current_date": now.strftime("%Y-%m-%d"),
            "current_day": days[now.weekday()],
            "current_time": now.strftime("%H:%M:%S"),
            "total_medicines": len(inventory_items),
            "low_stock_count": low_stock_count,
            "moderate_count": moderate_count,
            "adequate_count": adequate_count,
            "pending_orders_count": pending_orders_count,
            "inventory_health": {
                "low": low_stock_count,
                "moderate": moderate_count,
                "adequate": adequate_count,
            },
            "recent_activity": recent_activity,
            "insight_message": insight_message_data.get("message", ""),
            "top_products": top_products,
        })
    except Exception as e:
        return jsonify({"error": f"Dashboard summary failed: {str(e)}"}), 500


@app.route('/order_suggestions', methods=['GET'])
@cached(ttl_seconds=180)
def get_order_suggestions():
    clinic_id = request.args.get('clinic_id')
    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400
    try:
        clinic_doc = db.collection("clinics").document(clinic_id).get()
        if clinic_doc.exists and clinic_doc.to_dict().get("has_pending_order"):
            return jsonify({"clinic_id": clinic_id, "order_suggestions": []})
        inv_items = get_inventory_for_clinic(clinic_id)
        suggestions = []
        for item in inv_items:
            stock = item["current_stock"]
            item_name = item["item_name"]
            if stock < 100:
                suggestions.append({
                    "item_name": item_name,
                    "suggested_qty": 200 - stock,
                    "priority": "HIGH"
                })
            elif stock < 200:
                suggestions.append({
                    "item_name": item_name,
                    "suggested_qty": 300 - stock,
                    "priority": "MEDIUM"
                })
        return jsonify({"clinic_id": clinic_id, "order_suggestions": suggestions})
    except Exception as e:
        return jsonify({"error": f"Order suggestions failed: {str(e)}"}), 500

@app.route('/usage_logs', methods=['GET'])
@cached(ttl_seconds=300)
def get_usage_logs():
    clinic_id = request.args.get('clinic_id')
    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400
    try:
        docs = db.collection("usage_logs") \
                 .where("clinic_id", "==", clinic_id) \
                 .stream()
        logs = []
        for doc in docs:
            data = doc.to_dict()
            timestamp = data.get("timestamp")
            if timestamp:
                malaysia_time = timestamp + timedelta(hours=8)
                formatted_time = malaysia_time.strftime("%Y-%m-%d %H:%M:%S")
            else:
                formatted_time = None
            logs.append({
                "item_name": data.get("item_name"),
                "quantity_used": data.get("quantity_used"),
                "timestamp": formatted_time
            })
        return jsonify({"clinic_id": clinic_id, "usage_logs": logs})
    except Exception as e:
        return jsonify({"error": f"Usage logs failed: {str(e)}"}), 500

@app.route('/usage_logs', methods=['POST'])
def add_usage_log():
    data = request.get_json()
    clinic_id = data.get("clinic_id")
    item_name = data.get("item_name")
    quantity_used = data.get("quantity_used")
    if not clinic_id or not item_name or not quantity_used:
        return jsonify({"error": "Missing data"}), 400
    try:
        db.collection("usage_logs").add({
            "clinic_id": clinic_id,
            "item_name": item_name,
            "quantity_used": quantity_used,
            "timestamp": datetime.utcnow()
        })
        return jsonify({"message": "Usage log added successfully"})
    except Exception as e:
        return jsonify({"error": f"Failed to add usage log: {str(e)}"}), 500

@app.route('/stock_in', methods=['POST'])
def stock_in():
    data = request.get_json()
    clinic_id = data.get("clinic_id")
    item_name = data.get("item_name")
    quantity_added = int(data.get("quantity_added", 0))
    if clinic_id is None or item_name is None or quantity_added is None:
        return jsonify({"error": "Missing data"}), 400
    try:
        docs = db.collection("inventory") \
                 .where("clinic_id", "==", clinic_id) \
                 .where("item_name", "==", item_name) \
                 .stream()
        found = False
        for doc in docs:
            found = True
            data_db = doc.to_dict()
            current_stock = data_db.get("current_stock", 0)
            new_stock = current_stock + quantity_added
            db.collection("inventory").document(doc.id).update({"current_stock": new_stock})
        if not found:
            db.collection("inventory").add({
                "clinic_id": clinic_id,
                "item_name": item_name,
                "current_stock": quantity_added
            })
        db.collection("stock_in_logs").add({
            "clinic_id": clinic_id,
            "item_name": item_name,
            "quantity_added": quantity_added,
            "timestamp": datetime.utcnow()
        })
        return jsonify({"message": "Stock-in successful"})
    except Exception as e:
        return jsonify({"error": f"Stock-in failed: {str(e)}"}), 500

@app.route('/stock_out', methods=['POST'])
def stock_out():
    data = request.get_json()
    clinic_id = data.get("clinic_id")
    item_name = data.get("item_name")
    quantity_used = int(data.get("quantity_used", 0))
    if clinic_id is None or item_name is None or quantity_used is None:
        return jsonify({"error": "Missing data"}), 400
    quantity_used = int(quantity_used)
    try:
        docs = db.collection("inventory") \
                 .where("clinic_id", "==", clinic_id) \
                 .where("item_name", "==", item_name) \
                 .stream()
        found = False
        for doc in docs:
            found = True
            data_db = doc.to_dict()
            current_stock = data_db.get("current_stock", 0)
            if current_stock < quantity_used:
                return jsonify({"error": "Not enough stock"}), 400
            new_stock = current_stock - quantity_used
            db.collection("inventory").document(doc.id).update({"current_stock": new_stock})
        if not found:
            return jsonify({"error": "Item not found in inventory"}), 404
        db.collection("usage_logs").add({
            "clinic_id": clinic_id,
            "item_name": item_name,
            "quantity_used": quantity_used,
            "timestamp": datetime.utcnow()
        })
        return jsonify({"message": "Stock-out successful"})
    except Exception as e:
        return jsonify({"error": f"Stock-out failed: {str(e)}"}), 500

@app.route('/ai/forecast', methods=['GET'])
def ai_forecast():
    unavailable = ai_unavailable_response()
    if unavailable:
        return unavailable
    clinic_id = request.args.get('clinic_id')
    item_name = request.args.get('item_name')
    if not clinic_id or not item_name:
        return jsonify({"error": "Missing clinic_id or item_name"}), 400
    try:
        cache_key = f"forecast:{clinic_id}:{item_name}"
        cached_data = cache_get(cache_key)
        if cached_data:
            return jsonify(cached_data)
        dispense_txns = fetch_dispense_transactions(clinic_id=clinic_id, limit=1000)
        usage_data = [
            {"quantity_used": u["quantity_used"], "timestamp": u["timestamp"]}
            for u in dispense_txns_to_usage_list(dispense_txns)
            if u["item_name"] == item_name
        ]
        forecast = generate_forecast(usage_data, predict_days=7)
        result = {"clinic_id": clinic_id, "item_name": item_name, "forecast_7_days": forecast}
        cache_set(cache_key, result, ttl_seconds=60)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": f"Forecast failed: {str(e)}"}), 500


@app.route('/ai/anomalies', methods=['GET'])
def ai_anomalies():
    unavailable = ai_unavailable_response()
    if unavailable:
        return unavailable
    clinic_id = request.args.get('clinic_id')
    if not clinic_id:
        return jsonify({"error": "Missing clinic_id"}), 400
    try:
        cache_key = f"anomalies:{clinic_id}"
        cached_data = cache_get(cache_key)
        if cached_data:
            return jsonify(cached_data)
        docs = db.collection("usage_logs") \
                 .where("clinic_id", "==", clinic_id) \
                 .stream()
        usage_data = []
        for doc in docs:
            data = doc.to_dict()
            usage_data.append({
                "item_name": data.get("item_name"),
                "quantity_used": data.get("quantity_used", 0),
                "timestamp": data.get("timestamp")
            })
        anomalies_report = []
        item_groups = {}
        for entry in usage_data:
            item = entry['item_name']
            if item not in item_groups:
                item_groups[item] = []
            item_groups[item].append(entry)
        for item, item_data in item_groups.items():
            anomalies = detect_anomalies(item_data)
            if anomalies:
                anomalies_report.append({
                    "item_name": item,
                    "anomalies": anomalies
                })
        result = {"clinic_id": clinic_id, "epidemic_warnings": anomalies_report}
        cache_set(cache_key, result, ttl_seconds=120)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": f"Anomaly detection failed: {str(e)}"}), 500


@app.route('/ai/overall_usage', methods=['GET'])
@cached(ttl_seconds=300)
def ai_overall_usage():
    clinic_id = request.args.get('clinic_id')
    dispense_txns = fetch_dispense_transactions(clinic_id=clinic_id, limit=1000)
    logs = dispense_txns_to_usage_list(dispense_txns)
    return jsonify(build_overall_usage_payload(logs))


@app.route('/ai/stock_summary', methods=['GET'])
@cached(ttl_seconds=300)
def ai_stock_summary():
    clinic_id = request.args.get('clinic_id')
    inventory_items = get_inventory_for_clinic(clinic_id)
    return jsonify(build_stock_summary_payload(inventory_items))


@app.route('/ai/top_products', methods=['GET'])
@cached(ttl_seconds=300)
def ai_top_products():
    clinic_id = request.args.get('clinic_id')
    dispense_txns = fetch_dispense_transactions(clinic_id=clinic_id, limit=1000)
    return jsonify(build_top_products_from_dispense(dispense_txns))


@app.route('/ai/insight_message', methods=['GET'])
@cached(ttl_seconds=300)
def ai_insight_message():
    clinic_id = request.args.get('clinic_id')
    inventory_items = get_inventory_for_clinic(clinic_id)
    stock_summary = build_stock_summary_payload(inventory_items)
    dispense_txns = fetch_dispense_transactions(clinic_id=clinic_id, limit=1000)
    top_products = build_top_products_from_dispense(dispense_txns)
    return jsonify(build_insight_message_payload(stock_summary, top_products))

@app.route('/ai/smart_inventory', methods=['GET'])
@cached(ttl_seconds=300)
def ai_smart_inventory():
    unavailable = ai_unavailable_response()
    if unavailable:
        return unavailable
    clinic_id = request.args.get('clinic_id')
    if not clinic_id:
        return jsonify({"error": "Missing clinic_id"}), 400
    try:
        inv_items = get_inventory_for_clinic(clinic_id)
        my_inventory = {item['item_name']: item['current_stock'] for item in inv_items}
        weather_data = get_7_day_weather()
        dispense_txns = fetch_dispense_transactions(clinic_id=clinic_id, limit=1000)
        usage_list = dispense_txns_to_usage_list(dispense_txns)
        my_usage = {}
        for u in usage_list:
            item = u["item_name"]
            if item not in my_usage:
                my_usage[item] = []
            my_usage[item].append(u)
        smart_list = []
        for item, stock in my_inventory.items():
            logs = my_usage.get(item, [])
            anomalies = detect_anomalies(logs) if logs else []
            metrics = calculate_smart_inventory(logs, stock, item_name=item, weather_data=weather_data) if logs else {
                "run_out_days": -1, "run_out_date": None, "recommend_order": 0,
                "surplus_stock": stock, "forecast_7_days": [], "weather_warning": ""
            }
            smart_list.append({
                "item_name": item,
                "current_stock": stock,
                "run_out_days": metrics['run_out_days'],
                "run_out_date": metrics['run_out_date'],
                "recommend_order": metrics['recommend_order'],
                "surplus_stock": metrics['surplus_stock'],
                "forecast_7_days": metrics['forecast_7_days'],
                "has_epidemic_warning": len(anomalies) > 0,
                "anomalies": anomalies,
                "transfer_candidates": [],
                "weather_warning": metrics.get("weather_warning", "")
            })
        smart_list.sort(key=lambda x: 9999 if x['run_out_days'] == -1 else x['run_out_days'])
        return jsonify({"clinic_id": clinic_id, "smart_inventory": smart_list})
    except Exception as e:
        return jsonify({"error": f"Smart inventory failed: {str(e)}"}), 500

@app.route('/pkd/request_transfer', methods=['POST'])
def pkd_request_transfer():
    data = request.get_json()
    from_clinic = data.get('from_clinic')
    to_clinic = data.get('clinic_id')
    item_name = data.get('item_name')
    quantity = data.get('quantity')
    if not from_clinic or not to_clinic or not item_name or not quantity:
        return jsonify({"error": "Missing data"}), 400
    try:
        db.collection("interclinic_transfers").add({
            "from_clinic": from_clinic,
            "to_clinic": to_clinic,
            "item_name": item_name,
            "quantity": int(quantity),
            "status": "Pending Acceptance",
            "timestamp": datetime.utcnow()
        })
        return jsonify({"message": f"Transfer request for {quantity} {item_name} sent to {from_clinic}!"})
    except Exception as e:
        return jsonify({"error": f"Transfer request failed: {str(e)}"}), 500


@app.route('/pkd/request_order', methods=['POST'])
def pkd_request_order():
    data = request.get_json()
    clinic_id = data.get('clinic_id')
    orders = data.get('orders', [])
    if not clinic_id or not orders:
        return jsonify({"error": "Missing data"}), 400
    try:
        db.collection("pkd_orders").add({
            "clinic_id": clinic_id,
            "orders": orders,
            "status": "Pending Verification",
            "timestamp": datetime.utcnow()
        })
        return jsonify({"message": "Order sent to PKD!"})
    except Exception as e:
        return jsonify({"error": f"PKD order failed: {str(e)}"}), 500

@app.route('/generate_order', methods=['POST'])
def generate_order():
    data = request.json
    clinic_id = data.get("clinic_id")
    items = data.get("items")
    if not clinic_id or not items:
        return jsonify({"error": "Missing data"}), 400
    try:
        order_data = {
            "clinic_id": clinic_id,
            "items": items,
            "status": "PENDING",
            "created_at": datetime.utcnow()
        }
        db.collection("orders").add(order_data)
        db.collection("clinics").document(clinic_id).update({"has_pending_order": True})
        return jsonify({"message": "Order generated successfully"})
    except Exception as e:
        return jsonify({"error": f"Order generation failed: {str(e)}"}), 500


@app.route('/orders', methods=['GET'])
@cached(ttl_seconds=180)
def get_orders():
    clinic_id = request.args.get('clinic_id')
    if not clinic_id:
        return jsonify({"error": "clinic_id required"}), 400
    try:
        docs = db.collection("orders") \
                 .where("clinic_id", "==", clinic_id) \
                 .stream()
        orders = []
        for doc in docs:
            data = doc.to_dict()
            orders.append({
                "id": doc.id,
                "items": data.get("items", []),
                "status": data.get("status", "PENDING"),
                "created_at": str(data.get("created_at"))
            })
        return jsonify({"orders": orders})
    except Exception as e:
        return jsonify({"error": f"Failed to load orders: {str(e)}"}), 500


@app.route('/complete_order', methods=['POST'])
def complete_order():
    data = request.json
    clinic_id = data.get("clinic_id")
    if not clinic_id:
        return jsonify({"error": "clinic_id required"}), 400
    try:
        orders = db.collection("orders") \
            .where("clinic_id", "==", clinic_id) \
            .where("status", "==", "SUBMITTED") \
            .stream()
        joined_supabase = get_joined_inventory(clinic_id=clinic_id)
        supabase_qty_map = {item["item_code"]: int(item["quantity"]) for item in joined_supabase}

        for doc in orders:
            order_data = doc.to_dict()
            items = order_data.get("items", [])
            for item in items:
                item_name = item.get("item_name")
                item_code = item.get("item_code", "")
                qty = item.get("qty", 0)
                inv_docs = db.collection("inventory") \
                    .where("clinic_id", "==", clinic_id) \
                    .where("item_name", "==", item_name) \
                    .stream()
                for inv_doc in inv_docs:
                    current_stock = inv_doc.to_dict().get("current_stock", 0)
                    inv_doc.reference.update({"current_stock": current_stock + qty})
                    db.collection("stock_in_logs").add({
                        "clinic_id": clinic_id,
                        "item_name": item_name,
                        "qty_added": qty,
                        "timestamp": datetime.utcnow()
                    })
                if item_code:
                    current_supabase_qty = supabase_qty_map.get(item_code, 0)
                    new_supabase_qty = current_supabase_qty + qty
                    update_inventory_quantity(clinic_id, item_code, new_supabase_qty)
            doc.reference.update({"status": "RECEIVED"})
        db.collection("clinics").document(clinic_id).update({"has_pending_order": False})
        return jsonify({"message": "Order received & inventory updated"})
    except Exception as e:
        return jsonify({"error": f"Complete order failed: {str(e)}"}), 500


@app.route('/update_order_status', methods=['POST'])
def update_order_status():
    data = request.json
    order_id = data.get("order_id")
    new_status = data.get("status")
    if not order_id or not new_status:
        return jsonify({"error": "Missing data"}), 400
    try:
        db.collection("orders").document(order_id).update({"status": new_status})
        if new_status == "SUBMITTED":
            order = db.collection("orders").document(order_id).get()
            if order.exists:
                clinic_id = order.to_dict().get("clinic_id")
                if clinic_id:
                    db.collection("clinics").document(clinic_id).update({"has_pending_order": True})
        return jsonify({"message": "Order status updated"})
    except Exception as e:
        return jsonify({"error": f"Update failed: {str(e)}"}), 500


# ===================== PKD ANALYTICS HELPERS =====================

def get_district_clinics(district):
    if not district:
        return []
    clinics = []
    for doc in db.collection("clinics").where("district", "==", district).stream():
        data = doc.to_dict()
        clinics.append({
            "clinic_id": doc.id,
            "name": data.get("name", doc.id),
            "district": data.get("district", district),
            "route_id": data.get("route_id", ""),
            "has_pending_order": data.get("has_pending_order", False),
        })
    return clinics


def count_orders_for_clinic(clinic_id, status):
    try:
        count = 0
        for doc in db.collection("orders") \
                .where("clinic_id", "==", clinic_id) \
                .stream():
            if doc.to_dict().get("status") == status:
                count += 1
        return count
    except Exception:
        return 0


# Precomputed PKD summary: 1 Firestore read instead of scanning all collections
PKD_SUMMARY_TTL = 600  # 10 minutes

def get_or_compute_pkd_summary(district):
    if not district:
        return {"error": "district is required"}
    summary_doc_id = district.lower().replace(" ", "_")
    now = datetime.utcnow()
    try:
        doc_ref = db.collection("pkd_summaries").document(summary_doc_id)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            last_updated = data.get("last_updated")
            if last_updated and (now - last_updated).total_seconds() < PKD_SUMMARY_TTL:
                return data.get("data", {})
    except Exception:
        pass
    try:
        overview = build_pkd_overview(district)
        clinics = get_district_clinics(district)
        clinic_risks = [build_clinic_risk(c) for c in clinics]
        clinic_risks.sort(key=lambda x: x["risk_score"], reverse=True)
        route_map = {}
        for c in clinics:
            rid = c.get("route_id", "unassigned")
            if rid not in route_map:
                route_map[rid] = {"route_id": rid, "clinics": [], "total_risk": 0, "pending_orders": 0}
            risk_info = next((r for r in clinic_risks if r["clinic_id"] == c["clinic_id"]), None)
            if risk_info:
                route_map[rid]["total_risk"] += risk_info["risk_score"]
                route_map[rid]["pending_orders"] += risk_info["pending_orders"]
        route_list = []
        for rid, data in route_map.items():
            avg_risk = data["total_risk"] / max(len(data["clinics"]), 1)
            route_list.append({
                "route_id": rid,
                "clinic_count": len([c for c in clinics if c.get("route_id", "unassigned") == rid]),
                "avg_risk_score": round(avg_risk, 1),
                "pending_orders": data["pending_orders"],
            })
        route_list.sort(key=lambda x: x["avg_risk_score"], reverse=True)
        result = {
            "district": district,
            "overview": overview,
            "clinics": clinic_risks[:20],
            "routes": route_list,
        }
        try:
            doc_ref.set({
                "district": district,
                "data": result,
                "last_updated": now,
            })
        except Exception:
            pass
        return result
    except Exception as e:
        return {"district": district, "overview": {}, "clinics": [], "routes": [],
                "warning": f"Summary unavailable: {str(e)}"}


def get_clinic_inventory_stats(clinic_id):
    total = 0
    low_stock = 0
    try:
        for item in get_inventory_for_clinic(clinic_id):
            total += 1
            if item["current_stock"] < 100:
                low_stock += 1
    except Exception:
        pass
    return {"total": total, "low_stock": low_stock, "expiring_soon": 0, "expired": 0}


def get_clinic_usage_summary(clinic_id):
    monthly_logs = 0
    try:
        now = datetime.utcnow()
        for doc in db.collection("usage_logs") \
                .where("clinic_id", "==", clinic_id) \
                .stream():
            data = doc.to_dict()
            ts = data.get("timestamp")
            if ts and hasattr(ts, "month") and ts.month == now.month and ts.year == now.year:
                monthly_logs += 1
    except Exception:
        pass
    return {"monthly_logs": monthly_logs}


def build_clinic_risk(clinic):
    clinic_id = clinic["clinic_id"]
    inv_stats = get_clinic_inventory_stats(clinic_id)
    usage = get_clinic_usage_summary(clinic_id)
    pending_count = count_orders_for_clinic(clinic_id, "PENDING")
    submitted_count = count_orders_for_clinic(clinic_id, "SUBMITTED")
    total_orders = pending_count + submitted_count
    risk_score = 0
    risk_reasons = []
    if inv_stats["low_stock"] > 0:
        risk_score += inv_stats["low_stock"] * 2
        risk_reasons.append(f"{inv_stats['low_stock']} low-stock items")
    if inv_stats["expiring_soon"] > 0:
        risk_score += inv_stats["expiring_soon"]
        risk_reasons.append(f"{inv_stats['expiring_soon']} items expiring soon")
    if inv_stats["expired"] > 0:
        risk_score += inv_stats["expired"] * 3
        risk_reasons.append(f"{inv_stats['expired']} expired items")
    if usage["monthly_logs"] == 0:
        risk_score += 1
        risk_reasons.append("No recent usage logs")
    if total_orders > 0:
        risk_score += total_orders
        risk_reasons.append(f"{total_orders} pending/submitted orders")
    if risk_score >= 10:
        risk_level = "HIGH"
    elif risk_score >= 5:
        risk_level = "MEDIUM"
    else:
        risk_level = "LOW"
    return {
        "clinic_id": clinic_id,
        "name": clinic.get("name", clinic_id),
        "route_id": clinic.get("route_id", ""),
        "risk_level": risk_level,
        "risk_score": risk_score,
        "risk_reasons": risk_reasons[:3],
        "total_medicines": inv_stats["total"],
        "low_stock_count": inv_stats["low_stock"],
        "pending_orders": pending_count,
        "monthly_logs": usage["monthly_logs"],
    }


def build_pkd_overview(district):
    clinics = get_district_clinics(district)
    total_clinics = len(clinics)
    high_risk_clinics = 0
    total_low_stock = 0
    total_pending_orders = 0
    total_monthly_logs = 0
    all_routes = set()
    top_medicine_totals = {}

    for clinic in clinics:
        cid = clinic["clinic_id"]
        inv_stats = get_clinic_inventory_stats(cid)
        usage = get_clinic_usage_summary(cid)
        pending = count_orders_for_clinic(cid, "PENDING")
        submitted = count_orders_for_clinic(cid, "SUBMITTED")
        risk_score = (inv_stats["low_stock"] * 2) + (inv_stats["expired"] * 3) + pending + submitted
        if risk_score >= 10:
            high_risk_clinics += 1
        total_low_stock += inv_stats["low_stock"]
        total_pending_orders += pending + submitted
        total_monthly_logs += usage["monthly_logs"]
        if clinic.get("route_id"):
            all_routes.add(clinic["route_id"])

        for doc in db.collection("usage_logs") \
                .where("clinic_id", "==", cid) \
                .stream():
            data = doc.to_dict()
            item = data.get("item_name")
            qty = int(data.get("quantity_used", 0))
            if item:
                top_medicine_totals[item] = top_medicine_totals.get(item, 0) + qty

    top_medicines = sorted(top_medicine_totals.items(), key=lambda x: x[1], reverse=True)[:5]
    active_routes = len(all_routes)

    return {
        "district": district,
        "total_clinics": total_clinics,
        "clinics_at_risk": high_risk_clinics,
        "active_routes": active_routes,
        "total_low_stock_items": total_low_stock,
        "total_pending_orders": total_pending_orders,
        "total_monthly_logs": total_monthly_logs,
        "medicines_tracked": len(top_medicine_totals),
        "top_medicines": [
            {"rank": i + 1, "item_name": name, "total_used": qty}
            for i, (name, qty) in enumerate(top_medicines)
        ],
    }


# ===================== PKD ANALYTICS ENDPOINTS =====================

@app.route('/pkd/overview', methods=['GET'])
@cached(ttl_seconds=600)
def pkd_overview():
    district = request.args.get('district')
    if not district:
        return jsonify({"error": "district is required"}), 400
    try:
        overview = build_pkd_overview(district)
        return jsonify(overview)
    except Exception as e:
        return jsonify({
            "district": district, "total_clinics": 0, "clinics_at_risk": 0,
            "active_routes": 0, "total_low_stock_items": 0, "total_pending_orders": 0,
            "total_monthly_logs": 0, "medicines_tracked": 0, "top_medicines": [],
            "warning": f"Overview partially unavailable: {str(e)}"
        })


@app.route('/pkd/clinic_risks', methods=['GET'])
@cached(ttl_seconds=600)
def pkd_clinic_risks():
    district = request.args.get('district')
    if not district:
        return jsonify({"error": "district is required"}), 400
    try:
        clinics = get_district_clinics(district)
        results = [build_clinic_risk(c) for c in clinics]
        results.sort(key=lambda x: x["risk_score"], reverse=True)
        return jsonify({"district": district, "clinics": results})
    except Exception as e:
        return jsonify({"district": district, "clinics": [], "warning": str(e)})


@app.route('/pkd/routes', methods=['GET'])
@cached(ttl_seconds=600)
def pkd_routes():
    district = request.args.get('district')
    if not district:
        return jsonify({"error": "district is required"}), 400
    try:
        clinics = get_district_clinics(district)
        route_map = {}
        for c in clinics:
            rid = c.get("route_id", "unassigned")
            if rid not in route_map:
                route_map[rid] = {"route_id": rid, "clinics": [], "total_risk": 0, "pending_orders": 0}
            risk_info = build_clinic_risk(c)
            route_map[rid]["clinics"].append(c)
            route_map[rid]["total_risk"] += risk_info["risk_score"]
            route_map[rid]["pending_orders"] += risk_info["pending_orders"]
        route_list = []
        for rid, data in route_map.items():
            avg_risk = data["total_risk"] / max(len(data["clinics"]), 1)
            route_list.append({
                "route_id": rid,
                "clinic_count": len(data["clinics"]),
                "avg_risk_score": round(avg_risk, 1),
                "pending_orders": data["pending_orders"],
            })
        route_list.sort(key=lambda x: x["avg_risk_score"], reverse=True)
        return jsonify({"district": district, "routes": route_list})
    except Exception as e:
        return jsonify({"district": district, "routes": [], "warning": str(e)})


@app.route('/pkd/top_medicines', methods=['GET'])
@cached(ttl_seconds=600)
def pkd_top_medicines():
    district = request.args.get('district')
    if not district:
        return jsonify({"error": "district is required"}), 400
    try:
        clinics = get_district_clinics(district)
        medicine_totals = {}
        thirty_days_ago = datetime.utcnow() - timedelta(days=30)
        for clinic in clinics:
            for doc in db.collection("usage_logs") \
                    .where("clinic_id", "==", clinic["clinic_id"]) \
                    .stream():
                data = doc.to_dict()
                ts = data.get("timestamp")
                if ts and isinstance(ts, datetime) and ts < thirty_days_ago:
                    continue
                item = data.get("item_name")
                qty = int(data.get("quantity_used", 0))
                if item:
                    medicine_totals[item] = medicine_totals.get(item, 0) + qty
        top = sorted(medicine_totals.items(), key=lambda x: x[1], reverse=True)[:10]
        return jsonify({
            "district": district,
            "medicines": [
                {"rank": i + 1, "item_name": name, "total_used": qty}
                for i, (name, qty) in enumerate(top)
            ]
        })
    except Exception as e:
        return jsonify({"district": district, "medicines": [], "warning": str(e)})

@app.route('/pkd/dashboard_summary', methods=['GET'])
@cached(ttl_seconds=600)
def pkd_dashboard_summary():
    district = request.args.get('district')
    if not district:
        return jsonify({"error": "district is required"}), 400
    result = get_or_compute_pkd_summary(district)
    return jsonify(result)


@app.route('/pkd/force_refresh_summary', methods=['POST'])
def pkd_force_refresh_summary():
    district = request.args.get('district')
    if not district:
        return jsonify({"error": "district is required"}), 400
    try:
        summary_doc_id = district.lower().replace(" ", "_")
        db.collection("pkd_summaries").document(summary_doc_id).delete()
    except Exception:
        pass
    result = get_or_compute_pkd_summary(district)
    return jsonify({"message": f"Summary refreshed for {district}", "data": result})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
