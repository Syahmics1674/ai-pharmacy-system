from flask import Flask, request, jsonify
from consolidation import consolidate_order_date
from firebase_config import db  
from datetime import timedelta
from datetime import datetime
from flask_cors import CORS  

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

@app.route('/consolidate', methods=['GET'])
def consolidate():

    clinic_id = request.args.get('clinic_id')

    if not clinic_id:
        return jsonify({"error": "clinic_id is required"}), 400

    result = consolidate_order_date(clinic_id)

    if not result:
        return jsonify({"error": "No data found"}), 404

    from datetime import timedelta

    malaysia_time = result["date"] + timedelta(hours=8)

    print("Final Consolidated Date:", malaysia_time)

    return jsonify({
        "clinic_id": clinic_id,
        "consolidated_date": malaysia_time.strftime("%Y-%m-%d"),
        "based_on": result["based_on"],
        "details": result["details"]
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

@app.route('/generate_order', methods=['POST'])
def generate_order():
    data = request.json

    clinic_id = data.get("clinic_id")
    items = data.get("items")

    if not clinic_id or not items:
        return jsonify({"error": "Missing data"}), 400

    order_data = {
        "clinic_id": clinic_id,
        "items": items,
        "status": "PENDING",
        "created_at": datetime.utcnow()
    }

    db.collection("orders").add(order_data)

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

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)