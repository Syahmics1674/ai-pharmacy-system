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

def _rest_post(table, data, timeout=10.0):
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    response = httpx.post(url, headers=_SUPABASE_HEADERS, json=data, timeout=timeout)
    response.raise_for_status()
    return response.json()

def _rest_patch(table, params, data, timeout=10.0):
    url = f"{SUPABASE_URL}/rest/v1/{table}"
    response = httpx.patch(
        url, headers=_SUPABASE_HEADERS, params=params, json=data, timeout=timeout
    )
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
    params = {"limit": limit, "order": "cloud_created_at.desc.nullslast"}
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

def upsert_dispense_transactions(transactions):
    if not transactions:
        return []
    synced_ids = []
    for txn in transactions:
        try:
            _rest_post("dispense_transactions", txn)
            synced_ids.append(txn.get("id"))
        except Exception:
            pass
    return synced_ids


def update_inventory_quantity(clinic_id, item_code, quantity):
    params = {
        "clinic_id": f"eq.{clinic_id}",
        "item_code": f"eq.{item_code}",
    }
    data = {
        "quantity": quantity,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S.000000+00:00", time.gmtime()),
    }
    _rest_patch("inventory", params, data)


def add_dispense_transaction(clinic_id, item_code=None, matched_name=None, quantity_change=0, action="stock_out", device_id=None, local_created_at=None, cloud_created_at=None):
    payload = {
        "clinic_id": clinic_id,
        "item_code": item_code,
        "matched_name": matched_name,
        "quantity_change": quantity_change,
        "action": action,
    }
    if device_id:
        payload["device_id"] = device_id
    if local_created_at:
        payload["local_created_at"] = local_created_at
    if cloud_created_at:
        payload["cloud_created_at"] = cloud_created_at
    return _rest_post("dispense_transactions", data=payload)


def fetch_clinic(clinic_id):
    if not clinic_id:
        return {}
    cache_key = f"supabase_clinic_{clinic_id}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    try:
        data = _rest_get("clinics", params={"clinic_id": f"eq.{clinic_id}"})
        result = data[0] if data else {}
    except Exception:
        result = {}
    _cache_set(cache_key, result, ttl=_DEFAULT_TTL)
    return result


def fetch_clinics_by_district(district):
    if not district:
        return []
    cache_key = f"supabase_clinics_district_{district}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    try:
        data = _rest_get("clinics", params={"district": f"eq.{district}"})
    except Exception:
        data = []
    _cache_set(cache_key, data, ttl=_DEFAULT_TTL)
    return data


def update_clinic(clinic_id, data):
    if not clinic_id or not data:
        return
    params = {"clinic_id": f"eq.{clinic_id}"}
    try:
        _rest_patch("clinics", params, data)
    except Exception:
        pass


def clear_cache():
    with _cache_lock:
        _cache.clear()
