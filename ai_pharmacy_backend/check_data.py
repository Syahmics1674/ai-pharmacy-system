from firebase_config import db

def check_data():
    usage_ref = db.collection("usage_logs")
    docs = usage_ref.get()
    
    inventory_ref = db.collection("inventory")
    inv_docs = inventory_ref.get()
    
    print(f"Total Usage Logs: {len(docs)}")
    print(f"Total Inventory Items: {len(inv_docs)}")

if __name__ == "__main__":
    check_data()
