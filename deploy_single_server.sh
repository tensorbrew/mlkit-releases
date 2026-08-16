#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "========================================================"
echo " Starting MLKit Single-Server Unified Deployment"
echo "========================================================"

# Initialize variables
ACCESS_TOKEN=""
OPENAI_API_KEY=""
GEMINI_API_KEY=""
CLAUDE_API_KEY=""
HF_TOKEN=""
DOMAIN=""
STORAGE_PROVIDER=""
STORAGE_PATH=""
AWS_KEY=""
AWS_SECRET=""
GCP_KEY=""
MAX_UPTIME=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--token) ACCESS_TOKEN="$2"; shift ;;
        -o|--openai) OPENAI_API_KEY="$2"; shift ;;
        -g|--gemini) GEMINI_API_KEY="$2"; shift ;;
        -c|--claude) CLAUDE_API_KEY="$2"; shift ;;
        -f|--hf) HF_TOKEN="$2"; shift ;;
        -d|--domain) DOMAIN="$2"; shift ;;
        --storage-provider) STORAGE_PROVIDER="$2"; shift ;;
        --storage-path) STORAGE_PATH="$2"; shift ;;
        --aws-key) AWS_KEY="$2"; shift ;;
        --aws-secret) AWS_SECRET="$2"; shift ;;
        --gcp-key) GCP_KEY="$2"; shift ;;
        --max-uptime) MAX_UPTIME="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# 1. Check/Install Docker and Docker Compose
if ! [ -x "$(command -v docker)" ]; then
    echo "[-] Docker is not installed. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    echo "[+] Docker installed successfully!"
else
    echo "[+] Docker is already installed."
fi

if ! [ -x "$(command -v docker-compose)" ] && ! docker compose version >/dev/null 2>&1; then
    echo "[-] Docker Compose not found. Installing..."
    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin
    echo "[+] Docker Compose installed successfully!"
else
    echo "[+] Docker Compose is available."
fi

# 2. Setup Environment Configuration (.env)
ENV_FILE="backend/.env"

if [ -n "$ACCESS_TOKEN" ]; then
    # Provisioned Mode: Always overwrite .env to apply fresh credentials
    echo "[+] Writing provisioned credentials to production .env file..."
    mkdir -p backend
    cat <<EOF > "$ENV_FILE"
ENV=cloud
DATABASE_URL=sqlite:////app/data/mlkit.db
ACCESS_TOKEN=${ACCESS_TOKEN}
EOF

    # Inject optional API keys if provided
    if [ -n "$OPENAI_API_KEY" ]; then
        echo "OPENAI_API_KEY=${OPENAI_API_KEY}" >> "$ENV_FILE"
    fi
    if [ -n "$GEMINI_API_KEY" ]; then
        echo "GEMINI_API_KEY=${GEMINI_API_KEY}" >> "$ENV_FILE"
    fi
    if [ -n "$CLAUDE_API_KEY" ]; then
        echo "CLAUDE_API_KEY=${CLAUDE_API_KEY}" >> "$ENV_FILE"
        echo "ANTHROPIC_API_KEY=${CLAUDE_API_KEY}" >> "$ENV_FILE"
    fi
    if [ -n "$HF_TOKEN" ]; then
        echo "HF_TOKEN=${HF_TOKEN}" >> "$ENV_FILE"
    fi
    echo "[+] Production .env file updated successfully!"
else
    # Standard Mode: Preserve existing configuration if found
    if [ ! -f "$ENV_FILE" ]; then
        echo "[-] Creating default production .env file..."
        mkdir -p backend
        cat <<EOF > "$ENV_FILE"
ENV=cloud
DATABASE_URL=sqlite:////app/data/mlkit.db
EOF
        echo "[+] Production .env file created successfully!"
    else
        echo "[+] An existing .env file was found. Skipping creation to preserve settings."
    fi
fi

# Setup storage sync and telemetry configurations in /var/lib/mlkit/.env
if [ -n "$STORAGE_PATH" ] || [ -n "$MAX_UPTIME" ]; then
    echo "[+] Writing storage sync and telemetry credentials to /var/lib/mlkit/.env..."
    sudo mkdir -p /var/lib/mlkit
    sudo touch /var/lib/mlkit/.env
    sudo chmod 600 /var/lib/mlkit/.env
    
    cat <<EOF | sudo tee /var/lib/mlkit/.env > /dev/null
CLOUD_PROVIDER=${STORAGE_PROVIDER}
CLOUD_SYNC_PATH=${STORAGE_PATH}
AWS_ACCESS_KEY_ID=${AWS_KEY}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET}
GCP_SERVICE_ACCOUNT_KEY=${GCP_KEY}
MAX_RUN_HOURS=${MAX_UPTIME}
EOF
fi

# 3. Setup Reverse Proxy Configuration (Caddy)
CADDYFILE="CADDYFILE"

if [ -n "$DOMAIN" ]; then
    echo "[+] Configuring Caddy with SSL for domain: $DOMAIN"
    cat <<EOF > "$CADDYFILE"
$DOMAIN {
    reverse_proxy /api/* backend:8000
    reverse_proxy /* frontend:80
}
EOF
else
    echo "[+] No domain provided. Configuring Caddy for HTTP access on port 80..."
    cat <<EOF > "$CADDYFILE"
:80 {
    reverse_proxy /api/* backend:8000
    reverse_proxy /* frontend:80
}
EOF
fi

# 4. Download Docker Compose Configuration template
if [ ! -f "docker-compose.yml" ]; then
    echo "[+] Downloading Docker Compose configuration template..."
    curl -fsSL https://raw.githubusercontent.com/tensorbrew/mlkit-releases/main/docker-compose.yml -o docker-compose.yml
fi

# 5. Start Stack
echo "[+] Pulling latest container images..."
if docker compose version >/dev/null 2>&1; then
    docker compose pull
    docker compose up -d
else
    docker-compose pull
    docker-compose up -d
fi

echo "[+] Waiting for Python backend and package installation to complete..."
echo "[*] Tailing backend initialization logs:"
if docker compose version >/dev/null 2>&1; then
    docker compose logs -f backend | while read -r line; do
        echo "$line"
        if [[ "$line" == *"Custom packages setup complete!"* ]]; then
            break
        fi
    done
else
    docker-compose logs -f backend | while read -r line; do
        echo "$line"
        if [[ "$line" == *"Custom packages setup complete!"* ]]; then
            break
        fi
    done
fi

echo "========================================================"
echo "[+] MLKit Deployment Completed Successfully!"
if [ -n "$DOMAIN" ]; then
    if [ -n "$ACCESS_TOKEN" ]; then
        echo "    URL: https://$DOMAIN/?access_token=$ACCESS_TOKEN"
    else
        echo "    URL: https://$DOMAIN"
    fi
else
    if [ -n "$ACCESS_TOKEN" ]; then
        echo "    URL: http://<your-server-ip>/?access_token=$ACCESS_TOKEN"
    else
        echo "    URL: http://<your-server-ip>"
    fi
fi
echo "========================================================"
