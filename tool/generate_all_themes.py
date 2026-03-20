#!/usr/bin/env python3
"""
生成所有主题的所有密度图标
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

# 主题配置
THEMES = {
    'coral': 'assets/images/icon_coral.png',
    'mint': 'assets/images/icon_mint.png',
    'pink': 'assets/images/icon_pink.png',
    'starry': 'assets/images/icon_starry.png',
}

def generate_theme_icons(theme_name, source_path):
    """为单个主题生成所有密度图标"""
    print(f"\nGenerating {theme_name} icons...")
    
    if not os.path.exists(source_path):
        print(f"  Source not found: {source_path}")
        return
    
    source = Image.open(source_path)
    
    for folder, size in ICON_SIZES.items():
        # 为主题创建专用目录
        output_dir = f'android/app/src/main/res/{folder}'
        if theme_name == 'coral':
            # 默认图标
            output_path = f'{output_dir}/ic_launcher.png'
        else:
            # 主题专用图标
            output_path = f'{output_dir}/ic_launcher_{theme_name}.png'
        
        # 缩放图标
        resized = source.resize((size, size), Image.LANCZOS)
        resized.save(output_path, 'PNG')
        
        print(f"  {folder}: {size}x{size}px")

def main():
    print("Generating all theme icons...")
    
    for theme_name, source_path in THEMES.items():
        generate_theme_icons(theme_name, source_path)
    
    print("\nAll theme icons generated!")
    print("\nThemes:")
    print("  [CORAL] coral - 珊瑚红（默认）")
    print("  [MINT] mint - 青绿色")
    print("  [PINK] pink - 樱花粉")
    print("  [STARRY] starry - 星空主题（商店购买）")

if __name__ == "__main__":
    main()
