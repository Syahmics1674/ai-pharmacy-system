# AI-Assisted Pharmacy Inventory System

AI-Assisted Pharmacy Inventory System (Flutter + Flask + Firebase).

---

## 🚀 Setup & Run Instructions

This system consists of two main components:
1. **Backend API**: A Flask application connecting to Firestore and Supabase.
2. **Frontend App**: A Flutter mobile/desktop application.

---

## 🛠️ Backend Setup (Flask)

The backend code is located in the [ai_pharmacy_backend](file:///c:/Users/danis/Documents/GitHub/ai-pharmacy-system/ai_pharmacy_backend/) directory.

### 1. Prerequisites
Make sure you have Python 3.8+ installed on your system.

### 2. Navigate to the backend directory
```bash
cd ai_pharmacy_backend
```

### 3. Create a virtual environment (Recommended)
This prevents system-wide package conflicts.
* **On Windows (PowerShell/CMD):**
  ```powershell
  python -m venv venv
  .\venv\Scripts\activate
  ```
* **On macOS/Linux:**
  ```bash
  python3 -m venv venv
  source venv/bin/activate
  ```

### 4. Install dependencies
```bash
pip install -r requirements.txt
```
*(This resolves `ModuleNotFoundError: No module named 'firebase_admin'` and installs all other required packages like Flask, scikit-learn, pandas, etc.)*

### 5. Setup Firebase Credentials 🔑
Because `firebase_key.json` contains private service account credentials, it is excluded from git version control and must be placed manually:
1. Open the [Firebase Console](https://console.firebase.google.com/).
2. Select your project and navigate to **Project Settings** (gear icon) > **Service Accounts**.
3. Under **Firebase Admin SDK**, click **Generate new private key**.
4. Save the downloaded JSON file as **`firebase_key.json`** inside the [ai_pharmacy_backend](file:///c:/Users/danis/Documents/GitHub/ai-pharmacy-system/ai_pharmacy_backend/) folder.

### 6. Run the server
```bash
python app.py
```
The backend server will run on `http://127.0.0.1:5000`.

---

## 📱 Frontend Setup (Flutter)

The frontend code is located in the [ai_pharmacy_app](file:///c:/Users/danis/Documents/GitHub/ai-pharmacy-system/ai_pharmacy_app/) directory.

### 1. Prerequisites
Install the [Flutter SDK](https://docs.flutter.dev/get-started/install).

### 2. Navigate to the app directory
```bash
cd ai_pharmacy_app
```

### 3. Get dependencies
```bash
flutter pub get
```

### 4. Run the application
Connect a physical device, start an emulator, or run on your desktop environment:
```bash
flutter run
```
