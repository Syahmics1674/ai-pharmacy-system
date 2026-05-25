from flask import Blueprint, jsonify
from services.supabase_service import (
    get_joined_inventory,
    fetch_dispense_transactions,
    fetch_medicines,
)

supabase_bp = Blueprint("supabase", __name__)


@supabase_bp.route("/api/live_inventory", methods=["GET"])
def live_inventory():
    try:
        data = get_joined_inventory()
        return jsonify({"success": True, "inventory": data})
    except Exception as e:
        return jsonify({"success": False, "error": str(e), "inventory": []}), 500


@supabase_bp.route("/api/dispense_history", methods=["GET"])
def dispense_history():
    try:
        data = fetch_dispense_transactions()
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
