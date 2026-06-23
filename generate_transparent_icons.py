import os
from PIL import Image

def generate_icons(img_path):
    # Open the transparent image
    img = Image.open(img_path)
    
    # Generate Windows Icon (.ico)
    if not os.path.exists("Windows"):
        os.makedirs("Windows")
    img.save("Windows/Icon.ico", format="ICO", sizes=[(16,16), (32,32), (48,48), (64,64), (128,128), (256,256)])
    print("Generated Windows/Icon.ico")
    
    # Generate macOS Icon (.icns)
    iconset_dir = "MyIcon.iconset"
    if not os.path.exists(iconset_dir):
        os.makedirs(iconset_dir)
        
    sizes = [16, 32, 128, 256, 512]
    for size in sizes:
        # standard resolution
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(f"{iconset_dir}/icon_{size}x{size}.png")
        # high resolution
        resized_2x = img.resize((size*2, size*2), Image.Resampling.LANCZOS)
        resized_2x.save(f"{iconset_dir}/icon_{size}x{size}@2x.png")
        
    os.system(f"iconutil -c icns {iconset_dir} -o macOS/AppIcon.icns")
    print("Generated macOS/AppIcon.icns")

if __name__ == "__main__":
    generate_icons("stopwatch_transparent.png")
