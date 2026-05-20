import requests
import app_store_common as common

SUB_ID = "0a51bcf6-383e-4354-8f5a-646aec12226f"
BASE = "https://api.appstoreconnect.apple.com"

# Try v2 cancel
r = requests.post(f"{BASE}/v2/reviewSubmissions/{SUB_ID}/actions/cancel", headers=common.hdrs(), json={})
print(f"v2 cancel: {r.status_code} {r.text[:200]}")

# Try DELETE on the submission
r2 = requests.delete(f"{BASE}/v1/reviewSubmissions/{SUB_ID}", headers=common.hdrs())
print(f"DELETE submission: {r2.status_code} {r2.text[:200]}")
