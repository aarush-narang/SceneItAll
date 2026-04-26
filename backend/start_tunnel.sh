#!/bin/bash
set -e

cd "$(dirname "$0")"

PORT=8000

# Install cloudflared if not present
if ! command -v cloudflared &>/dev/null; then
  echo "Installing cloudflared..."
  brew install cloudflared
fi

# Start uvicorn in the background
uvicorn app.app:app --host 0.0.0.0 --port "$PORT" &
UVICORN_PID=$!

# Give uvicorn a moment to bind
sleep 2

echo ""
echo "Server running locally on http://localhost:$PORT"
echo "Starting Cloudflare quick tunnel..."
echo ""

# Quick tunnel — no account needed; prints a *.trycloudflare.com URL
cloudflared tunnel --url "http://localhost:$PORT" &
TUNNEL_PID=$!

# On Ctrl-C, kill both
trap "kill $UVICORN_PID $TUNNEL_PID 2>/dev/null; exit 0" INT TERM

wait $UVICORN_PID
