from PIL import Image
import os

def resize_screenshot(input_path, output_path, size):
    try:
        with Image.open(input_path) as img:
            # We will use LANCZOS for high quality resizing
            # If aspect ratio is different, we fill/crop to fit exactly
            target_w, target_h = size
            img_aspect = img.width / img.height
            target_aspect = target_w / target_h
            
            if img_aspect > target_aspect:
                # Image is wider than target, crop sides
                new_width = int(target_aspect * img.height)
                left = (img.width - new_width) / 2
                img = img.crop((left, 0, left + new_width, img.height))
            elif img_aspect < target_aspect:
                # Image is taller than target, crop top/bottom
                new_height = int(img.width / target_aspect)
                top = (img.height - new_height) / 2
                img = img.crop((0, top, img.width, top + new_height))
            
            img = img.resize(size, Image.Resampling.LANCZOS)
            img.save(output_path, quality=95)
            print(f"Generated: {output_path}")
    except Exception as e:
        print(f"Error processing {input_path}: {e}")

# Apple Screenshot Sizes
sizes = {
    "6.5": (1290, 2796),
    "5.5": (1242, 2208)
}

# Mapping: (Source File, Output Name)
mapping = [
    ("current_state_login.png", "01_login"),
    ("dashboard_cleaned_final_v3.png", "02_home"),
    ("current_state_results.png", "03_services"),
    ("current_state_checkout.png", "04_booking"),
    ("current_state_location_picker.png", "05_location")
]

root = r"c:\Users\denin\erihdev\zyiarah"
output_dir = os.path.join(root, "assets", "apple_screenshots")

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

for size_name, dimensions in sizes.items():
    size_dir = os.path.join(output_dir, size_name)
    if not os.path.exists(size_dir):
        os.makedirs(size_dir)
    
    for src_file, out_name in mapping:
        input_p = os.path.join(root, src_file)
        output_p = os.path.join(size_dir, f"{out_name}.png")
        resize_screenshot(input_p, output_p, dimensions)

print("\nDone! All screenshots are ready in assets/apple_screenshots/")
