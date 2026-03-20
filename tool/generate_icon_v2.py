#!/usr/bin/env python3
"""
「笔迹·成长」图标生成器 v2
基于详细设计规范：1024px 画布

4种配色，全部使用渐变背景：
1. 珊瑚红 - 渐变 #E85A5A → #FF8E8E
2. 青绿色 - 渐变 #3DBDB5 → #6EDDD5
3. 樱花粉 - 渐变 #E87AA8 → #FFB0D0
4. 星空主题 - 渐变 #0d0d12 → #4a2c32
"""

from PIL import Image, ImageDraw, ImageFilter
import math
import os

def create_gradient_background(size, colors, angle=135):
    """创建线性渐变背景"""
    image = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(image)
    
    # 简化渐变：从上到下
    for y in range(size):
        ratio = y / size
        r = int(colors[0][0] * (1 - ratio) + colors[1][0] * ratio)
        g = int(colors[0][1] * (1 - ratio) + colors[1][1] * ratio)
        b = int(colors[0][2] * (1 - ratio) + colors[1][2] * ratio)
        draw.line([(0, y), (size, y)], fill=(r, g, b))
    
    return image

def draw_pencil(draw, center_x, center_y, angle=45):
    """绘制铅笔主体"""
    # 笔身中心线
    length = 280
    rad = math.radians(angle)
    
    # 笔身起点（尾部）和终点（笔尖）
    end_x = center_x - length * math.cos(rad)
    end_y = center_y - length * math.sin(rad)
    
    # 笔身宽度
    width = 40
    
    # 计算笔身四个角
    perp_rad = rad + math.pi / 2
    dx = width * math.cos(perp_rad) / 2
    dy = width * math.sin(perp_rad) / 2
    
    # 笔身主体（白色）
    body_points = [
        (end_x + dx, end_y + dy),
        (center_x + dx * 0.5, center_y + dy * 0.5),
        (center_x - dx * 0.5, center_y - dy * 0.5),
        (end_x - dx, end_y - dy),
    ]
    draw.polygon(body_points, fill=(255, 255, 255))
    
    # 红色条纹
    stripe_offset = 12
    stripe_points = [
        (end_x + dx + stripe_offset * math.cos(rad), end_y + dy + stripe_offset * math.sin(rad)),
        (center_x + dx * 0.5 + stripe_offset * math.cos(rad), center_y + dy * 0.5 + stripe_offset * math.sin(rad)),
        (center_x + dx * 0.5 + (stripe_offset + 6) * math.cos(rad), center_y + dy * 0.5 + (stripe_offset + 6) * math.sin(rad)),
        (end_x + dx + (stripe_offset + 6) * math.cos(rad), end_y + dy + (stripe_offset + 6) * math.sin(rad)),
    ]
    draw.polygon(stripe_points, fill=(255, 82, 82))
    
    # 笔尖（红色三角形）
    tip_length = 35
    tip_points = [
        (center_x, center_y),
        (center_x + dx * 0.8 + tip_length * math.cos(rad), center_y + dy * 0.8 + tip_length * math.sin(rad)),
        (center_x - dx * 0.8 + tip_length * math.cos(rad), center_y - dy * 0.8 + tip_length * math.sin(rad)),
    ]
    draw.polygon(tip_points, fill=(255, 68, 68))
    
    return center_x, center_y

def draw_spiral(draw, center_x, center_y, is_starry=False):
    """绘制螺旋星轨"""
    points = []
    steps = 120
    
    for i in range(steps):
        t = i / steps
        angle = t * 2.5 * math.pi  # 两圈半
        radius = 30 + 140 * t  # 从30到170
        
        x = center_x + radius * math.cos(angle)
        y = center_y + radius * math.sin(angle)
        
        # 颜色设置
        if is_starry:
            # 星空主题：粉白渐变
            if t < 0.33:
                color = (224, 224, 224)  # 冷白
            elif t < 0.66:
                color = (255, 196, 208)  # 粉白
            else:
                color = (255, 179, 193)  # 柔粉
        else:
            # 基础配色：纯白色
            color = (255, 255, 255)
        
        # 绘制点
        dot_size = 3 if i % 2 == 0 else 2
        draw.ellipse([x-dot_size, y-dot_size, x+dot_size, y+dot_size], fill=color)
    
    # 小星球
    planet_x = center_x + 100 * math.cos(2.2)
    planet_y = center_y + 100 * math.sin(2.2)
    draw.ellipse([planet_x-8, planet_y-8, planet_x+8, planet_y+8], fill=(255, 255, 255))

def draw_star(draw, x, y, is_starry=False):
    """绘制五角星"""
    size = 50
    
    if is_starry:
        # 星空主题：红色星星 + 发光效果
        # 外层发光
        for i in range(3):
            glow_size = size + 30 - i * 10
            draw_star_shape(draw, x, y, (255, 179, 179), glow_size)
        # 主体
        draw_star_shape(draw, x, y, (255, 107, 107), size)
    else:
        # 基础配色：白色星星
        draw_star_shape(draw, x, y, (255, 255, 255), size)

def draw_star_shape(draw, x, y, color, size):
    """绘制五角星形状"""
    points = []
    for i in range(10):
        angle = math.radians(i * 36 - 90)
        r = size if i % 2 == 0 else size * 0.4
        px = x + r * math.cos(angle)
        py = y + r * math.sin(angle)
        points.append((px, py))
    
    if len(points) >= 3:
        draw.polygon(points, fill=color)

def create_icon(theme_config, filename):
    """创建单个图标"""
    size = 1024
    corner_radius = 230
    
    bg_colors = theme_config['bg_colors']
    is_starry = theme_config.get('is_starry', False)
    
    # 创建渐变背景
    image = create_gradient_background(size, bg_colors)
    
    # 创建圆角遮罩
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, size, size], radius=corner_radius, fill=255)
    
    # 应用圆角
    output = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    output.paste(image, (0, 0))
    output.putalpha(mask)
    
    draw = ImageDraw.Draw(output)
    
    # 计算笔尖位置（中心偏右下）
    center_x = size // 2 + 40
    center_y = size // 2 + 60
    
    # 绘制螺旋
    draw_spiral(draw, center_x, center_y, is_starry)
    
    # 绘制铅笔
    draw_pencil(draw, center_x, center_y, angle=45)
    
    # 绘制星星（右上角）
    star_x = size - 180
    star_y = 200
    draw_star(draw, star_x, star_y, is_starry)
    
    # 保存
    output_path = f'assets/images/{filename}'
    output.save(output_path, 'PNG')
    print(f"Generated: {output_path}")

def main():
    print("Generating app icons with gradients...")
    
    themes = {
        'coral': {
            'bg_colors': [(232, 90, 90), (255, 142, 142)],  # #E85A5A → #FF8E8E
            'is_starry': False,
        },
        'mint': {
            'bg_colors': [(61, 189, 181), (110, 221, 213)],  # #3DBDB5 → #6EDDD5
            'is_starry': False,
        },
        'pink': {
            'bg_colors': [(232, 122, 168), (255, 176, 208)],  # #E87AA8 → #FFB0D0
            'is_starry': False,
        },
        'starry': {
            'bg_colors': [(13, 13, 18), (90, 44, 50)],  # #0d0d12 → #5a2c32 更红一点
            'is_starry': True,
        },
    }
    
    for theme_name, config in themes.items():
        create_icon(config, f'icon_{theme_name}.png')
    
    # Play Store 默认图标（珊瑚红渐变）
    create_icon(themes['coral'], 'playstore_icon.png')
    
    print("\nAll icons generated!")
    print("\nThemes with gradients:")
    print("  [CORAL] 珊瑚红 - #E85A5A → #FF8E8E")
    print("  [MINT] 青绿色 - #3DBDB5 → #6EDDD5")
    print("  [PINK] 樱花粉 - #E87AA8 → #FFB0D0")
    print("  [STARRY] 星空主题 - #0d0d12 → #4a2c32")

if __name__ == "__main__":
    main()
