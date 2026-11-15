# Technical Specification & Reference: Offline-first Finance Tracker

Dokumen ini merupakan acuan arsitektur teknis dan implementasi untuk **Finance Tracker (Offline-first)**, mencakup desain database lokal (Drift), database server (PostgreSQL), protokol sinkronisasi outbox, alur deteksi konflik, dan integrasi API.

---

## 1. Arsitektur Komponen

```
+-------------------------------------------------------------+
|                      FLUTTER CLIENT                         |
|                                                             |
|  [ UI Views & Riverpod State ]                              |
|              |                                              |
|              v                                              |
|  [ Repository Layer ]                                       |
|      |               |                                      |
|      v               v                                      |
|  [ Drift DB ]    [ SyncEngine ] <--- [ connectivity_plus ]   |
|  (Local Truth)   (Outbox Worker)                            |
+----------------------|--------------------------------------+
                       | HTTPS (OpenAPI v1)
                       v
+-------------------------------------------------------------+
|                     FASTAPI SERVER                          |
|                                                             |
|  [ JWT Auth Middleware ]                                    |
|              |                                              |
|              v                                              |
|  [ Sync Router (/push, /pull, /resolve-conflict) ]          |
|              |                                              |
|              v                                              |
|  [ PostgreSQL DB (Alembic Migrations) ]                     |
+-------------------------------------------------------------+
```

---

## 2. Model Data & Skema Database

### 2.1 Format ID & Nilai Uang
* **Primary Key:** `UUIDv4` dihasilkan oleh Flutter client saat transaksi dibuat (`uuid` package). Tidak ada mapping `temp_id` ke `server_id`.
* **Nilai Uang (Currency):** `BIGINT` (Rupiah murni, tanpa float/desimal).

### 2.2 Skema Drift (Client - SQLite)

#### Tabel `transactions`
| Kolom | Tipe | Keterangan |
| :--- | :--- | :--- |
| `id` | `TEXT` (PK) | UUIDv4 |
| `user_id` | `TEXT` | ID user pemilik |
| `amount` | `INT64` | Nilai nominal dalam Rupiah |
| `type` | `TEXT` | `'income'` atau `'expense'` |
| `category` | `TEXT` | Nama kategori (cth: 'Makan', 'Gaji') |
| `note` | `TEXT` (nullable) | Catatan opsional |
| `date` | `TEXT` | Format ISO tanggal lokal: `YYYY-MM-DD` |
| `version` | `INT` | Versi server terakhir yang diketahui (0 saat baru dibuat lokal) |
| `sync_status` | `TEXT` | `'synced'`, `'pending'`, `'conflict'` |
| `deleted_at` | `DATETIME` (nullable) | Tombstone jika transaksi dihapus |
| `updated_at` | `DATETIME` | Waktu perubahan terakhir lokal |

#### Tabel `sync_outbox`
| Kolom | Tipe | Keterangan |
| :--- | :--- | :--- |
| `id` | `TEXT` (PK) | UUIDv4 entri mutasi |
| `transaction_id` | `TEXT` (FK) | Relasi ke `transactions.id` |
| `action` | `TEXT` | `'create'`, `'update'`, `'delete'` |
| `base_version` | `INT` | Nilai `version` transaksi sebelum diedit |
| `payload` | `TEXT` | JSON snapshot transaksi saat aksi terjadi |
| `status` | `TEXT` | `'pending'`, `'in_flight'`, `'failed'`, `'conflict'` |
| `created_at` | `DATETIME` | Waktu aksi dicatat |

#### Tabel `sync_state`
| Kolom | Tipe | Keterangan |
| :--- | :--- | :--- |
| `key` | `TEXT` (PK) | `'last_pulled_cursor'`, `'last_sync_time'` |
| `value` | `TEXT` | Nilai status sinkronisasi |

---

### 2.3 Skema PostgreSQL (Server - SQLAlchemy)

#### Tabel `transactions`
* `id`: `UUID` (Primary Key)
* `user_id`: `UUID` (Foreign Key -> `users.id`, Indexed)
* `amount`: `BIGINT` NOT NULL
* `type`: `VARCHAR(16)` NOT NULL (`'income'`, `'expense'`)
* `category`: `VARCHAR(64)` NOT NULL
* `note`: `TEXT` NULL
* `date`: `DATE` NOT NULL (`YYYY-MM-DD`)
* `version`: `INTEGER` NOT NULL DEFAULT 1
* `deleted_at`: `TIMESTAMPTZ` NULL (Tombstone)
* `created_at`: `TIMESTAMPTZ` DEFAULT NOW()
* `updated_at`: `TIMESTAMPTZ` DEFAULT NOW()
* **Index:** `(user_id, updated_at)`, `(user_id, date)`

#### Tabel `sync_batch_log` (Idempotency Audit)
* `id`: `UUID` (Primary Key - dari `batch_id` client)
* `user_id`: `UUID`
* `processed_at`: `TIMESTAMPTZ` DEFAULT NOW()
* `items_count`: `INTEGER`

---

## 3. Protokol Sinkronisasi (Push-then-Pull)

### 3.1 Alur Push
1. Client mengambil semua entri `sync_outbox` dengan status `pending`.
2. Ubah status entri lokal menjadi `in_flight`.
3. Kirim ke `POST /api/v1/sync/push` dengan `batch_id` (UUID).
4. **Logika Server per Item:**
   * Jika item baru (`action: create`):
     * Simpan record dengan `version = 1`.
     * Kembalikan item ke daftar `applied`.
   * Jika update/delete (`action: update | delete`):
     * Ambil record di server. Jika `record.version == item.base_version`:
       * Update record dan naikkan `version = version + 1`.
       * Kembalikan item ke daftar `applied`.
     * Jika `record.version != item.base_version`:
       * Laporkan sebagai `conflicts` beserta snapshot versi server saat ini.
5. **Respons Client:**
   * Item di `applied`: hapus dari `sync_outbox`, ubah status di `transactions` menjadi `synced`, perbarui `version` ke versi server terbaru.
   * Item di `conflicts`: ubah status di `sync_outbox` & `transactions` menjadi `conflict`.

### 3.2 Alur Pull
1. Client membaca `last_pulled_cursor` dari tabel `sync_state`.
2. Panggil `GET /api/v1/sync/pull?cursor={cursor}&limit=100`.
3. **Logika Server:**
   * Mengambil semua transaksi user di mana `updated_at > cursor` diurutkan ascending.
4. **Logika Client saat Menerima Data:**
   * Untuk setiap item dari server:
     * Cek apakah ada record di local `sync_outbox` yang sedang `pending`/`in_flight` untuk `id` yang sama.
     * Jika **tidak ada**: tulis/update langsung ke database Drift lokal (`version = server_version`).
     * Jika **ada perubahan lokal yang belum terkirim**: tandai konflik lokal.
   * Simpan `next_cursor` ke tabel `sync_state`.

---

## 4. Penanganan Konflik (Conflict Resolution)

* **Deteksi:** Server mendeteksi ketika `base_version < server_version` (edit vs edit) atau jika target sudah memiliki `deleted_at` (edit vs delete).
* **UI Affordance:**
  1. Item yang berkonflik menampilkan badge warna amber/oranye (*Conflict*).
  2. Klik item memunculkan dialog pembanding:
     * **Versi Lokal:** Jumlah, kategori, tanggal, catatan.
     * **Versi Server:** Jumlah, kategori, tanggal, catatan.
  3. Pilihan Aksi:
     * **Gunakan Versi Lokal:** Client mengirim ulang push dengan `base_version = server_version` terbaru (force overwrite).
     * **Gunakan Versi Server:** Client membatalkan mutasi outbox lokal dan menimpa database lokal dengan versi server.

---

## 5. Keamanan & Autentikasi
* Password di-hash menggunakan **Argon2id** atau **Bcrypt**.
* **Access Token:** JWT masa aktif 30 menit, ditandatangani dengan rahasia HMAC-SHA256.
* **Refresh Token:** Disimpan di database server dengan status terikat ke *device/session*, masa aktif 60 hari, menggunakan rotasi token (*Refresh Token Rotation*).
* Flutter Client menyimpan token menggunakan `flutter_secure_storage` (Android Keystore / EncryptedSharedPreferences).

---

## 6. Lingkungan Pengembangan Backend (Docker & Docker Compose)

Seluruh pengembangan backend FastAPI dan PostgreSQL diisolasi di dalam kontainer Docker menggunakan **Docker Compose**.

### 6.1 Topologi Kontainer
* **Service `api`:**
  * Base Image: `python:3.12-slim` (atau Python 3.11).
  * Framework: FastAPI + Uvicorn dengan *hot-reload* aktif (`--reload`).
  * Volume Mount: Source code backend di-mount ke kontainer agar perubahan kode langsung ter-refresh.
  * Port Expose: `8000:8000`.
* **Service `db`:**
  * Base Image: `postgres:16-alpine`.
  * Persistent Volume: `postgres_data` untuk persistensi data transaksi.
  * Port Expose: `5432:5432` (untuk akses database client/GUI lokal jika diperlukan).

### 6.2 Alamat Akses Jaringan Klien (Flutter Client)
* **Android Emulator:** Mengakses backend via `http://10.0.2.2:8000/api/v1` (alias default loopback host mesin pengembangan).
* **Perangkat Android Fisik:** Mengakses backend via IP LAN komputer host (contoh: `http://192.168.x.x:8000/api/v1`) dengan firewall mengizinkan port 8000.
* **Windows / Web Client:** Mengakses backend via `http://localhost:8000/api/v1`.

