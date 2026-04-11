from flask import Flask, request, jsonify
from consolidation import consolidate_order_date
from firebase_config import db  
from datetime import timedelta
from datetime import datetime
from flask_cors import CORS  
import sys
import os

# Allow import from ai_prediction parent directory
# Allow import from ai_prediction parent directory
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'ai_prediction')))
from ai_engine import generate_forecast, detect_anomalies, calculate_smart_inventory
from weather_service import get_7_day_weather
from consolidation import consolidate_order_date

app = Flask(__name__)
CORS(app)

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()

    username = data.get("username")
    password = data.get("password")

    if not username or not password:
        return jsonify({"error": "Missing credentials"}), 400

    docs = db.collection("users") \
             .where("username", "==", username) \
             .where("password", "==", password) \
             .stream()

    for doc in docs:
        user = doc.to_dict()
        return jsonify({
            "message": "Login successful",
            "clinic_id": user["clinic_id"]
        })

    return jsonify({"error": "Invalid credentials"}), 401

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


@app.route('/inventory', methods=['GET'])
def get_inventory():

    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400

    docs = db.collection("inventory") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    inventory_list = []

    for doc in docs:
        data = doc.to_dict()
        inventory_list.append({
            "item_name": data.get("item_name"),
            "current_stock": data.get("current_stock")
        })
    
    clinic_doc = db.collection("clinics").document(clinic_id).get()
    clinic_name = clinic_doc.to_dict().get("name", clinic_id)

    return jsonify({
        "clinic_id": clinic_id,
        "clinic_name": clinic_name,  
        "inventory": inventory_list
    })

@app.route('/order_suggestions', methods=['GET'])
def get_order_suggestions():

    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400

    docs = db.collection("inventory") \
             .where("clinic_id", "==", clinic_id) \
             .stream()

    suggestions = []

    for doc in docs:
        data = doc.to_dict()
        stock = data.get("current_stock", 0)
        item = data.get("item_name")

        # 🔥 LOW STOCK RULE
        if stock < 100:
            suggestions.append({
                "item_name": item,
                "suggested_qty": 200 - stock,  # simple rule
                "priority": "HIGH"
            })

        elif stock < 200:
            suggestions.append({
                "item_name": item,
                "suggested_qty": 300 - stock,
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

    logs = []

    for doc in docs:
        data = doc.to_dict()

        # Convert timestamp → Malaysia time
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

    return jsonify({
        "clinic_id": clinic_id,
        "usage_logs": logs
    })

@app.route('/usage_logs', methods=['POST'])
def add_usage_log():

    data = request.get_json()

    clinic_id = data.get("clinic_id")
    item_name = data.get("item_name")
    quantity_used = data.get("quantity_used")

    if not clinic_id or not item_name or not quantity_used:
        return jsonify({"error": "Missing data"}), 400

    db.collection("usage_logs").add({
        "clinic_id": clinic_id,
        "item_name": item_name,
        "quantity_used": quantity_used,
        "timestamp": datetime.utcnow()
    })

    return jsonify({
        "message": "Usage log added successfully"
    })

@app.route('/stock_in', methods=['POST'])
def stock_in():

    data = request.get_json()

    print("🔥 RECEIVED:", data)

    clinic_id = data.get("clinic_id")
    item_name = data.get("item_name")
    quantity_added = int(data.get("quantity_added", 0))  

    if clinic_id is None or item_name is None or quantity_added is None:
        return jsonify({"error": "Missing data"}), 400

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

        db.collection("inventory").document(doc.id).update({
            "current_stock": new_stock
        })

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

    return jsonify({
        "message": "Stock-in successful"
    })

@app.route('/stock_out', methods=['POST'])
def stock_out():

    data = request.get_json()
    print("🔥 STOCK OUT:", data)

    clinic_id = data.get("clinic_id")
    item_name = data.get("item_name")
    quantity_used = int(data.get("quantity_used", 0)) 

    if clinic_id is None or item_name is None or quantity_used is None:
        return jsonify({"error": "Missing data"}), 400

    quantity_used = int(quantity_used)  

    docs = db.collection("inventory") \
             .where("clinic_id", "==", clinic_id) \
             .where("item_name", "==", item_name) \
             .stream()

    found = False

    for doc in docs:
        found = True
        data_db = doc.to_dict()
        current_stock = data_db.get("current_stock", 0)

        # ❗ Prevent negative stock
        if current_stock < quantity_used:
            return jsonify({
                "error": "Not enough stock"
            }), 400

        new_stock = current_stock - quantity_used

        db.collection("inventory").document(doc.id).update({
            "current_stock": new_stock
        })

    if not found:
        return jsonify({
            "error": "Item not found in inventory"
        }), 404

    db.collection("usage_logs").add({
        "clinic_id": clinic_id,
        "item_name": item_name,
        "quantity_used": quantity_used,
        "timestamp": datetime.utcnow()
    })

    return jsonify({
        "message": "Stock-out successful"
    })

@app.route('/ai/forecast', methods=['GET'])
def ai_forecast():
    clinic_id = request.args.get('clinic_id')
    item_name = request.args.get('item_name')

    if not clinic_id or not item_name:
        return jsonify({"error": "Missing clinic_id or item_name"}), 400

    docs = db.collection("usage_logs") \
             .where("clinic_id", "==", clinic_id) \
             .where("item_name", "==", item_name) \
             .stream()

    usage_data = []
    for doc in docs:
        data = doc.to_dict()
        usage_data.append({
            "quantity_used": data.get("quantity_used", 0),
            "timestamp": data.get("timestamp")
        })

    forecast = generate_forecast(usage_data, predict_days=7)

    return jsonify({
        "clinic_id": clinic_id,
        "item_name": item_name,
        "forecast_7_days": forecast
    })

@app.route('/ai/anomalies', methods=['GET'])
def ai_anomalies():
    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "Missing clinic_id"}), 400

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

    # Group by item and detect anomalies
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

    return jsonify({
        "clinic_id": clinic_id,
        "epidemic_warnings": anomalies_report
    })

@app.route('/ai/smart_inventory', methods=['GET'])
def ai_smart_inventory():
    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "Missing clinic_id"}), 400

    # 1. High-Performance Bulk Load
    all_inv_docs = db.collection("inventory").stream()
    global_inv = {} # { clinic_id: { item: stock } }
    for doc in all_inv_docs:
        d = doc.to_dict()
        cid = d.get('clinic_id')
        if cid not in global_inv: global_inv[cid] = {}
        global_inv[cid][d.get('item_name')] = d.get('current_stock', 0)

    # 1.5 Fetch Meteorological Data once
    weather_data = get_7_day_weather()

    # 2. Bulk Load Usage Logs
    all_usage_docs = db.collection("usage_logs").stream()
    global_usage = {} # { clinic_id: { item: [logs] } }
    for doc in all_usage_docs:
        d = doc.to_dict()
        cid = d.get('clinic_id')
        item = d.get('item_name')
        if cid not in global_usage: global_usage[cid] = {}
        if item not in global_usage[cid]: global_usage[cid][item] = []
        global_usage[cid][item].append(d)

    # 3. Process each item for the local clinic
    smart_list = []
    my_inventory = global_inv.get(clinic_id, {})

    for item, stock in my_inventory.items():
        logs = global_usage.get(clinic_id, {}).get(item, [])
        anomalies = detect_anomalies(logs)
        metrics = calculate_smart_inventory(logs, stock, item_name=item, weather_data=weather_data)
        
        has_warning = len(anomalies) > 0
        
        # Cross-Clinic Balancing Logic
        transfer_candidates = []
        if metrics['recommend_order'] > 0:
            for other_clinic, other_items in global_inv.items():
                if other_clinic == clinic_id: continue
                other_stock = other_items.get(item, 0)
                if other_stock > 0:
                    other_logs = global_usage.get(other_clinic, {}).get(item, [])
                    other_metrics = calculate_smart_inventory(other_logs, other_stock, item_name=item, weather_data=weather_data)
                    if other_metrics['surplus_stock'] >= 20: # Only bother if they have a meaningful surplus > 20
                        transfer_candidates.append({
                            "clinic_id": other_clinic,
                            "surplus_stock": other_metrics['surplus_stock']
                        })

        # Sort transfer candidates by largest surplus
        transfer_candidates.sort(key=lambda x: x['surplus_stock'], reverse=True)

        smart_list.append({
            "item_name": item,
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

@app.route('/consolidate', methods=['GET'])
def consolidate_order():
    clinic_id = request.args.get('clinic_id')
    if not clinic_id:
        return jsonify({"error": "Missing clinic_id"}), 400
        
    result = consolidate_order_date(clinic_id)
    if result:
        return jsonify({
            "consolidated_date": str(result['date']),
            "based_on": result['based_on'],
            "details": result['details']
        })
    else:
        return jsonify({
            "consolidated_date": "No urgent orders",
            "based_on": "None",
            "details": []
        })

@app.route('/pkd/request_transfer', methods=['POST'])
def pkd_request_transfer():
    data = request.get_json()
    from_clinic = data.get('from_clinic')
    to_clinic = data.get('clinic_id') # The one making the request
    item_name = data.get('item_name')
    quantity = data.get('quantity')

    if not from_clinic or not to_clinic or not item_name or not quantity:
        return jsonify({"error": "Missing data"}), 400

    db.collection("interclinic_transfers").add({
        "from_clinic": from_clinic,
        "to_clinic": to_clinic,
        "item_name": item_name,
        "quantity": int(quantity),
        "status": "Pending Acceptance",
        "timestamp": datetime.utcnow()
    })

    return jsonify({"message": f"Transfer request for {quantity} {item_name} sent to {from_clinic}!"})

@app.route('/pkd/request_order', methods=['POST'])
def pkd_request_order():
    data = request.get_json()
    clinic_id = data.get('clinic_id')
    orders = data.get('orders', []) # list of {"item_name": "x", "quantity": int}

    if not clinic_id or not orders:
        return jsonify({"error": "Missing data"}), 400

    db.collection("pkd_orders").add({
        "clinic_id": clinic_id,
        "orders": orders,
        "status": "Pending Verification",
        "timestamp": datetime.utcnow()
    })

    return jsonify({"message": "Order sent to PKD!"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)