#!/usr/bin/env python3
"""
Resize reference images to Android icon densities
"""
from PIL import Image
import os
import glob

# Android icon sizes
ICON_SIZES = {
    'mipmap-ldpi': 36,
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

base_dir = '../android/app/src/main/res'

# Find reference images by pattern
reference_files = glob.glob('../*参考.png')
print(f"Found {len(reference_files)} reference images:")
for f in reference_files:
    print(f"  - {os.path.basename(f)}")

# Map color keywords to theme names
# Order matters: first matched becomes default
priority_order = [
    ('粉色', 'pink', 'ic_launcher_pink.png'),      # 粉色作为默认
    ('珊瑚', 'coral', 'ic_launcher_coral.png'),
    ('青绿', 'mint', 'ic_launcher_mint.png'),
    ('星空', 'starry', 'ic_launcher_starry.png'),
]

# Ensure directories exist
for folder in ICON_SIZES.keys():
    os.makedirs(f'{base_dir}/{folder}', exist_ok=True)

# Process reference images in priority order
# First in priority_order becomes default icon
processed = {}

for keyword, theme_name, target_name in priority_order:
    # Find matching reference file
    for ref_path in reference_files:
        filename = os.path.basename(ref_path)
        if keyword in filename and filename not in processed:
            print(f"\nProcessing {theme_name}: {filename}")
            img = Image.open(ref_path)
            
            # Generate themed icon
            for folder, size in ICON_SIZES.items():
                output_path = f'{base_dir}/{folder}/{target_name}'
                resized = img.resize((size, size), Image.LANCZOS)
                resized.save(output_path, 'PNG', quality=95)
            
            # First one (粉色/pink) becomes default
            if len(processed) == 0:
                print(f"  [DEFAULT] Setting as ic_launcher.png")
                for folder, size in ICON_SIZES.items():
                    output_path = f'{base_dir}/{folder}/ic_launcher.png'
                    resized = img.resize((size, size), Image.LANCZOS)
                    resized.save(output_path, 'PNG', quality=95)
            
            processed[filename] = theme_name
            break

# Report unknown files
for ref_path in reference_files:
    filename = os.path.basename(ref_path)
    if filename not in processed:
        print(f"  Unknown: {filename}")

# Verify results
print("\n--- Verification ---")
for folder in ICON_SIZES.keys():
    path = f'{base_dir}/{folder}'
    if os.path.exists(path):
        files = sorted([f for f in os.listdir(path) if f.endswith('.png')])
        print(f"{folder}: {', '.join(files)}")

print("\nDone!")
