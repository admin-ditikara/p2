#!/bin/bash
# Run this ON the VM (after 02-vm-setup.sh and re-logging in).
# Clones the repo, starts Postgres + Rails via Docker Compose, and wires nginx.
#
# Usage (from the VM):
#   bash /opt/p2/deploy/03-deploy.sh

set -e

APP_DIR="/opt/p2"
REPO_URL="YOUR_GIT_REPO_URL"   # e.g. https://github.com/yourorg/p2.git

# ── Clone / update repo ──────────────────────────────────────────────────────
if [ -d "$APP_DIR/.git" ]; then
  echo "=== Pulling latest code ==="
  git -C "$APP_DIR" pull
else
  echo "=== Cloning repository ==="
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"

# ── Check .env ───────────────────────────────────────────────────────────────
if [ ! -f deploy/.env ]; then
  cp deploy/.env.example deploy/.env
  echo ""
  echo "ERROR: deploy/.env was just created from the example."
  echo "Edit it now, then re-run this script:"
  echo ""
  echo "  nano $APP_DIR/deploy/.env"
  echo ""
  exit 1
fi

# Make sure required vars are set
source deploy/.env
if [ -z "$RAILS_MASTER_KEY" ] || [ -z "$P2_DATABASE_PASSWORD" ]; then
  echo "ERROR: RAILS_MASTER_KEY and P2_DATABASE_PASSWORD must be set in deploy/.env"
  exit 1
fi

# ── Start services ───────────────────────────────────────────────────────────
echo "=== Building and starting containers ==="
docker compose --env-file deploy/.env -f deploy/docker-compose.prod.yml up -d --build

echo "=== Waiting for app to be ready ==="
sleep 5
docker compose --env-file deploy/.env -f deploy/docker-compose.prod.yml ps

# ── nginx ────────────────────────────────────────────────────────────────────
echo "=== Configuring nginx ==="
sudo cp deploy/nginx.conf /etc/nginx/sites-available/p2
sudo ln -sf /etc/nginx/sites-available/p2 /etc/nginx/sites-enabled/p2
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

echo ""
echo "=== Deployment complete! ==="
echo ""
EXTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip \
  2>/dev/null || echo "<your-vm-ip>")
echo "App URL : http://$EXTERNAL_IP"
echo ""
echo "Useful commands:"
echo "  View logs   : docker compose --env-file deploy/.env -f deploy/docker-compose.prod.yml logs -f app"
echo "  Rails console: docker compose --env-file deploy/.env -f deploy/docker-compose.prod.yml exec app bin/rails console"
echo "  SSL cert    : sudo certbot --nginx -d yourdomain.com"
