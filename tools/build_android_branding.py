#!/usr/bin/env python3
"""Render AI Story RPG's reproducible launcher icon and system splash assets.

Only touches generated Android resources after flutter create. Does not modify
applicationId, signing, or any app data.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("apps/story_reader/android/app/src/main/res")
if not root.exists():
    raise SystemExit(f"Android resources not generated: {root}")

N = 1024
bg = (29, 31, 35, 255)
bronze = (217, 190, 146, 255)
paper = (246, 242, 233, 255)
img = Image.new("RGBA", (N, N), bg)
d = ImageDraw.Draw(img)
# Strong silhouette: two open pages with a center spine.
d.rounded_rectangle((160, 270, 500, 760), radius=58, fill=paper)
d.rounded_rectangle((524, 270, 864, 760), radius=58, fill=paper)
d.polygon([(500, 290), (512, 343), (524, 290), (524, 756), (512, 797), (500, 756)], fill=bronze)
d.arc((213, 335, 470, 548), 200, 345, fill=bronze, width=23)
d.arc((554, 335, 811, 548), 195, 345, fill=bronze, width=23)
# An opening/portal between the pages. Keep all strokes legible at 48px.
d.ellipse((436, 160, 588, 312), fill=bronze)
d.ellipse((475, 199, 549, 273), fill=bg)
d.line([(512, 110), (512, 143)], fill=bronze, width=19)
d.line([(413, 190), (390, 165)], fill=bronze, width=16)
d.line([(610, 190), (633, 165)], fill=bronze, width=16)

for density, px in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)]:
    folder = root / f"mipmap-{density}"
    folder.mkdir(parents=True, exist_ok=True)
    img.resize((px,px), Image.Resampling.LANCZOS).save(folder / "ic_launcher.png")

# Dedicated centered image for legacy splash; Android 12+ defaults to launcher
# icon from the generated theme when no custom animated splash is configured.
splash = root / "drawable-nodpi"
splash.mkdir(exist_ok=True)
img.resize((300,300), Image.Resampling.LANCZOS).save(splash / "ai_story_splash.png")
drawable = root / "drawable"
drawable.mkdir(exist_ok=True)
(drawable / "launch_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '  <item android:drawable="#1D1F23"/>\n'
    '  <item><bitmap android:gravity="center" android:src="@drawable/ai_story_splash"/></item>\n'
    '</layer-list>\n', encoding="utf-8")
print(f"Branding resources generated in {root}")
