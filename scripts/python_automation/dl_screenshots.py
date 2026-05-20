import os
import requests
import app_store_common as common

r = requests.get(f"{common.BASE_URL}/apps/{common.APP_ID}/appStoreVersions", headers=common.hdrs(), params={"filter[platform]": "IOS", "limit": 1})
ver_id = r.json()["data"][0]["id"]
r2 = requests.get(f"{common.BASE_URL}/appStoreVersions/{ver_id}/appStoreVersionLocalizations", headers=common.hdrs())
loc_id = r2.json()["data"][0]["id"]
r3 = requests.get(f"{common.BASE_URL}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", headers=common.hdrs(), params={"include": "appScreenshots", "fields[appScreenshots]": "fileName,imageAsset,assetDeliveryState"})
data = r3.json()
sets = data.get("data", [])
included = data.get("included", [])
ss_map = {s["id"]: s for s in included if s.get("type") == "appScreenshots"}

# Setup output dir relative to the workspace root
base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out_dir = os.path.join(base_dir, "screenshots_check")
os.makedirs(out_dir, exist_ok=True)

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
            out_path = os.path.join(out_dir, f"{display}_{safe_name}")
            r = requests.get(url, timeout=30)
            if r.ok:
                with open(out_path, "wb") as f2:
                    f2.write(r.content)
                print(f"Downloaded: {out_path} ({len(r.content)//1024}KB)")
