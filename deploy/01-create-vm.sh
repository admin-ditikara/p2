#!/bin/bash
# Creates a GCP Compute Engine VM for p2 (Rails 7.2 + PostgreSQL)
# Run this locally with gcloud CLI authenticated.
#
# Prerequisites:
#   gcloud auth login
#   gcloud config set project YOUR_PROJECT_ID

set -e

# ── Configuration ────────────────────────────────────────────────────────────
PROJECT_ID="balmy-moonlight-488205-u6"   # gcloud config get-value project
INSTANCE_NAME="p2-server"
ZONE="us-central1-a"
MACHINE_TYPE="e2-standard-2"
DISK_SIZE="30GB"
DISK_TYPE="pd-balanced"
# ─────────────────────────────────────────────────────────────────────────────

echo "=== Creating VM: $INSTANCE_NAME in $ZONE ==="

gcloud compute instances create "$INSTANCE_NAME" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size="$DISK_SIZE" \
  --boot-disk-type="$DISK_TYPE" \
  --tags=http-server,https-server \
  --scopes=cloud-platform

echo "=== Creating firewall rules ==="

gcloud compute firewall-rules create allow-http \
  --project="$PROJECT_ID" \
  --allow=tcp:80 \
  --target-tags=http-server \
  --description="Allow HTTP" 2>/dev/null \
  || echo "  (allow-http rule already exists)"

gcloud compute firewall-rules create allow-https \
  --project="$PROJECT_ID" \
  --allow=tcp:443 \
  --target-tags=https-server \
  --description="Allow HTTPS" 2>/dev/null \
  || echo "  (allow-https rule already exists)"

EXTERNAL_IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --project="$PROJECT_ID" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo ""
echo "=== Done! ==="
echo ""
echo "External IP : $EXTERNAL_IP"
echo ""
echo "Next — SSH into the VM and run the setup script:"
echo "  gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=$PROJECT_ID"
echo "  bash /path/to/deploy/02-vm-setup.sh"
