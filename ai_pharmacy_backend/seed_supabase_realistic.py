import sys
import os
import random
from datetime import datetime, timedelta, timezone

# Add backend root to path to allow importing services folder
sys.path.append(os.path.abspath(os.path.dirname(__file__)))
from services.supabase_service import fetch_medicines, _rest_post

def seed():
    print("Fetching medicines from Supabase...")
    medicines = fetch_medicines()
    if not medicines:
        print("No medicines found in catalog. Seeding aborted.")
        return
    
    print(f"Found {len(medicines)} medicines.")
    
    clinic_id = "clinic_bangkit"
    end_date = datetime.now(timezone.utc)
    start_date = end_date - timedelta(days=90)
    
    transactions = []
    
    # Seeding loop over 90 days
    for day_offset in range(91):
        curr_date = start_date + timedelta(days=day_offset)
        # Skip weekends to simulate normal clinic closures
        if curr_date.weekday() >= 5:
            continue
            
        month = curr_date.month
        # Monsoon rainy season in Malaysia: Nov, Dec, Jan, Feb
        is_rainy_season = month in [11, 12, 1, 2]
        
        for m in medicines:
            code = m.get("item_code")
            name = m.get("full_brand_name") or m.get("brand_name") or m.get("match_name") or code
            
            # Fever, flu, and cough meds are dispensed more frequently
            is_flu_med = any(x in name.lower() for x in ["paracetamol", "uphamol", "cephalexin", "diphenhydramine", "salbutamol", "promethazine"])
            dispense_probability = 0.65 if is_flu_med else 0.35
            
            if random.random() > dispense_probability:
                continue
                
            # Random base quantity change (dispensing is negative)
            base_qty = random.randint(4, 16)
            
            # Rainy season boost for fever/flu meds
            if is_rainy_season and is_flu_med:
                base_qty = int(base_qty * random.uniform(1.2, 1.45))
                
            # Add a mock outbreak spike in January to test Isolation Forest anomaly detection
            if curr_date.month == 1 and 12 <= curr_date.day <= 18:
                if is_flu_med:
                    base_qty += random.randint(25, 55)
            
            # Format standard ISO timestamp with UTC timezone offset
            hour = random.randint(8, 16)
            minute = random.randint(0, 59)
            second = random.randint(0, 59)
            ts = curr_date.replace(hour=hour, minute=minute, second=second).isoformat()
            
            transactions.append({
                "clinic_id": clinic_id,
                "item_code": code,
                "matched_name": name,
                "quantity_change": -base_qty,
                "action": "stock_out",
                "device_id": "mac_dev_01",
                "local_created_at": ts,
                "cloud_created_at": ts
            })
            
    print(f"Generated {len(transactions)} transactions locally.")
    
    # Bulk insert in batches of 500 to stay safely under API thresholds
    batch_size = 500
    for i in range(0, len(transactions), batch_size):
        batch = transactions[i:i+batch_size]
        print(f"Inserting batch {i//batch_size + 1} of {((len(transactions)-1)//batch_size)+1} ({len(batch)} items)...")
        try:
            _rest_post("dispense_transactions", data=batch)
        except Exception as e:
            print(f"Error inserting batch: {str(e)}")
            return
        
    print("Seeding completed successfully!")

if __name__ == "__main__":
    seed()
