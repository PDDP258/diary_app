#!/usr/bin/env python3
"""
生成 Play Store 应用商店图标
「笔迹·成长」512px × 512px

设计规范：
- 尺寸：512px × 512px
- 格式：PNG（32位透明）
- 背景：珊瑚红渐变 #FF6B6B → #FF8E8E
- 图形：白色笔 + 螺旋轨迹 + 星星
- 安全边距：四周留 48px 透明边距
"""

from PIL import Image, ImageDraw
import math

# 画布尺寸
CANVAS_SIZE = 512
# 安全边距
SAFE_MARGIN = 48
# 有效绘图区域
DRAW_SIZE = CANVAS_SIZE - (SAFE_MARGIN * 2)
# 中心点
CENTER = CANVAS_SIZE // 2

# 颜色定义
BACKGROUND_TOP = (255, 107, 107)      # #FF6B6B 珊瑚红
BACKGROUND_BOTTOM = (255, 142, 142)   # #FF8E8E 浅珊瑚
FOREGROUND = (255, 255, 255)          # 白色

def create_gradient_background(size, color_top, color_bottom):
    """创建渐变背景"""
    image = Image.new('RGB', (size, size))
    for y in range(size):
        ratio = y / size
        r = int(color_top[0] * (1 - ratio) + color_bottom[0] * ratio)
        g = int(color_top[1] * (1 - ratio) + color_bottom[1] * ratio)
        b = int(color_top[2] * (1 - ratio) + color_bottom[2] * ratio)
        for x in range(size):
            image.putpixel((x, y), (r, g, b))
    return image

def draw_archimedean_spiral(draw, center_x, center_y, start_radius, end_radius, 
                            start_angle, end_angle, line_width, color):
    """绘制阿基米德螺线"""
    points = []
    steps = 100
    
    for i in range(steps + 1):
        t = i / steps
        angle = start_angle + (end_angle - start_angle) * t
        radius = start_radius + (end_radius - start_radius) * t
        
        x = center_x + radius * math.cos(angle)
        y = center_y + radius * math.sin(angle)
        points.append((x, y))
    
    # 绘制线段
    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=color, width=line_width)
    
    return points

def draw_pen_tip(draw, x, y, size, color):
    """绘制笔尖（菱形）"""
    # 菱形四个点
    points = [
        (x, y - size),      # 上
        (x + size, y),      # 右
        (x, y + size),      # 下
        (x - size, y),      # 左
    ]
    draw.polygon(points, fill=color)

def draw_pen_body(draw, x, y, length, angle, width, color):
    """绘制笔杆"""
    # 笔杆方向（与笔尖相反）
    rad = math.radians(angle + 180)
    end_x = x + length * math.cos(rad)
    end_y = y + length * math.sin(rad)
    
    # 绘制笔杆主体
    draw.line([(x, y), (end_x, end_y)], fill=color, width=width)
    
    return (end_x, end_y)

def draw_star(draw, cx, cy, size, color):
    """绘制四角星（四芒星）"""
    # 四角星的 8 个点
    points = []
    for i in range(8):
        angle = math.radians(i * 45 - 90)  # 从顶部开始
        if i % 2 == 0:
            # 长角
            r = size
        else:
            # 短角
            r = size * 0.4
        x = cx + r * math.cos(angle)
        y = cy + r * math.sin(angle)
        points.append((x, y))
    
    draw.polygon(points, fill=color)

def draw_dotted_line(draw, points, dot_radius, color, alpha=200):
    """沿路径绘制点状装饰"""
    for i in range(0, len(points), 10):
        if i < len(points):
            x, y = points[i]
            # 使用透明度
            draw.ellipse([x - dot_radius, y - dot_radius, 
                         x + dot_radius, y + dot_radius], 
                        fill=(*color, alpha))

def main():
    # 创建渐变背景
    print("Generating Play Store icon...")
    image = create_gradient_background(CANVAS_SIZE, BACKGROUND_TOP, BACKGROUND_BOTTOM)
    draw = ImageDraw.Draw(image, 'RGBA')
    
    # 缩放因子（将 108dp 设计稿映射到 512px）
    scale = DRAW_SIZE / 108
    offset_x = SAFE_MARGIN
    offset_y = SAFE_MARGIN
    
    def to_px(x, y):
        """将设计稿坐标转换为像素坐标"""
        return (offset_x + x * scale, offset_y + y * scale)
    
    # ========== 绘制「笔迹·成长」图标 ==========
    
    # 1. 绘制螺旋轨迹（阿基米德螺线 1.5 圈）
    spiral_center_x = 46
    spiral_center_y = 52
    
    # 螺线路径点
    spiral_points = []
    steps = 150
    for i in range(steps + 1):
        t = i / steps
        theta = t * 1.5 * math.pi  # 1.5 圈
        r = 4 + 18 * t  # 半径从 4 到 22
        
        x = spiral_center_x + r * math.cos(theta - math.pi/2)
        y = spiral_center_y + r * math.sin(theta - math.pi/2)
        spiral_points.append(to_px(x, y))
    
    # 绘制螺线（分段绘制实现渐变线宽效果）
    for i in range(len(spiral_points) - 1):
        t = i / len(spiral_points)
        width = int(2 + t * 2)  # 线宽从 2 渐变到 4
        draw.line([spiral_points[i], spiral_points[i + 1]], 
                 fill=(*FOREGROUND, 240), width=width)
    
    # 2. 绘制笔尖（菱形）- 位于螺线起点
    pen_tip_x, pen_tip_y = 38, 42
    pen_tip_px = to_px(pen_tip_x, pen_tip_y)
    draw_pen_tip(draw, pen_tip_px[0], pen_tip_px[1], 6, (*FOREGROUND, 255))
    
    # 3. 绘制笔杆
    pen_end_x, pen_end_y = 28, 52
    pen_end_px = to_px(pen_end_x, pen_end_y)
    draw.line([pen_tip_px, pen_end_px], fill=(*FOREGROUND, 230), width=10)
    
    # 笔尾装饰
    tail_x, tail_y = 24, 56
    tail_px = to_px(tail_x, tail_y)
    draw.ellipse([tail_px[0] - 6, tail_px[1] - 6, 
                  tail_px[0] + 6, tail_px[1] + 6], 
                 fill=(*FOREGROUND, 200))
    
    # 4. 绘制星星（四角星）- 右上区域
    star_x, star_y = 62, 38
    star_px = to_px(star_x, star_y)
    draw_star(draw, star_px[0], star_px[1], 14, (*FOREGROUND, 240))
    
    # 星星中心高光
    draw.ellipse([star_px[0] - 4, star_px[1] - 4, 
                  star_px[0] + 4, star_px[1] + 4], 
                 fill=(*FOREGROUND, 180))
    
    # 5. 轨迹上的小点装饰
    for i in range(0, len(spiral_points), 25):
        if i < len(spiral_points):
            x, y = spiral_points[i]
            radius = 3 if i % 50 == 0 else 2
            alpha = 200 if i % 50 == 0 else 140
            draw.ellipse([x - radius, y - radius, 
                         x + radius, y + radius], 
                        fill=(*FOREGROUND, alpha))
    
    # 螺线终点装饰
    end_point = spiral_points[-1]
    draw.ellipse([end_point[0] - 5, end_point[1] - 5, 
                  end_point[0] + 5, end_point[1] + 5], 
                 fill=(*FOREGROUND, 230))
    
    # 保存图片
    output_path = "assets/images/playstore_icon.png"
    image.save(output_path, "PNG")
    print("Play Store icon generated: " + output_path)
    print("Size: " + str(CANVAS_SIZE) + "x" + str(CANVAS_SIZE) + "px")
    print("Format: PNG (32-bit)")
    print("Theme: Brushstroke Growth (Coral Red)")

if __name__ == "__main__":
    main()
