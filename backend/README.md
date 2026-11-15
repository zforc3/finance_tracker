# Finance Tracker Backend (FastAPI + PostgreSQL)

Backend service untuk aplikasi Finance Tracker Offline-First, dibangun dengan FastAPI, SQLAlchemy 2.0, Alembic, dan PostgreSQL 16 dalam Docker Compose.

## 🚀 Fitur & Kemampuan
- **Autentikasi JWT & Refresh Token Rotation**: Endpoint `/api/v1/auth/register`, `/api/v1/auth/login`, `/api/v1/auth/refresh`, `/api/v1/auth/me`.
- **Offline-First Synchronization Engine**:
  - `POST /api/v1/sync/push`: Batch push outbox mutasi dengan Optimistic Concurrency Control (OCC) dan idempotensi berbasis `batch_id`.
  - `GET /api/v1/sync/pull`: Pull perubahan remote menggunakan ISO timestamp cursor pagination dan dukungan soft-delete (tombstone).
  - `POST /api/v1/sync/resolve-conflict`: Resolusi konflik eksplisit (`use_client` atau `use_server`).
- **Database Migrations**: Alembic migrasi otomatis dijalankan saat kontainer startup.

## 📦 Menjalankan Layanan (Docker Compose)

### Menjalankan Semua Service
```bash
cd backend
docker compose up -d
```

### Menghentikan Service
```bash
docker compose down
```

### Menjalankan Automated Integration Test
```bash
docker exec finance_tracker_api python test_api.py
```

## 🌐 Akses Layanan
- **Swagger UI (Interactive API Docs):** [http://localhost:8000/docs](http://localhost:8000/docs)
- **ReDoc:** [http://localhost:8000/redoc](http://localhost:8000/redoc)
- **OpenAPI JSON:** [http://localhost:8000/openapi.json](http://localhost:8000/openapi.json)
- **pgAdmin 4 (GUI Database):** [http://localhost:5050](http://localhost:5050)
  - **Email:** `admin@example.com`
  - **Password:** `admin`
  - **Host Database:** `postgres` (port `5432`)
- **API Base URL untuk Klien:**
  - **Windows / Web / Host:** `http://localhost:8000/api/v1`
  - **Android Emulator:** `http://10.0.2.2:8000/api/v1`
  - **Perangkat Fisik Android:** `http://<IP-LAN-Komputer>:8000/api/v1`
