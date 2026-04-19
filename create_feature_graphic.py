from PIL import Image, ImageDraw

def create_feature_graphic():
    width, height = 1024, 500
    # Create gradient background (Purple to Dark Purple)
    base = Image.new('RGB', (width, height), (75, 0, 130))
    top = (75, 0, 130)
    bottom = (40, 0, 80)
    
    draw = ImageDraw.Draw(base)
    for y in range(height):
        r = top[0] + (bottom[0] - top[0]) * y // height
        g = top[1] + (bottom[1] - top[1]) * y // height
        b = top[2] + (bottom[2] - top[2]) * y // height
        draw.line((0, y, width, y), fill=(r, g, b))

    # Load and process logo
    try:
        logo = Image.open(r'c:\Users\denin\erihdev\zyiarah\assets\logo.png').convert("RGBA")
        
        # Resize logo to fit nicely
        logo_aspect = logo.width / logo.height
        new_h = 300
        new_w = int(new_h * logo_aspect)
        logo = logo.resize((new_w, new_h), Image.Resampling.LANCZOS)
        
        # Paste logo on center (handling transparency correctly)
        pos = ((width - new_w) // 2, (height - new_h) // 2)
        base.paste(logo, pos, logo)
        
        base.save(r'c:\Users\denin\erihdev\zyiarah\assets\play_store_feature_graphic.png')
        print("Success: Feature Graphic created.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    create_feature_graphic()
