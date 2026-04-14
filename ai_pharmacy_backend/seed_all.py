"""
Master Seed Script — Run this to fully reset Firestore data
============================================================
Order of operations:
  1. Replace inventory with 50 Pharmaniaga medicines × 5 clinics
  2. Replace usage_logs with 1 year of realistic Malaysian usage data

Estimated time: ~5–10 minutes (Firestore batch writes)
"""

import time
from seed_pharmaniaga_inventory import seed_inventory
from seed_realistic_usage_logs import clear_usage_logs, seed_usage_logs

if __name__ == "__main__":
    print("\n" + "=" * 60)
    print("  AI PHARMACY SYSTEM — FULL FIRESTORE RESET")
    print("=" * 60 + "\n")

    # Step 1: Inventory
    print("STEP 1: Seeding Pharmaniaga Inventory...")
    t0 = time.time()
    seed_inventory()
    t1 = time.time()
    print(f"\n  [OK] Inventory seeded in {t1 - t0:.1f}s\n")

    # Step 2: Usage logs
    print("STEP 2: Clearing old usage logs...")
    clear_usage_logs()
    print()
    print("STEP 2: Seeding realistic usage logs (1 year)...")
    t2 = time.time()
    seed_usage_logs()
    t3 = time.time()
    print(f"\n  [OK] Usage logs seeded in {t3 - t2:.1f}s\n")

    print("=" * 60)
    print(f"  ALL DONE! Total time: {t3 - t0:.1f}s")
    print("=" * 60 + "\n")
