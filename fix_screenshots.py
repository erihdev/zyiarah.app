"""
Replace Android status bar with a clean iOS-style status bar in all iPhone screenshots.
Keeps the original image dimensions (1290x2796).
"""
from PIL import Image, ImageDraw, ImageFont
import os, glob

STATUS_BAR_H = 130  # pixels to cover (Android bar ends around y=65, use 130 for safety)

def get_bg_color(img, y_sample=135):
    """Sample background color just below the status bar."""
    # Sample 20 pixels from the center area
    cx = img.width // 2
    colors = [img.getpixel((cx + dx, y_sample)) for dx in range(-50, 51, 10)]
    avg_r = sum(c[0] for c in colors) // len(colors)
    avg_g = sum(c[1] for c in colors) // len(colors)
    avg_b = sum(c[2] for c in colors) // len(colors)
    return (avg_r, avg_g, avg_b)

def draw_ios_status_bar(img, bg_color):
    """Draw a clean iOS-style status bar over the top portion of the image."""
    draw = ImageDraw.Draw(img)
    w = img.width

    # Fill status bar background
    draw.rectangle([0, 0, w, STATUS_BAR_H], fill=bg_color)

    # Determine text color based on background brightness
    brightness = (bg_color[0] * 299 + bg_color[1] * 587 + bg_color[2] * 114) / 1000
    text_color = (0, 0, 0) if brightness > 128 else (255, 255, 255)

    # Try to load a system font, fall back to default
    font_size = 52
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/Arial.ttf", font_size)
        font_bold = ImageFont.truetype("C:/Windows/Fonts/ArialBD.ttf", font_size)
    except:
        font = ImageFont.load_default()
        font_bold = font

    # Draw time "9:41" on the left
    time_text = "9:41"
    time_x = 80
    time_y = STATUS_BAR_H // 2 - font_size // 2
    draw.text((time_x, time_y), time_text, font=font_bold, fill=text_color)

    # Draw battery indicator on the right (simplified)
    batt_right = w - 60
    batt_y = STATUS_BAR_H // 2 - 14
    batt_w, batt_h = 60, 28
    batt_tip = 6

    # Battery outline
    draw.rectangle([batt_right - batt_w, batt_y, batt_right, batt_y + batt_h],
                   outline=text_color, width=3)
    # Battery tip
    draw.rectangle([batt_right, batt_y + batt_tip, batt_right + batt_tip, batt_y + batt_h - batt_tip],
                   fill=text_color)
    # Battery fill (100%)
    draw.rectangle([batt_right - batt_w + 4, batt_y + 4, batt_right - 4, batt_y + batt_h - 4],
                   fill=text_color)

    # Draw WiFi icon (3 arcs approximated as rectangles)
    wifi_x = batt_right - batt_w - 80
    wifi_y = STATUS_BAR_H // 2
    for i, (r, h_offset) in enumerate([(22, -16), (14, -8), (6, 0)]):
        draw.arc([wifi_x - r, wifi_y - r + h_offset, wifi_x + r, wifi_y + r + h_offset],
                 200, 340, fill=text_color, width=5)
    # Dot
    draw.ellipse([wifi_x - 4, wifi_y + 4, wifi_x + 4, wifi_y + 12], fill=text_color)

    # Draw signal bars
    sig_x = wifi_x - 80
    sig_y = STATUS_BAR_H // 2 + 14
    bar_w = 10
    for i in range(4):
        bar_h = 8 + i * 8
        x = sig_x + i * 18
        draw.rectangle([x, sig_y - bar_h, x + bar_w, sig_y], fill=text_color)

    return img

def fix_green_edges(img, edge_px=10):
    """Replace the Android green edge artifact with the adjacent content color."""
    draw = ImageDraw.Draw(img)
    w, h = img.size
    # Fix left edge
    for y in range(h):
        ref_color = img.getpixel((edge_px + 2, y))
        for x in range(edge_px):
            draw.point((x, y), fill=ref_color)
    # Fix right edge
    for y in range(h):
        ref_color = img.getpixel((w - edge_px - 3, y))
        for x in range(w - edge_px, w):
            draw.point((x, y), fill=ref_color)
    return img

def process_screenshot(input_path, output_path):
    img = Image.open(input_path).convert("RGB")
    print(f"Processing: {os.path.basename(input_path)} ({img.size})")

    # Fix green Android edge artifact first
    img = fix_green_edges(img, edge_px=8)

    bg_color = get_bg_color(img, y_sample=135)
    print(f"  Background color: {bg_color}")

    img = draw_ios_status_bar(img, bg_color)
    img.save(output_path, "PNG", optimize=False)
    print(f"  Saved: {output_path}")

# Process all iPhone 6.7 screenshots
input_dir = r"C:\Users\denin\erihdev\zyiarah\screenshots_check"
output_dir = r"C:\Users\denin\erihdev\zyiarah\screenshots_ios"
os.makedirs(output_dir, exist_ok=True)

iphone_files = [f for f in os.listdir(input_dir) if f.startswith("APP_IPHONE_67")]
for fname in iphone_files:
    process_screenshot(
        os.path.join(input_dir, fname),
        os.path.join(output_dir, fname)
    )

print("\nDone! Check screenshots_ios/ folder.")
