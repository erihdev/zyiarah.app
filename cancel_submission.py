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

# Cancel the submission
r = requests.post(f"{BASE_URL}/reviewSubmissions/{SUB_ID}/actions/cancel", headers=hdrs(), json={})
print(f"Cancel: {r.status_code}")
if r.text:
    print(r.text[:300])

# Check state after cancel
time.sleep(3)
r2 = requests.get(f"{BASE_URL}/reviewSubmissions/{SUB_ID}", headers=hdrs())
if r2.ok:
    state = r2.json()["data"]["attributes"]["state"]
    print(f"New state: {state}")

# Check app store version state
r3 = requests.get(f"{BASE_URL}/apps/{APP_ID}/appStoreVersions", headers=hdrs(),
                  params={"filter[platform]": "IOS", "limit": 1, "fields[appStoreVersions]": "versionString,appStoreState"})
v = r3.json()["data"][0]["attributes"]
print(f"Version state: {v['versionString']} = {v['appStoreState']}")
