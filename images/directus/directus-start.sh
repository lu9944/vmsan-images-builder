#!/bin/bash
set -e
cd /opt/directus

# Initialize .env on first boot
if [ ! -f /opt/directus/.env ]; then
    echo "[directus] Generating initial configuration..."
    echo "KEY=$(openssl rand -hex 16)" > /opt/directus/.env
    echo "SECRET=$(openssl rand -hex 32)" >> /opt/directus/.env
    echo "ADMIN_EMAIL=admin@directus.local" >> /opt/directus/.env
    echo "ADMIN_PASSWORD=Directus123!" >> /opt/directus/.env
    echo "DB_CLIENT=sqlite3" >> /opt/directus/.env
    echo "DB_FILENAME=/opt/directus/database/database.sqlite" >> /opt/directus/.env
    echo "PORT=8055" >> /opt/directus/.env
    echo "HOST=0.0.0.0" >> /opt/directus/.env
    echo "PUBLIC_URL=http://localhost:8055" >> /opt/directus/.env
fi

# Bootstrap database (creates schema and admin user - idempotent)
echo "[directus] Bootstrapping database..."
node cli.js bootstrap || echo "[directus] Bootstrap completed with warnings"

# Start Directus server
echo "[directus] Starting server on port 8055..."
exec node cli.js start
