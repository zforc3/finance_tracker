#!/bin/sh
set -e

echo "Waiting for PostgreSQL to be ready..."
python - << 'EOF'
import sys
import time
import os
import psycopg

url = os.getenv("DATABASE_URL", "postgresql+psycopg://postgres:postgres@postgres:5432/finance_tracker")
conn_info = url.replace("postgresql+psycopg://", "postgresql://")

max_retries = 30
for i in range(max_retries):
    try:
        conn = psycopg.connect(conn_info)
        conn.close()
        print("PostgreSQL is ready!")
        sys.exit(0)
    except Exception as e:
        time.sleep(1)

print("Timed out waiting for PostgreSQL.")
sys.exit(1)
EOF

echo "Running database migrations..."
alembic upgrade head

echo "Starting application..."
exec "$@"
