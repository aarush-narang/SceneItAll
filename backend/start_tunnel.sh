#!/bin/bash
set -e

cd "$(dirname "$0")"

PORT=8000

# Install ngrok if not present
if ! command -v ngrok &>/dev/null; then
  echo "Installing ngrok..."
  brew install ngrok
fi

# Start uvicorn in the background
uvicorn app.app:app --host 0.0.0.0 --port "$PORT" &
UVICORN_PID=$!

# Give uvicorn a moment to bind
sleep 2

echo ""
echo "Server running locally on http://localhost:$PORT"
echo "Starting ngrok tunnel..."
echo ""

# Start ngrok tunnel and capture the output
ngrok http "$PORT" &
TUNNEL_PID=$!

# On Ctrl-C, kill both
trap "kill $UVICORN_PID $TUNNEL_PID 2>/dev/null; exit 0" INT TERM

wait $UVICORN_PID
