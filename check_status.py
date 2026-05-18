import jwt, time, requests

ISSUER_ID = "6dd67287-cfcd-40fc-a3db-8bf378a1ac8f"
KEY_ID = "RJMPC4734X"
APP_ID = "6760955777"
SUB_ID = "0a51bcf6-383e-4354-8f5a-646aec12226f"
BASE_URL = "https://api.appstoreconnect.apple.com/v1"

with open("AuthKey_RJMPC4734X.p8") as f:
    private_key = f.read()

def make_token():
    payload = {"iss": ISSUER_ID, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})

def hdrs():
    return {"Authorization": f"Bearer {make_token()}", "Content-Type": "application/json"}

r = requests.get(f"{BASE_URL}/reviewSubmissions/{SUB_ID}", headers=hdrs())
print("Submission:", r.status_code)
if r.ok:
    data = r.json().get("data", {})
    attrs = data.get("attributes", {})
    print("  State:", attrs.get("state"))
    print("  Submitted:", attrs.get("submitted"))

r2 = requests.get(f"{BASE_URL}/apps/{APP_ID}/appStoreVersions", headers=hdrs(), params={"filter[platform]": "IOS", "limit": 5, "fields[appStoreVersions]": "versionString,appStoreState,createdDate"})
print("Versions:")
for v in r2.json().get("data", []):
    a = v.get("attributes", {})
    print(" ", a.get("versionString"), a.get("appStoreState"), str(a.get("createdDate",""))[:10])

