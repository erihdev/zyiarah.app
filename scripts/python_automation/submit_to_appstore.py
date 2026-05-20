import sys
import time
import requests
import app_store_common as common

# Force UTF-8 output
sys.stdout.reconfigure(encoding='utf-8')

TARGET_BUILD_ID = "51414a63-c75d-459f-8fdf-754ff0fbbaeb"

def get(path, params=None):
    url = path if path.startswith("http") else f"{common.BASE_URL}{path}"
    r = requests.get(url, headers=common.hdrs(), params=params)
    r.raise_for_status()
    return r.json()

def post(path, body):
    url = path if path.startswith("http") else f"{common.BASE_URL}{path}"
    r = requests.post(url, headers=common.hdrs(), json=body)
    if not r.ok:
        print(f"  POST {url} => {r.status_code}: {r.text[:300]}")
        r.raise_for_status()
    return r.json()

def patch(path, body):
    url = path if path.startswith("http") else f"{common.BASE_URL}{path}"
    r = requests.patch(url, headers=common.hdrs(), json=body)
    if not r.ok:
        print(f"  PATCH {url} => {r.status_code}: {r.text[:300]}")
        r.raise_for_status()
    return r.json()

print("=" * 60)
print("  Zyiarah App Store Submission")
print("=" * 60)

# Step 1: List all review submissions
print("\n[1] Listing review submissions...")
data = get(f"/apps/{common.APP_ID}/reviewSubmissions", {"limit": 50})
submissions = data.get("data", [])
print(f"  Found {len(submissions)} submission(s):")
for s in submissions:
    print(f"    id={s['id']}  state={s.get('attributes', {}).get('state', '?')}")

# Step 2: Cancel all open submissions
open_states = {"WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW", "UNRESOLVED_ISSUES"}
for s in submissions:
    sid = s["id"]
    state = s.get("attributes", {}).get("state", "")
    if state in open_states:
        print(f"\n[2] Cancelling {sid} (state={state})...")
        r = requests.post(f"{common.BASE_URL}/reviewSubmissions/{sid}/actions/cancel", headers=common.hdrs(), json={})
        print(f"    cancel action => {r.status_code}")
        if not r.ok:
            # Try via PATCH submitted=false
            r2 = requests.patch(f"{common.BASE_URL}/reviewSubmissions/{sid}", headers=common.hdrs(), json={
                "data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": False}}
            })
            print(f"    patch cancel => {r2.status_code}: {r2.text[:200]}")
        time.sleep(3)

print("\n  Waiting 5s for Apple to process cancellations...")
time.sleep(5)

# Step 3: Find the right App Store Version
print("\n[3] Finding App Store versions...")
v_data = get(f"/apps/{common.APP_ID}/appStoreVersions", {
    "filter[platform]": "IOS",
    "limit": 10,
    "fields[appStoreVersions]": "versionString,appStoreState,build"
})
versions = v_data.get("data", [])
target_version_id = None
for v in versions:
    vid = v["id"]
    state = v.get("attributes", {}).get("appStoreState", "?")
    ver = v.get("attributes", {}).get("versionString", "?")
    print(f"  v{ver}  id={vid}  state={state}")
    if state in ("PREPARE_FOR_SUBMISSION", "REJECTED", "DEVELOPER_REJECTED", "WAITING_FOR_REVIEW"):
        if not target_version_id:
            target_version_id = vid

if not target_version_id and versions:
    target_version_id = versions[0]["id"]

print(f"  [USE] Target version id: {target_version_id}")

# Step 4: Link our build to the App Store Version
print(f"\n[4] Linking build {TARGET_BUILD_ID} to version {target_version_id}...")
r = requests.patch(f"{common.BASE_URL}/appStoreVersions/{target_version_id}/relationships/build",
    headers=common.hdrs(),
    json={"data": {"type": "builds", "id": TARGET_BUILD_ID}})
print(f"  link result => {r.status_code}")
if r.text:
    print(f"  {r.text[:200]}")
time.sleep(3)

# Step 5: Create new review submission
print(f"\n[5] Creating new review submission...")
sub = post("/reviewSubmissions", {"data": {
    "type": "reviewSubmissions",
    "attributes": {"platform": "IOS"},
    "relationships": {"app": {"data": {"type": "apps", "id": common.APP_ID}}}
}})
new_sub_id = sub["data"]["id"]
print(f"  Created: {new_sub_id}  state={sub['data'].get('attributes', {}).get('state', '?')}")
time.sleep(3)

# Step 6: Add App Store Version to the submission
print(f"\n[6] Adding App Store Version to submission...")
item = post("/reviewSubmissionItems", {"data": {
    "type": "reviewSubmissionItems",
    "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": new_sub_id}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": target_version_id}}
    }
}})
item_id = item["data"]["id"]
print(f"  Item created: {item_id}")
time.sleep(3)

# Step 7: Confirm/submit
print(f"\n[7] Submitting for App Review...")
result = patch(f"/reviewSubmissions/{new_sub_id}", {"data": {
    "type": "reviewSubmissions",
    "id": new_sub_id,
    "attributes": {"submitted": True}
}})
final_state = result["data"].get("attributes", {}).get("state", "?")
print(f"  Final state: {final_state}")

print("\n" + "=" * 60)
print("  DONE!")
print(f"  Submission ID: {new_sub_id}")
print(f"  State: {final_state}")
print("=" * 60)
