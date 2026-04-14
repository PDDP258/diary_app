# 字体文件放置说明

## PDF中文字体

此目录用于存放PDF导出所需的中文字体文件。

## 当前使用的字体

```
assets/fonts/
└── NotoSerifCJKsc-VF.ttf    (约25MB)
```

**重要说明：**
- 必须使用 **TTF 格式**（TrueType轮廓）
- **禁止使用 CFF-based OTF 格式**，因为 `dart_pdf` 库无法对这类字体进行中文Unicode编码
- 使用 **可变字体（VF）**，一个文件同时支持 Regular 和 Bold 字重

## 获取字体文件的方法

### 方法1：从Windows系统复制（最简单）

如果您的电脑是Windows系统，通常已安装该字体：

```
C:\Windows\Fonts\NotoSerifSC-VF.ttf
```

直接复制到项目目录：
```
assets/fonts/NotoSerifCJKsc-VF.ttf
```

### 方法2：手动下载TTF版本

1. 访问第三方TTF发布页：
   ```
   https://github.com/life888888/cjk-fonts-ttf/releases
   ```

2. 下载 `NotoSerifCJK-SC.zip`

3. 解压后找到 `NotoSerifCJKsc-Regular.ttf`，可重命名为 `NotoSerifCJKsc-VF.ttf` 使用

### 方法3：使用项目脚本检查

```bash
python tool/download_fonts.py
```

## 验证文件

放置完成后，检查文件大小：
```bash
ls -lh assets/fonts/
# 应该显示一个约25MB的TTF文件
```

## 构建APK

字体放置完成后，正常构建：
```bash
flutter clean
flutter pub get
flutter build apk --release
```

字体将自动打包进APK，用户无需网络下载即可正常使用PDF导出功能。
