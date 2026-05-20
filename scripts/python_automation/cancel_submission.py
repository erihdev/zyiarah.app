import time
import requests
import app_store_common as common

SUB_ID = "0a51bcf6-383e-4354-8f5a-646aec12226f"

# Cancel the submission
r = requests.post(f"{common.BASE_URL}/reviewSubmissions/{SUB_ID}/actions/cancel", headers=common.hdrs(), json={})
print(f"Cancel: {r.status_code}")
if r.text:
    print(r.text[:300])

# Check state after cancel
time.sleep(3)
r2 = requests.get(f"{common.BASE_URL}/reviewSubmissions/{SUB_ID}", headers=common.hdrs())
if r2.ok:
    state = r2.json()["data"]["attributes"]["state"]
    print(f"New state: {state}")

# Check app store version state
r3 = requests.get(f"{common.BASE_URL}/apps/{common.APP_ID}/appStoreVersions", headers=common.hdrs(),
                  params={"filter[platform]": "IOS", "limit": 1, "fields[appStoreVersions]": "versionString,appStoreState"})
v = r3.json()["data"][0]["attributes"]
print(f"Version state: {v['versionString']} = {v['appStoreState']}")
