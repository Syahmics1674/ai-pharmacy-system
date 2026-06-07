from flask import Blueprint, jsonify, request
from services.supabase_service import (
    get_joined_inventory,
    fetch_dispense_transactions,
    fetch_medicines,
    upsert_dispense_transactions,
    update_inventory_quantity,
)

supabase_bp = Blueprint("supabase", __name__)


@supabase_bp.route("/api/live_inventory", methods=["GET"])
def live_inventory():
    try:
        clinic_id = request.args.get("clinic_id")
        data = get_joined_inventory(clinic_id=clinic_id)
        return jsonify({"success": True, "inventory": data})
    except Exception as e:
        return jsonify({"success": False, "error": str(e), "inventory": []}), 500


@supabase_bp.route("/api/dispense_history", methods=["GET"])
def dispense_history():
    try:
        clinic_id = request.args.get("clinic_id")
        data = fetch_dispense_transactions(clinic_id=clinic_id, limit=200)

        # Resolve medicine display names matching the inventory page logic
        medicines = fetch_medicines()
        medicine_map = {m.get("item_code"): m for m in medicines if m.get("item_code")}

        for txn in data:
            # Normalize timestamp key: Supabase stores cloud_created_at
            if "created_at" not in txn:
                raw_ts = txn.get("cloud_created_at") or txn.get("local_created_at")
                if raw_ts:
                    txn["created_at"] = raw_ts

            item_code = txn.get("item_code", "")
            med = medicine_map.get(item_code, {})

            # Resolve display name using same precedence as inventory page:
            # full_brand_name > brand_name > match_name > generic_name + strength + dosage_form > item_code
            display_name = (
                med.get("full_brand_name")
                or med.get("brand_name")
                or med.get("match_name")
                or (
                    " ".join(
                        p for p in [
                            med.get("generic_name"),
                            med.get("strength"),
                            med.get("dosage_form"),
                        ] if p
                    )
                    or None
                )
                or item_code
                or "Unknown"
            )
            txn["_display_name"] = display_name

            # Also attach individual fields for flexible fallback on the client
            for field in ("full_brand_name", "brand_name", "match_name",
                          "generic_name", "strength", "dosage_form"):
                if med.get(field):
                    txn[field] = med[field]

        return jsonify({"success": True, "dispense_transactions": data})
    except Exception as e:
        return jsonify({"success": False, "error": str(e), "dispense_transactions": []}), 500


@supabase_bp.route("/api/medicine_catalog", methods=["GET"])
def medicine_catalog():
    try:
        data = fetch_medicines()
        return jsonify({"success": True, "medicines": data})
    except Exception as e:
        return jsonify({"success": False, "error": str(e), "medicines": []}), 500


@supabase_bp.route("/api/sync/dispense", methods=["POST"])
def sync_dispense():
    try:
        body = request.get_json()
        if not body:
            return jsonify({"success": False, "error": "Request body required"}), 400
        clinic_id = body.get("clinic_id")
        transactions = body.get("transactions", [])
        if not clinic_id or not transactions:
            return jsonify({"success": False, "error": "clinic_id and transactions required"}), 400

        synced_ids = upsert_dispense_transactions(transactions)

        for txn in transactions:
            txn_id = txn.get("id")
            if txn_id in synced_ids:
                update_inventory_quantity(
                    clinic_id,
                    txn.get("item_code"),
                    txn.get("quantity_after", 0),
                )

        failed_ids = [
            txn.get("id")
            for txn in transactions
            if txn.get("id") not in synced_ids
        ]

        return jsonify({
            "success": len(failed_ids) == 0,
            "synced_ids": synced_ids,
            "failed_ids": failed_ids,
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e), "synced_ids": [], "failed_ids": []}), 500


@supabase_bp.route("/api/sync/status", methods=["GET"])
def sync_status():
    try:
        medicines = fetch_medicines()
        return jsonify({
            "success": True,
            "online": True,
            "medicines_count": len(medicines),
            "server_time": __import__("time").strftime(
                "%Y-%m-%dT%H:%M:%S+00:00", __import__("time").gmtime()
            ),
        })
    except Exception as e:
        return jsonify({"success": True, "online": False, "error": str(e)})
