import pandas as pd
import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor, IsolationForest
from datetime import datetime, timedelta

def generate_forecast(usage_data, predict_days=7):
    """
    Trains a Gradient Boosting model to forecast demand based on historical usage.
    usage_data: list of dictionaries => [{'quantity_used': int, 'timestamp': datetime}, ...]
    """
    if not usage_data:
        return [0] * predict_days
    
    df = pd.DataFrame(usage_data)
    # Convert timezone-aware datetimes to naive datetimes if necessary, or just extract date
    df['timestamp'] = pd.to_datetime(df['timestamp'], utc=True)
    df['date'] = df['timestamp'].dt.date
    
    daily_usage = df.groupby('date')['quantity_used'].sum().reset_index()
    daily_usage['date'] = pd.to_datetime(daily_usage['date'])
    
    # Fill missing dates with 0
    full_range = pd.date_range(start=daily_usage['date'].min(), end=pd.to_datetime('today').normalize(), freq='D')
    daily_usage = daily_usage.set_index('date').reindex(full_range, fill_value=0).reset_index()
    daily_usage.rename(columns={'index': 'date'}, inplace=True)
    
    # Feature Engineering
    daily_usage['day_of_week'] = daily_usage['date'].dt.dayofweek
    daily_usage['day_of_month'] = daily_usage['date'].dt.day
    daily_usage['month'] = daily_usage['date'].dt.month
    
    # Simple rolling average feature
    daily_usage['rolling_mean_7d'] = daily_usage['quantity_used'].rolling(window=7, min_periods=1).mean()
    
    X = daily_usage[['day_of_week', 'day_of_month', 'month', 'rolling_mean_7d']]
    y = daily_usage['quantity_used']
    
    if len(X) < 14:
        # Fallback to mean if very little data
        return [int(y.mean())] * predict_days

    # Train Industry-Level Model (Gradient Boosting)
    model = HistGradientBoostingRegressor(max_iter=100, random_state=42)
    model.fit(X, y)
    
    # Predict into the future
    future_dates = [pd.to_datetime('today').normalize() + timedelta(days=i) for i in range(1, predict_days+1)]
    future_df = pd.DataFrame({'date': future_dates})
    future_df['day_of_week'] = future_df['date'].dt.dayofweek
    future_df['day_of_month'] = future_df['date'].dt.day
    future_df['month'] = future_df['date'].dt.month
    
    # Forward-fill the last rolling mean as a naive approach for the future rolling mean
    last_rolling_mean = daily_usage['rolling_mean_7d'].iloc[-1]
    future_df['rolling_mean_7d'] = last_rolling_mean
    
    X_future = future_df[['day_of_week', 'day_of_month', 'month', 'rolling_mean_7d']]
    predictions = model.predict(X_future)
    
    return [int(max(0, p)) for p in predictions]

def calculate_smart_inventory(usage_data, current_stock, item_name="", weather_data=None):
    """
    Returns dict with:
    - forecast_7_days: list of upcoming 7 days prediction
    - run_out_days: int (-1 if > 30 days)
    - run_out_date: string (YYYY-MM-DD or "Safe (>30 Days)")
    - recommend_order: int
    - surplus_stock: int
    - weather_warning: string (Empty if no warning)
    """
    # Force float/int
    try:
        current_stock = float(current_stock)
    except:
        current_stock = 0.0

    forecast_30 = generate_forecast(usage_data, predict_days=30)
    
    weather_warning = ""
    # --- METEOROLOGICAL SCALING ---
    if weather_data:
        max_rain = weather_data.get('max_rain_mm', 0)
        is_flu_med = item_name in ['Paracetamol', 'Uphamol', 'Cephalexin 250mg']
        
        if max_rain > 15.0:
            if is_flu_med:
                # 20% spike in fever/flu medications during monsoons
                forecast_30 = [int(x * 1.20) for x in forecast_30]
                weather_warning = f"🌧️ Weather Risk: Severe rainfall ({max_rain}mm) expected. AI increased +20% demand forecast."
            else:
                weather_warning = f"🌧️ Heavy rainfall ({max_rain}mm) expected, but {item_name} demand is unaffected by weather."
        else:
            if is_flu_med:
                weather_warning = f"☀️ Clear Weather: Normal demand forecast for fever/flu medications."
            else:
                weather_warning = f"🌤️ General Weather: No climate scaling applied to this item."

    forecast_7 = forecast_30[:7]
    
    run_out_days = -1
    run_out_string = "Safe (>30 Days)"
    stock = current_stock
    
    for i, daily_use in enumerate(forecast_30):
        stock -= daily_use
        if stock <= 0:
            run_out_days = i + 1
            run_out_date = pd.to_datetime('today') + timedelta(days=run_out_days)
            run_out_string = run_out_date.strftime('%Y-%m-%d')
            break
            
    # Recommended order is 30 days of safety stock minus current stock
    total_30_day_demand = sum(forecast_30)
    recommend_order = max(0, total_30_day_demand - current_stock)
    surplus_stock = max(0, current_stock - total_30_day_demand)
    
    return {
        "forecast_7_days": forecast_7,
        "run_out_days": run_out_days,
        "run_out_date": run_out_string,
        "recommend_order": int(recommend_order),
        "surplus_stock": int(surplus_stock),
        "weather_warning": weather_warning
    }

def detect_anomalies(usage_data):
    """
    Uses Isolation Forest to detect anomalous spikes in drug usage.
    Returns the dates and actual usage of flagged spikes.
    """
    if len(usage_data) < 30:
        return [] # Need at least 30 points to confidently call an anomaly
        
    df = pd.DataFrame(usage_data)
    df['timestamp'] = pd.to_datetime(df['timestamp'], utc=True)
    df['date'] = df['timestamp'].dt.date
    
    daily_usage = df.groupby('date')['quantity_used'].sum().reset_index()
    daily_usage['date'] = pd.to_datetime(daily_usage['date'])
    
    X = daily_usage[['quantity_used']]
    
    # Train Isolation Forest
    # Contamination = 0.05 implies ~5% of the data are considered anomalies
    model = IsolationForest(contamination=0.05, random_state=42)
    daily_usage['anomaly'] = model.fit_predict(X)
    
    # Flag positive spikes (we only care if they used way MORE than normal, not less)
    median_usage = daily_usage['quantity_used'].median()
    anomalies = daily_usage[(daily_usage['anomaly'] == -1) & (daily_usage['quantity_used'] > median_usage)]
    
    # Format output
    result = []
    for _, row in anomalies.iterrows():
        result.append({
            "date": row['date'].strftime('%Y-%m-%d'),
            "quantity": int(row['quantity_used'])
        })
        
    return result
