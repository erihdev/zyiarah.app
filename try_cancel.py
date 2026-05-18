import jwt, time, requests

ISSUER_ID = "6dd67287-cfcd-40fc-a3db-8bf378a1ac8f"
KEY_ID = "RJMPC4734X"
SUB_ID = "0a51bcf6-383e-4354-8f5a-646aec12226f"
APP_ID = "6760955777"

with open("AuthKey_RJMPC4734X.p8") as f:
    private_key = f.read()

def make_token():
    payload = {"iss": ISSUER_ID, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})

def hdrs():
    return {"Authorization": f"Bearer {make_token()}", "Content-Type": "application/json"}

BASE = "https://api.appstoreconnect.apple.com"

# Try v2 cancel
r = requests.post(f"{BASE}/v2/reviewSubmissions/{SUB_ID}/actions/cancel", headers=hdrs(), json={})
print(f"v2 cancel: {r.status_code} {r.text[:200]}")

# Try DELETE on the submission
r2 = requests.delete(f"{BASE}/v1/reviewSubmissions/{SUB_ID}", headers=hdrs())
print(f"DELETE submission: {r2.status_code} {r2.text[:200]}")
