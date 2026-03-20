#!/usr/bin/env python3
"""
生成所有密度的 Android 启动图标
基于 Play Store 512px 图标缩放
"""

from PIL import Image
import os

# 图标尺寸映射
ICON_SIZES = {
    'mipmap-ldpi': 36,
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

def main():
    print("Generating launcher icons...")
    
    # 读取源图标
    source = Image.open('assets/images/playstore_icon.png')
    
    # 生成各密度图标
    for folder, size in ICON_SIZES.items():
        output_path = f'android/app/src/main/res/{folder}/ic_launcher.png'
        
        # 缩放图标
        resized = source.resize((size, size), Image.LANCZOS)
        resized.save(output_path, 'PNG')
        
        print(f"  {folder}: {size}x{size}px -> {output_path}")
    
    print("\nAll launcher icons generated!")

if __name__ == "__main__":
    main()
