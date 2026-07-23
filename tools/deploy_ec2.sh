#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/DevM4rk/The-Genius-Game.git"
APP_DIR="$HOME/The-Genius-Game"

sudo apt-get update -y
sudo apt-get install -y git

if [ -d "$APP_DIR/.git" ]; then
  echo "Repo exists — pulling latest"
  git -C "$APP_DIR" fetch origin
  git -C "$APP_DIR" reset --hard origin/main
else
  echo "Cloning repo"
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR/infra"
sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build

echo "--- containers ---"
sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml ps
echo "--- health ---"
curl -sS http://127.0.0.1/health || true
echo
echo DEPLOY_OK
