import time
import threading
import httpx

SUPABASE_URL = "https://lsgffuyamtsfszarqxwf.supabase.co"
SUPABASE_KEY = "sb_publishable_MELyDd3B3sYBtYti3f3NnQ_4bHs-I8C"

_SUPABASE_HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
}

_cache = {}
_cache_lock = threading.Lock()
_DEFAULT_TTL = 120

def _cache_get(key):
    with _cache_lock:
        entry = _cache.get(key)
        if entry is None:
            return None
        if time.time() > entry["expires_at"]:
            del _cache[key]
            return None
        return entry["data"]

def _cache_set(key, data, ttl=_DEFAULT_TTL):
    with _cache_lock:
        _cache[key] = {"data": data, "expires_at": time.time() + ttl}

def _rest_get(table, params=None, timeout=10.0):
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    response = httpx.get(url, headers=_SUPABASE_HEADERS, params=params, timeout=timeout)
    response.raise_for_status()
    return response.json()

def _safe_rest_get(table, params=None, timeout=10.0):
    try:
        return _rest_get(table, params=params, timeout=timeout)
    except Exception:
        return []

def fetch_inventory(clinic_id=None):
    cache_key = f"supabase_inventory_{clinic_id or 'all'}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    params = None
    if clinic_id:
        params = {"clinic_id": f"eq.{clinic_id}"}
    data = _safe_rest_get("inventory", params=params)
    _cache_set(cache_key, data, ttl=_DEFAULT_TTL)
    return data

def fetch_medicines():
    cache_key = "supabase_medicines"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    data = _safe_rest_get("medicines")
    _cache_set(cache_key, data, ttl=_DEFAULT_TTL)
    return data

def fetch_dispense_transactions(clinic_id=None, limit=100):
    cache_key = f"supabase_dispense_{clinic_id or 'all'}_{limit}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    params = {"limit": limit, "order": "created_at.desc.nullslast"}
    if clinic_id:
        params["clinic_id"] = f"eq.{clinic_id}"
    data = _safe_rest_get("dispense_transactions", params=params)
    _cache_set(cache_key, data, ttl=_DEFAULT_TTL)
    return data

def get_joined_inventory(clinic_id=None):
    cache_key = f"supabase_joined_inv_{clinic_id or 'all'}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    inventory = fetch_inventory(clinic_id=clinic_id)
    medicines = fetch_medicines()
    medicine_map = {m.get("item_code"): m for m in medicines if m.get("item_code")}
    joined = []
    for inv_item in inventory:
        item_code = inv_item.get("item_code")
        med = medicine_map.get(item_code, {})
        joined.append({
            "item_code": item_code,
            "quantity": inv_item.get("quantity", 0),

            "medicine_name": med.get("medicine_name") or inv_item.get("medicine_name"),

            "match_name": med.get("match_name"),
            "brand_name": med.get("brand_name"),
            "full_brand_name": med.get("full_brand_name"),

            "strength": med.get("strength"),
            "generic_name": med.get("generic_name"),
            "dosage_form": med.get("dosage_form"),

            "updated_at": inv_item.get("updated_at") or med.get("updated_at"),
        })
    _cache_set(cache_key, joined, ttl=_DEFAULT_TTL)
    print(
        f"Inventory rows={len(inventory)}, "
        f"Medicine rows={len(medicines)}, "
        f"Joined rows={len(joined)}"
    )
    return joined

def clear_cache():
    with _cache_lock:
        _cache.clear()
