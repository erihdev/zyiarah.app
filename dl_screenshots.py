import jwt, time, requests

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

r = requests.get(f"{BASE_URL}/apps/{APP_ID}/appStoreVersions", headers=hdrs(), params={"filter[platform]": "IOS", "limit": 1})
ver_id = r.json()["data"][0]["id"]
r2 = requests.get(f"{BASE_URL}/appStoreVersions/{ver_id}/appStoreVersionLocalizations", headers=hdrs())
loc_id = r2.json()["data"][0]["id"]
r3 = requests.get(f"{BASE_URL}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", headers=hdrs(), params={"include": "appScreenshots", "fields[appScreenshots]": "fileName,imageAsset,assetDeliveryState"})
data = r3.json()
sets = data.get("data", [])
included = data.get("included", [])
ss_map = {s["id"]: s for s in included if s.get("type") == "appScreenshots"}

import os
os.makedirs("screenshots_check", exist_ok=True)

for s in sets:
    display = s["attributes"].get("screenshotDisplayType", "")
    for ss_ref in s.get("relationships", {}).get("appScreenshots", {}).get("data", []):
        ss = ss_map.get(ss_ref["id"], {})
        attrs = ss.get("attributes", {})
        fname = attrs.get("fileName", "unknown.jpg")
        asset = attrs.get("imageAsset", {})
        template_url = asset.get("templateUrl", "")
        if template_url:
            w = asset.get("width", 1290)
            h = asset.get("height", 2796)
            url = template_url.replace("{w}", str(w)).replace("{h}", str(h)).replace("{f}", "jpg")
            safe_name = fname.replace(" ", "_").replace(":", "-")
            out_path = f"screenshots_check/{display}_{safe_name}"
            r = requests.get(url, timeout=30)
            if r.ok:
                with open(out_path, "wb") as f2:
                    f2.write(r.content)
                print(f"Downloaded: {out_path} ({len(r.content)//1024}KB)")
