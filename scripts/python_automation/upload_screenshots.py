"""
Upload fixed iOS screenshots to App Store Connect via API.
Replaces existing iPhone 6.7" screenshots with the corrected iOS versions.
"""
import time
import requests
import os
import hashlib
import base64
import app_store_common as common

# === 1. Get version ID ===
r = requests.get(f"{common.BASE_URL}/apps/{common.APP_ID}/appStoreVersions", headers=common.hdrs(),
                 params={"filter[platform]": "IOS", "limit": 1})
ver = r.json()["data"][0]
ver_id = ver["id"]
print(f"Version: {ver['attributes']['versionString']} ({ver_id})")

# === 2. Get localization ID ===
r2 = requests.get(f"{common.BASE_URL}/appStoreVersions/{ver_id}/appStoreVersionLocalizations", headers=common.hdrs())
loc = r2.json()["data"][0]
loc_id = loc["id"]
print(f"Locale: {loc['attributes']['locale']} ({loc_id})")

# === 3. Get the iPhone 6.7" screenshot set ===
r3 = requests.get(f"{common.BASE_URL}/appStoreVersions/{loc_id}/appScreenshotSets",
                  headers=common.hdrs(), params={"include": "appScreenshots"})
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
    r = requests.delete(f"{common.BASE_URL}/appScreenshots/{ss_id}", headers=common.hdrs())
    print(f"  Deleted {ss_id}: {r.status_code}")
    time.sleep(0.5)

# === 5. Upload new screenshots ===
base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
screenshots_dir = os.path.join(base_dir, "screenshots_ios")
if not os.path.exists(screenshots_dir):
    print(f"ERROR: Directory {screenshots_dir} does not exist!")
    exit(1)

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
    r = requests.post(f"{common.BASE_URL}/appScreenshots", headers=common.hdrs(), json=payload)
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
    r = requests.patch(f"{common.BASE_URL}/appScreenshots/{ss_id}", headers=common.hdrs(), json=commit_payload)
    if r.ok:
        print(f"    Committed: OK")
    else:
        print(f"    ERROR committing: {r.status_code} {r.text[:200]}")
    time.sleep(1)

print("\n=== Done! Screenshots uploaded to App Store Connect ===")
