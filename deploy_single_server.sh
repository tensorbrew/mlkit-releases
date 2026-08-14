#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "========================================================"
echo " Starting MLKit Single-Server Automated Deployment"
echo "========================================================"

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
if [ ! -f "$ENV_FILE" ]; then
    echo "[-] Creating production .env file with secure credentials..."
    POSTGRES_PASS=$(openssl rand -hex 16)
    REDIS_PASS=$(openssl rand -hex 16)
    
    mkdir -p backend
    cat <<EOF > "$ENV_FILE"
ENV=cloud
DATABASE_URL=postgresql://admin:${POSTGRES_PASS}@database:5432/mlkit
REDIS_URL=redis://::${REDIS_PASS}@redis:6379/0
EOF
    echo "[+] Production .env file created successfully!"
else
    echo "[+] An existing .env file was found. Skipping creation to preserve settings."
fi

# 3. Setup Reverse Proxy Configuration (Caddy)
# Domain is optional. If provided as the first argument, use it; otherwise, default to HTTP on IP.
DOMAIN=${1:-""}
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
echo "[+] Downloading Docker Compose configuration template..."
curl -fsSL https://raw.githubusercontent.com/tensorbrew/mlkit-releases/main/docker-compose.yml -o docker-compose.yml

# 5. Start Stack
echo "[+] Pulling latest container images..."
if docker compose version >/dev/null 2>&1; then
    docker compose pull
    docker compose up -d
else
    docker-compose pull
    docker-compose up -d
fi

echo "[+] Waiting for Python virtual environment and package installation to complete..."
echo "[*] Tailing backend initialization logs (this may take a few minutes on first run):"
if docker compose version >/dev/null 2>&1; then
    docker compose logs -f backend | while read -r line; do
        echo "$line"
        if [[ "$line" == *"Python packages ready!"* ]]; then
            break
        fi
    done
else
    docker-compose logs -f backend | while read -r line; do
        echo "$line"
        if [[ "$line" == *"Python packages ready!"* ]]; then
            break
        fi
    done
fi

echo "========================================================"
echo "[+] MLKit Deployment Completed Successfully!"
if [ -n "$DOMAIN" ]; then
    echo "    URL: https://$DOMAIN"
else
    echo "    URL: http://<your-server-ip>"
fi
echo "========================================================"
