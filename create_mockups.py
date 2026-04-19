from PIL import Image, ImageDraw, ImageFont
import os

def create_mockup(filename, title_text, bg_color, logo_path):
    width, height = 1080, 1920 # Standard mobile screenshot size
    img = Image.new('RGB', (width, height), bg_color)
    draw = ImageDraw.Draw(img)
    
    # Load logo
    try:
        logo = Image.open(logo_path).convert("RGBA")
        logo_w = 400
        logo_h = int(logo_w * logo.height / logo.width)
        logo = logo.resize((logo_w, logo_h), Image.Resampling.LANCZOS)
        img.paste(logo, ((width - logo_w) // 2, 300), logo)
    except:
        pass
        
    # Draw a "phone frame" look
    draw.rectangle([100, 600, 980, 1700], outline=(255,255,255), width=20)
    
    # Save the mockup
    output_path = f'c:/Users/denin/erihdev/zyiarah/assets/{filename}.png'
    img.save(output_path)
    print(f"Mockup created: {output_path}")

logo_p = r'c:\Users\denin\erihdev\zyiarah\assets\logo.png'
create_mockup("ss_home", "حجز سهل وسريع", (75, 0, 130), logo_p)
create_mockup("ss_services", "خدمات متنوعة", (40, 0, 80), logo_p)
create_mockup("ss_tracking", "تتبع طلبك بكل سهولة", (154, 205, 50), logo_p)
