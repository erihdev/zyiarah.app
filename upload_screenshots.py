"""
Upload fixed iOS screenshots to App Store Connect via API.
Replaces existing iPhone 6.7" screenshots with the corrected iOS versions.
"""
import jwt, time, requests, os, json, hashlib, base64

ISSUER_ID = "6dd67287-cfcd-40fc-a3db-8bf378a1ac8f"
KEY_ID = "RJMPC4734X"
APP_ID = "6760955777"
BASE_URL = "https://api.appstoreconnect.apple.com/v1"

with open("AuthKey_RJMPC4734X.p8") as f:
    private_key = f.read()

def make_token():
    payload = {"iss": ISSUER_ID, "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})

def hdrs():
    return {"Authorization": f"Bearer {make_token()}", "Content-Type": "application/json"}

# === 1. Get version ID ===
r = requests.get(f"{BASE_URL}/apps/{APP_ID}/appStoreVersions", headers=hdrs(),
                 params={"filter[platform]": "IOS", "limit": 1})
ver = r.json()["data"][0]
ver_id = ver["id"]
print(f"Version: {ver['attributes']['versionString']} ({ver_id})")

# === 2. Get localization ID ===
r2 = requests.get(f"{BASE_URL}/appStoreVersions/{ver_id}/appStoreVersionLocalizations", headers=hdrs())
loc = r2.json()["data"][0]
loc_id = loc["id"]
print(f"Locale: {loc['attributes']['locale']} ({loc_id})")

# === 3. Get the iPhone 6.7" screenshot set ===
r3 = requests.get(f"{BASE_URL}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets",
                  headers=hdrs(), params={"include": "appScreenshots"})
data = r3.json()
sets = data.get("data", [])
included = data.get("included", [])
ss_map = {s["id"]: s for s in included if s.get("type") == "appScreenshots"}

iphone_set = None
for s in sets:
    if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67":
        iphone_set = s
        break

if not iphone_set:
    print("ERROR: iPhone 6.7 screenshot set not found!")
    exit(1)

set_id = iphone_set["id"]
print(f"iPhone 6.7 set: {set_id}")

# === 4. Delete existing screenshots ===
existing_ids = [ss["id"] for ss in iphone_set.get("relationships", {}).get("appScreenshots", {}).get("data", [])]
print(f"Deleting {len(existing_ids)} existing screenshots...")
for ss_id in existing_ids:
    r = requests.delete(f"{BASE_URL}/appScreenshots/{ss_id}", headers=hdrs())
    print(f"  Deleted {ss_id}: {r.status_code}")
    time.sleep(0.5)

# === 5. Upload new screenshots ===
screenshots_dir = "screenshots_ios"
files = sorted([f for f in os.listdir(screenshots_dir) if f.startswith("APP_IPHONE_67")])
print(f"\nUploading {len(files)} new screenshots...")

for i, fname in enumerate(files):
    fpath = os.path.join(screenshots_dir, fname)
    with open(fpath, "rb") as f:
        file_data = f.read()

    file_size = len(file_data)
    md5 = base64.b64encode(hashlib.md5(file_data).digest()).decode()

    # Create screenshot reservation
    payload = {
        "data": {
            "type": "appScreenshots",
            "attributes": {
                "fileSize": file_size,
                "fileName": fname
            },
            "relationships": {
                "appScreenshotSet": {
                    "data": {"type": "appScreenshotSets", "id": set_id}
                }
            }
        }
    }
    r = requests.post(f"{BASE_URL}/appScreenshots", headers=hdrs(), json=payload)
    if not r.ok:
        print(f"  ERROR creating screenshot {fname}: {r.status_code} {r.text[:200]}")
        continue

    ss_data = r.json()["data"]
    ss_id = ss_data["id"]
    upload_ops = ss_data["attributes"]["uploadOperations"]
    print(f"  [{i+1}/{len(files)}] {fname} - created {ss_id}")

    # Upload file parts
    for op in upload_ops:
        offset = op["offset"]
        length = op["length"]
        url = op["url"]
        method = op["method"]
        request_headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}

        chunk = file_data[offset:offset + length]
        r_up = requests.request(method, url, data=chunk, headers=request_headers, timeout=60)
        if not r_up.ok:
            print(f"    ERROR uploading chunk: {r_up.status_code}")
        else:
            print(f"    Uploaded chunk {offset}-{offset+length}: OK")

    # Commit the screenshot
    commit_payload = {
        "data": {
            "type": "appScreenshots",
            "id": ss_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": md5
            }
        }
    }
    r = requests.patch(f"{BASE_URL}/appScreenshots/{ss_id}", headers=hdrs(), json=commit_payload)
    if r.ok:
        print(f"    Committed: OK")
    else:
        print(f"    ERROR committing: {r.status_code} {r.text[:200]}")
    time.sleep(1)

print("\n=== Done! Screenshots uploaded to App Store Connect ===")
