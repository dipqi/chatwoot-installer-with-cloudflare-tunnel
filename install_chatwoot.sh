#!/bin/bash

# Bersihkan layar terminal sebelum mulai
clear

# ==========================================
# SKRIP INSTALASI CHATWOOT SELF-HOSTED v.0.4
# oleh Dipqi
# ==========================================

# 1. Pengaturan Log & Warna
LOG_FILE="/tmp/chatwoot_install_$(date +%Y%m%d_%H%M%S).log"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color (Reset Warna)

echo -e "${GREEN}Memulai instalasi...${NC}"
echo -e "${GREEN}Semua log akan disimpan ke: $LOG_FILE${NC}"
echo ""

# Mengalihkan semua output selanjutnya ke file log DAN terminal
exec > >(tee -i "$LOG_FILE") 2>&1

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} SKRIP INSTALASI CHATWOOT SELF-HOSTED     ${NC}"
echo -e "${GREEN} v.0.4 oleh Dipqi                         ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# 2. Prompt untuk Perintah Token Cloudflare
echo -e "${RED}----------------------------------------------------------------${NC}"
echo -e "${RED}Silakan tempel (paste) perintah instalasi layanan Cloudflare lengkap Anda di bawah ini.${NC}"
echo -e "${RED}Contoh: sudo cloudflared service install eyJhIjoi...${NC}"
echo -e "${RED}----------------------------------------------------------------${NC}"
# Menggunakan /dev/tty untuk memastikan input dibaca dari pengguna meskipun ada redirection log
read -p "Perintah (Command): " CLOUDFLARE_CMD < /dev/tty

# 3. Prompt untuk URL Frontend
echo ""
echo -e "${RED}----------------------------------------------------------------${NC}"
echo -e "${RED}Silakan masukkan URL Frontend Chatwoot Anda.${NC}"
echo -e "${RED}Contoh: https://wa.dipqi.net${NC}"
echo -e "${RED}----------------------------------------------------------------${NC}"
read -p "URL Frontend: " FRONTEND_URL < /dev/tty

# 4. Cek dan Instal Docker
echo ""
echo -e "${GREEN}[Langkah 1/7] Memeriksa instalasi Docker...${NC}"

if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    echo -e "${GREEN}Docker dan Docker Compose sudah terinstal.${NC}"
    docker --version
    docker compose version
else
    echo -e "${GREEN}Docker tidak ditemukan. Sedang menginstal Docker...${NC}"
    sudo apt-get update && sudo apt-get upgrade -y
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    
    # Instal Docker Compose Plugin jika tidak terinstal otomatis oleh get-docker.sh
    sudo apt-get install -y docker-compose-plugin
    
    # Mulai dan aktifkan Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    echo -e "${GREEN}Docker berhasil diinstal.${NC}"
fi

# 5. Membuat Direktori dan File Konfigurasi
echo ""
echo -e "${GREEN}[Langkah 2/7] Mengatur direktori dan konfigurasi Chatwoot...${NC}"

# Membuat folder dengan sudo
sudo mkdir -p /chatwoot
cd /chatwoot || exit

# Generate dynamic secrets
GENERATED_SECRET_KEY=$(openssl rand -hex 64)
# Membuat password acak yang aman untuk DB/Redis
GENERATED_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9')

# Membuat file .env (MENGGUNAKAN SUDO TEE UNTUK MENGHINDARI PERMISSION DENIED)
echo -e "${GREEN}Sedang membuat file .env...${NC}"
cat <<EOF | sudo tee .env > /dev/null
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

# Membuat file docker-compose.yaml (MENGGUNAKAN SUDO TEE UNTUK MENGHINDARI PERMISSION DENIED)
echo -e "${GREEN}Sedang membuat file docker-compose.yaml...${NC}"
cat <<EOF | sudo tee docker-compose.yaml > /dev/null
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
    command: ["sh", "-c", "redis-server --requirepass \"$REDIS_PASSWORD\""]
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

echo -e "${GREEN}File konfigurasi berhasil dibuat dengan izin root.${NC}"

# 6. Persiapan Database
echo ""
echo -e "${GREEN}[Langkah 3/7] Menjalankan persiapan database Chatwoot...${NC}"
sudo docker compose run --rm rails bundle exec rails db:chatwoot_prepare

# 7. Memulai Layanan
echo ""
echo -e "${GREEN}[Langkah 4/7] Memulai layanan Chatwoot...${NC}"
sudo docker compose up -d

# 8. Cek dan Instal Cloudflared
echo ""
echo -e "${GREEN}[Langkah 5/7] Memeriksa Cloudflared...${NC}"

if command -v cloudflared &> /dev/null; then
    echo -e "${GREEN}Cloudflared sudah terinstal. Melewati langkah instalasi.${NC}"
else
    echo -e "${GREEN}Cloudflared tidak ditemukan. Sedang menginstal...${NC}"
    
    # Tambah key gpg cloudflare
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null

    # Tambah repo ke apt repositories
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

    # instal cloudflared
    sudo apt-get update && sudo apt-get install cloudflared -y
    echo -e "${GREEN}Cloudflared berhasil diinstal.${NC}"
fi

# 9. Jalankan Perintah Cloudflare dari User
echo ""
echo -e "${GREEN}[Langkah 6/7] Mendaftarkan Tunnel Cloudflare...${NC}"
# Jalankan command user apa adanya (biasanya sudah mengandung sudo jika dicopy full)
$CLOUDFLARE_CMD

# 10. Cek Kesehatan (Health Check)
echo ""
echo -e "${GREEN}[Langkah 7/7] Memeriksa kesehatan instalasi (menunggu respons 200 OK)...${NC}"

MAX_RETRIES=5
COUNT=0
SUCCESS=false

while [ $COUNT -lt $MAX_RETRIES ]; do
    # Menggunakan || true untuk mencegah skrip berhenti jika curl gagal
    HTTP_STATUS=$(curl -I -s -o /dev/null -w "%{http_code}" localhost:3000/api || true)
    
    if [ "$HTTP_STATUS" == "200" ]; then
        SUCCESS=true
        break
    else
        echo -e "${GREEN}Percobaan $((COUNT+1))/$MAX_RETRIES: Server merespons $HTTP_STATUS. Menunggu 10 detik...${NC}"
        sleep 10
        COUNT=$((COUNT+1))
    fi
done

# 11. Output Terakhir

echo ""
echo -e "${GREEN}============================================================${NC}"
if [ "$SUCCESS" = true ]; then
    echo -e "${GREEN}Instalasi Chatwoot Self-Hosted Anda telah selesai.${NC}"
else
    echo -e "${GREEN}Instalasi selesai, namun pemeriksaan kesehatan tidak mengembalikan 200 (Hasil: $HTTP_STATUS).${NC}"
    echo -e "${GREEN}Layanan mungkin masih dalam proses startup.${NC}"
fi
echo -e "${GREEN}Silakan kunjungi http://127.0.0.1:3000/${NC}"
echo -e "${GREEN}Log disimpan ke: $LOG_FILE${NC}"
echo -e "${GREEN}============================================================${NC}"
