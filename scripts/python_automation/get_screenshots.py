import requests
import app_store_common as common

# Get version ID
r = requests.get(f"{common.BASE_URL}/apps/{common.APP_ID}/appStoreVersions", headers=common.hdrs(), params={"filter[platform]": "IOS", "limit": 1})
ver_id = r.json()["data"][0]["id"]

# Get localizations
r2 = requests.get(f"{common.BASE_URL}/appStoreVersions/{ver_id}/appStoreVersionLocalizations", headers=common.hdrs())
loc_id = r2.json()["data"][0]["id"]

# Get screenshot sets with screenshots included
r3 = requests.get(f"{common.BASE_URL}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", headers=common.hdrs(), params={"include": "appScreenshots", "fields[appScreenshots]": "sourceFileChecksum,uploadOperations,fileName,imageAsset,assetToken,assetDeliveryState"})
data = r3.json()

sets = data.get("data", [])
included = data.get("included", [])

# Build a map of screenshot id -> details
ss_map = {s["id"]: s for s in included if s.get("type") == "appScreenshots"}

for s in sets:
    display = s["attributes"].get("screenshotDisplayType", "")
    print(f"\n=== {display} ===")
    for ss_ref in s.get("relationships", {}).get("appScreenshots", {}).get("data", []):
        ss = ss_map.get(ss_ref["id"], {})
        attrs = ss.get("attributes", {})
        fname = attrs.get("fileName", "")
        asset = attrs.get("imageAsset", {})
        delivery = attrs.get("assetDeliveryState", {})
        state = delivery.get("state", "")
        template_url = asset.get("templateUrl", "")
        print(f"  {fname} - {state}")
        if template_url:
            # Replace {w} and {h} with real dims
            w = asset.get("width", 1290)
            h = asset.get("height", 2796)
            url = template_url.replace("{w}", str(w)).replace("{h}", str(h)).replace("{f}", "jpg")
            print(f"  URL: {url[:100]}...")
