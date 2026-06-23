from PIL import Image
import os
import subprocess

img_path = "/Users/kyle/.gemini/antigravity/brain/df7261e3-faaf-4818-8f07-a22085439ba2/stopwatch_edit_1782234633029.png"
img = Image.open(img_path)

# Windows ICO
img.save("Windows/Icon.ico", format="ICO", sizes=[(16,16), (32,32), (48,48), (64,64), (128,128), (256,256)])

# macOS ICNS
os.makedirs("MyIcon.iconset", exist_ok=True)
configs = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for name, size in configs:
    resized = img.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(f"MyIcon.iconset/{name}")

subprocess.run(["iconutil", "-c", "icns", "MyIcon.iconset", "-o", "macOS/AppIcon.icns"])
