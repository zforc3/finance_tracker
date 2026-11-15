import uuid
import httpx

BASE_URL = "http://localhost:8000/api/v1"

def test_full_flow():
    client = httpx.Client(base_url=BASE_URL, timeout=10.0)

    # 1. Register
    email = f"user_{uuid.uuid4().hex[:8]}@example.com"
    password = "SecurePassword123!"
    print(f"Registering user: {email}...")
    reg_resp = client.post("/auth/register", json={"email": email, "password": password})
    print("Register response:", reg_resp.status_code, reg_resp.json())
    assert reg_resp.status_code == 201

    # 2. Login
    print("Logging in...")
    login_resp = client.post("/auth/login", json={"email": email, "password": password})
    print("Login response:", login_resp.status_code)
    assert login_resp.status_code == 200
    tokens = login_resp.json()
    access_token = tokens["access_token"]
    refresh_token = tokens["refresh_token"]

    headers = {"Authorization": f"Bearer {access_token}"}

    # 3. Get profile /me
    me_resp = client.get("/auth/me", headers=headers)
    print("Me response:", me_resp.status_code, me_resp.json())
    assert me_resp.status_code == 200

    # 4. Refresh token
    print("Refreshing token...")
    ref_resp = client.post("/auth/refresh", json={"refresh_token": refresh_token})
    print("Refresh response:", ref_resp.status_code)
    assert ref_resp.status_code == 200
    new_access_token = ref_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {new_access_token}"}

    # 5. Push batch (1 transaction create)
    tx_id = str(uuid.uuid4())
    batch_id = str(uuid.uuid4())
    print(f"Pushing create transaction {tx_id}...")
    push_resp = client.post("/sync/push", headers=headers, json={
        "batch_id": batch_id,
        "items": [
            {
                "id": tx_id,
                "action": "create",
                "base_version": 0,
                "amount": 75000,
                "type": "expense",
                "category": "Makanan",
                "note": "Nasi Padang Komplit",
                "date": "2026-11-15",
                "client_updated_at": "2026-11-15T12:00:00Z"
            }
        ]
    })
    print("Push response:", push_resp.status_code, push_resp.json())
    assert push_resp.status_code == 200
    push_data = push_resp.json()
    assert len(push_data["applied"]) == 1
    assert push_data["applied"][0]["version"] == 1

    # 6. Idempotency test (push same batch_id again)
    print("Testing idempotency with same batch_id...")
    idempotent_resp = client.post("/sync/push", headers=headers, json={
        "batch_id": batch_id,
        "items": [
            {
                "id": tx_id,
                "action": "create",
                "base_version": 0,
                "amount": 75000,
                "type": "expense",
                "category": "Makanan",
                "note": "Nasi Padang Komplit",
                "date": "2026-11-15",
                "client_updated_at": "2026-11-15T12:00:00Z"
            }
        ]
    })
    print("Idempotent push response:", idempotent_resp.status_code, idempotent_resp.json())
    assert idempotent_resp.status_code == 200
    assert len(idempotent_resp.json()["applied"]) == 1

    # 7. Pull changes
    print("Pulling changes...")
    pull_resp = client.get("/sync/pull", headers=headers)
    print("Pull response:", pull_resp.status_code, pull_resp.json())
    assert pull_resp.status_code == 200
    pull_data = pull_resp.json()
    assert len(pull_data["items"]) >= 1
    found_tx = next(item for item in pull_data["items"] if item["id"] == tx_id)
    assert found_tx["amount"] == 75000
    assert found_tx["version"] == 1

    # 8. Update transaction
    update_batch_id = str(uuid.uuid4())
    print("Pushing update transaction...")
    update_resp = client.post("/sync/push", headers=headers, json={
        "batch_id": update_batch_id,
        "items": [
            {
                "id": tx_id,
                "action": "update",
                "base_version": 1,
                "amount": 80000,
                "note": "Nasi Padang + Es Teh Manis",
                "client_updated_at": "2026-11-15T12:05:00Z"
            }
        ]
    })
    print("Update push response:", update_resp.status_code, update_resp.json())
    assert update_resp.status_code == 200
    assert update_resp.json()["applied"][0]["version"] == 2

    # 9. Test conflict detection (push with outdated base_version)
    conflict_batch_id = str(uuid.uuid4())
    print("Testing conflict detection (base_version 1 when server is version 2)...")
    conflict_resp = client.post("/sync/push", headers=headers, json={
        "batch_id": conflict_batch_id,
        "items": [
            {
                "id": tx_id,
                "action": "update",
                "base_version": 1,
                "amount": 90000,
                "client_updated_at": "2026-11-15T12:10:00Z"
            }
        ]
    })
    print("Conflict response:", conflict_resp.status_code, conflict_resp.json())
    assert conflict_resp.status_code == 200
    assert len(conflict_resp.json()["conflicts"]) == 1
    assert "Version conflict" in conflict_resp.json()["conflicts"][0]["conflict_reason"]

    # 10. Resolve conflict
    print("Testing resolve conflict...")
    resolve_resp = client.post("/sync/resolve-conflict", headers=headers, json={
        "id": tx_id,
        "resolution": "use_client",
        "target_version": 2,
        "client_data": {
            "amount": 95000,
            "type": "expense",
            "category": "Makanan",
            "note": "Resolved: Nasi Padang Rendang Double",
            "date": "2026-11-15"
        }
    })
    print("Resolve response:", resolve_resp.status_code, resolve_resp.json())
    assert resolve_resp.status_code == 200
    assert resolve_resp.json()["version"] == 3
    assert resolve_resp.json()["amount"] == 95000

    print("\nALL VERIFICATION TESTS PASSED SUCCESSFULLY! 🚀")

if __name__ == "__main__":
    test_full_flow()
