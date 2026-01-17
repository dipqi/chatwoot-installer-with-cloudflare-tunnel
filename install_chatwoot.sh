#!/bin/bash

clear

LOG_FILE="/tmp/chatwoot_install_$(date +%Y%m%d_%H%M%S).log"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Memulai instalasi...${NC}"
echo -e "${GREEN}Semua log akan disimpan ke: $LOG_FILE${NC}"
echo ""

exec > >(tee -i "$LOG_FILE") 2>&1

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} SKRIP INSTALASI CHATWOOT SELF-HOSTED     ${NC}"
echo -e "${GREEN} v.0.7 (Clean Version)                    ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

echo -e "${RED}----------------------------------------------------------------${NC}"
echo -e "${RED}Silakan tempel (paste) perintah instalasi layanan Cloudflare lengkap Anda di bawah ini.${NC}"
echo -e "${RED}Contoh: sudo cloudflared service install eyJhIjoi...${NC}"
echo -e "${RED}----------------------------------------------------------------${NC}"
read -p "Perintah (Command): " CLOUDFLARE_CMD < /dev/tty

echo ""
echo -e "${RED}----------------------------------------------------------------${NC}"
echo -e "${RED}Silakan masukkan URL Frontend Chatwoot Anda.${NC}"
echo -e "${RED}Contoh: https://wa.dipqi.net${NC}"
echo -e "${RED}----------------------------------------------------------------${NC}"
read -p "URL Frontend: " FRONTEND_URL < /dev/tty

echo ""
echo -e "${GREEN}Memeriksa instalasi Docker...${NC}"

if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    echo -e "${GREEN}Docker dan Docker Compose sudah terinstal.${NC}"
    docker --version
    docker compose version
else
    echo -e "${GREEN}Docker tidak ditemukan. Sedang menginstal Docker...${NC}"
    sudo apt-get update && sudo apt-get upgrade -y
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo apt-get install -y docker-compose-plugin
    sudo systemctl start docker
    sudo systemctl enable docker
    echo -e "${GREEN}Docker berhasil diinstal.${NC}"
fi

INSTALL_DIR="$HOME/chatwoot"

echo ""
echo -e "${GREEN}Mengatur direktori di: $INSTALL_DIR ...${NC}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit

GENERATED_SECRET_KEY=$(openssl rand -hex 64)
GENERATED_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9')

echo -e "${GREEN}Sedang membuat file .env...${NC}"
cat <<EOF > .env
SECRET_KEY_BASE=$GENERATED_SECRET_KEY
FRONTEND_URL=$FRONTEND_URL
FORCE_SSL=false
ENABLE_ACCOUNT_SIGNUP=false
REDIS_URL=redis://redis:6379
REDIS_PASSWORD=$GENERATED_PASSWORD
POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=$GENERATED_PASSWORD
RAILS_ENV=production
RAILS_MAX_THREADS=5
ACTIVE_STORAGE_SERVICE=local
RAILS_LOG_TO_STDOUT=true
LOG_LEVEL=info
LOG_SIZE=500
ENABLE_PUSH_RELAY_SERVER=true
EOF

echo -e "${GREEN}Sedang membuat file docker-compose.yaml...${NC}"
cat <<EOF > docker-compose.yaml
version: '3'

services:
  base: &base
    image: chatwoot/chatwoot:latest
    env_file: .env
    volumes:
      - storage_data:/app/storage

  rails:
    <<: *base
    depends_on:
      - postgres
      - redis
    ports:
      - '127.0.0.1:3000:3000'
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    entrypoint: docker/entrypoints/rails.sh
    command: ['bundle', 'exec', 'rails', 's', '-p', '3000', '-b', '0.0.0.0']
    restart: always

  sidekiq:
    <<: *base
    depends_on:
      - postgres
      - redis
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
    command: ['bundle', 'exec', 'sidekiq', '-C', 'config/sidekiq.yml']
    restart: always

  postgres:
    image: pgvector/pgvector:pg16
    restart: always
    ports:
      - '127.0.0.1:5432:5432'
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=chatwoot
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=$GENERATED_PASSWORD

  redis:
    image: redis:alpine
    restart: always
    command: redis-server --requirepass $GENERATED_PASSWORD
    env_file: .env
    volumes:
      - redis_data:/data
    ports:
      - '127.0.0.1:6379:6379'

volumes:
  storage_data:
  postgres_data:
  redis_data:
EOF

echo -e "${GREEN}File konfigurasi berhasil dibuat.${NC}"

echo ""
echo -e "${GREEN}Menjalankan persiapan database Chatwoot...${NC}"
sudo docker compose up -d postgres redis
echo -e "${GREEN}Menunggu Database dan Redis siap (10 detik)...${NC}"
sleep 10

echo -e "${GREEN}Menjalankan migrasi database...${NC}"
sudo docker compose run --rm rails bundle exec rails db:chatwoot_prepare

echo ""
echo -e "${GREEN}Memulai semua layanan Chatwoot...${NC}"
sudo docker compose up -d

echo ""
echo -e "${GREEN}Memeriksa Cloudflared...${NC}"

if command -v cloudflared &> /dev/null; then
    echo -e "${GREEN}Cloudflared sudah terinstal.${NC}"
else
    echo -e "${GREEN}Cloudflared tidak ditemukan. Sedang menginstal...${NC}"
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
    sudo apt-get update && sudo apt-get install cloudflared -y
    echo -e "${GREEN}Cloudflared berhasil diinstal.${NC}"
fi

echo ""
echo -e "${GREEN}Mendaftarkan Tunnel Cloudflare...${NC}"
$CLOUDFLARE_CMD

echo ""
echo -e "${GREEN}Memeriksa kesehatan instalasi (menunggu respons 200 OK)...${NC}"

MAX_RETRIES=10
COUNT=0
SUCCESS=false

while [ $COUNT -lt $MAX_RETRIES ]; do
    HTTP_STATUS=$(curl -I -s -o /dev/null -w "%{http_code}" localhost:3000/api || true)
    
    if [ "$HTTP_STATUS" == "200" ]; then
        SUCCESS=true
        break
    else
        echo -e "${GREEN}Percobaan $((COUNT+1))/$MAX_RETRIES: Server merespons $HTTP_STATUS. Menunggu 15 detik...${NC}"
        sleep 15
        COUNT=$((COUNT+1))
    fi
done

echo ""
echo -e "${GREEN}============================================================${NC}"
if [ "$SUCCESS" = true ]; then
    echo -e "${GREEN}Instalasi Chatwoot Self-Hosted Anda telah selesai.${NC}"
else
    echo -e "${GREEN}Instalasi selesai, namun pemeriksaan kesehatan tidak mengembalikan 200 (Hasil: $HTTP_STATUS).${NC}"
    echo -e "${GREEN}Layanan mungkin masih dalam proses startup atau migrasi DB.${NC}"
fi
echo -e "${GREEN}Silakan kunjungi http://127.0.0.1:3000/${NC}"
echo -e "${GREEN}Lokasi Instalasi: $INSTALL_DIR${NC}"
echo -e "${GREEN}Log disimpan ke: $LOG_FILE${NC}"
echo -e "${GREEN}============================================================${NC}"
