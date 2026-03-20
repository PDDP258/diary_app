import 'dart:io';
import 'package:image/image.dart';

// 主题色 (ARGB格式)
const primaryColor = 0xFF81D8D0;  // 浅绿色
const lightColor = 0xFFB8E8E3;    // 浅绿色（加深一些）
const whiteColor = 0xFFFFFFFF;    // 白色

void main() {
  print('Generating app icons with white background...');
  
  // Android各尺寸
  final androidSizes = {
    'mipmap-ldpi': 36,
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  
  // 生成源图标
  final sourceIcon = createIcon(1024);
  Directory('assets/images').createSync(recursive: true);
  File('assets/images/app_icon.png').writeAsBytesSync(encodePng(sourceIcon));
  print('Created: assets/images/app_icon.png (1024x1024)');
  
  // 生成Android图标
  for (final entry in androidSizes.entries) {
    final icon = createIcon(entry.value);
    final path = 'android/app/src/main/res/${entry.key}/ic_launcher.png';
    File(path).writeAsBytesSync(encodePng(icon));
    print('Created: $path (${entry.value}x${entry.value})');
  }
  
  print('Done!');
}

Image createIcon(int size) {
  // 创建白色背景图像
  final image = Image(width: size, height: size);
  
  // 填充白色背景 - 使用fill方法
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixel(x, y, ColorRgb8(255, 255, 255));
    }
  }
  
  final padding = (size * 0.15).round();
  final gap = (size * 0.08).round();
  final cellSize = (size - 2 * padding - gap) ~/ 2;
  final radius = (cellSize * 0.25).round();
  
  // 四个方块的位置和颜色 (R,G,B)
  final cells = [
    (x: padding, y: padding, r: 184, g: 232, b: 227),                    // 左上 - 浅绿
    (x: padding + cellSize + gap, y: padding, r: 129, g: 216, b: 208),    // 右上 - 主题色
    (x: padding, y: padding + cellSize + gap, r: 184, g: 232, b: 227),   // 左下 - 浅绿
    (x: padding + cellSize + gap, y: padding + cellSize + gap, r: 184, g: 232, b: 227), // 右下 - 浅绿
  ];
  
  for (final cell in cells) {
    drawRoundRect(
      image,
      x: cell.x,
      y: cell.y,
      width: cellSize,
      height: cellSize,
      radius: radius,
      r: cell.r,
      g: cell.g,
      b: cell.b,
    );
  }
  
  return image;
}

// 绘制圆角矩形
void drawRoundRect(Image image, {
  required int x,
  required int y,
  required int width,
  required int height,
  required int radius,
  required int r,
  required int g,
  required int b,
}) {
  final color = ColorRgb8(r, g, b);
  
  // 绘制中间的矩形部分
  for (var py = y + radius; py < y + height - radius; py++) {
    for (var px = x + radius; px < x + width - radius; px++) {
      if (py >= 0 && py < image.height && px >= 0 && px < image.width) {
        image.setPixel(px, py, color);
      }
    }
  }
  
  // 绘制上下矩形条
  for (var py = y; py < y + radius; py++) {
    for (var px = x + radius; px < x + width - radius; px++) {
      if (py >= 0 && py < image.height && px >= 0 && px < image.width) {
        image.setPixel(px, py, color);
      }
    }
  }
  for (var py = y + height - radius; py < y + height; py++) {
    for (var px = x + radius; px < x + width - radius; px++) {
      if (py >= 0 && py < image.height && px >= 0 && px < image.width) {
        image.setPixel(px, py, color);
      }
    }
  }
  
  // 绘制左右矩形条
  for (var py = y + radius; py < y + height - radius; py++) {
    for (var px = x; px < x + radius; px++) {
      if (py >= 0 && py < image.height && px >= 0 && px < image.width) {
        image.setPixel(px, py, color);
      }
    }
    for (var px = x + width - radius; px < x + width; px++) {
      if (py >= 0 && py < image.height && px >= 0 && px < image.width) {
        image.setPixel(px, py, color);
      }
    }
  }
  
  // 绘制四个角的圆形
  drawCircle(image, x + radius, y + radius, radius, r, g, b);
  drawCircle(image, x + width - radius, y + radius, radius, r, g, b);
  drawCircle(image, x + radius, y + height - radius, radius, r, g, b);
  drawCircle(image, x + width - radius, y + height - radius, radius, r, g, b);
}

// 绘制填充圆形
void drawCircle(Image image, int cx, int cy, int radius, int r, int g, int b) {
  final color = ColorRgb8(r, g, b);
  for (var y = cy - radius; y <= cy + radius; y++) {
    for (var x = cx - radius; x <= cx + radius; x++) {
      final dx = x - cx;
      final dy = y - cy;
      if (dx * dx + dy * dy <= radius * radius) {
        if (y >= 0 && y < image.height && x >= 0 && x < image.width) {
          image.setPixel(x, y, color);
        }
      }
    }
  }
}
