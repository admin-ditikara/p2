#!/bin/bash
# Run this ON the VM after SSH-ing in.
# Installs: Docker (with Compose plugin), nginx, certbot, git.
#
# Usage:
#   gcloud compute scp deploy/02-vm-setup.sh p2-server:~ --zone=us-central1-a
#   gcloud compute ssh p2-server --zone=us-central1-a -- bash ~/02-vm-setup.sh

set -e

echo "=== Updating packages ==="
sudo apt-get update -qq

# ── Docker ───────────────────────────────────────────────────────────────────
echo "=== Installing Docker ==="
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -qq
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# Allow current user to run Docker without sudo
sudo usermod -aG docker "$USER"
echo "  Docker installed. Group change takes effect on next login."

# ── nginx + Certbot ──────────────────────────────────────────────────────────
echo "=== Installing nginx and certbot ==="
sudo apt-get install -y nginx certbot python3-certbot-nginx
sudo systemctl enable nginx

# ── git ──────────────────────────────────────────────────────────────────────
echo "=== Installing git ==="
sudo apt-get install -y git

# ── App directory ────────────────────────────────────────────────────────────
echo "=== Creating app directory /opt/p2 ==="
sudo mkdir -p /opt/p2
sudo chown "$USER:$USER" /opt/p2

echo ""
echo "=== Setup complete! ==="
echo ""
echo "IMPORTANT: Log out and back in so Docker group membership takes effect."
echo ""
echo "  exit"
echo "  gcloud compute ssh p2-server --zone=us-central1-a"
echo ""
echo "Then copy your repo and run deploy/03-deploy.sh"
