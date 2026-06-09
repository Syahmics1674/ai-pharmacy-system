#!/bin/bash

PROJECT_DIR="/Users/shehabsharearemolla/IDP/ai-pharmacy-system"
BACKEND_DIR="$PROJECT_DIR/ai_pharmacy_backend"
FRONTEND_DIR="$PROJECT_DIR/ai_pharmacy_app"

echo "Starting AI Pharmacy System..."
echo "--------------------------------"

cd "$BACKEND_DIR" || exit 1

if [ ! -d ".venv" ]; then
  echo "Backend virtual environment not found."
  echo "Creating backend .venv..."
  python3 -m venv .venv
fi

source .venv/bin/activate

echo "Installing/checking backend requirements..."
if [ -f "requirements.txt" ]; then
  pip install -r requirements.txt
else
  pip install flask flask-cors
fi

echo "Starting backend on http://127.0.0.1:5000 ..."
python3 app.py &
BACKEND_PID=$!

echo "Waiting for backend..."
until curl -s "http://127.0.0.1:5000/clinic_info?clinic_id=clinic_bangkit" > /dev/null; do
  sleep 1
done

echo "Backend is ready."
echo "Starting Flutter macOS app..."
echo "--------------------------------"

cd "$FRONTEND_DIR" || exit 1

flutter pub get
flutter run -d macos --dart-define=BACKEND_URL=http://127.0.0.1:5000

echo "Flutter app closed."
echo "Stopping backend..."

kill $BACKEND_PID 2>/dev/null

echo "Done."
read -p "Press Enter to close this window..."
