# 字体文件放置说明

## 方案2：打包字体到APK

此目录用于存放PDF导出所需的中文字体文件。

## 需要放置的文件

```
assets/fonts/
├── NotoSansSC-Regular.otf    (约8MB)
└── NotoSansSC-Bold.otf       (约8MB)
```

## 获取字体文件的方法

### 方法1：浏览器手动下载（推荐）

1. 打开浏览器访问：
   ```
   https://github.com/notofonts/noto-cjk/releases
   ```

2. 找到最新版本，下载文件：
   ```
   01_NotoSansCJK-OTF-VF.zip
   ```

3. 解压ZIP文件，进入目录：
   ```
   01_NotoSansCJK-OTF-VF/OTF/SimplifiedChinese/
   ```

4. 复制以下两个文件到本项目：
   ```
   NotoSansSC-Regular.otf  →  assets/fonts/NotoSansSC-Regular.otf
   NotoSansSC-Bold.otf     →  assets/fonts/NotoSansSC-Bold.otf
   ```

### 方法2：Git命令行下载

```bash
# 使用git sparse-checkout 只下载需要的文件
cd assets/fonts

# 直接下载单个文件（需要curl或wget）
curl -L -o NotoSansSC-Regular.otf \
  "https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Regular.otf"

curl -L -o NotoSansSC-Bold.otf \
  "https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Bold.otf"
```

### 方法3：使用代理/VPN

如果直接访问GitHub困难：
1. 开启代理/VPN
2. 使用上述方法1或方法2

## 验证文件

放置完成后，检查文件大小：
```bash
ls -lh assets/fonts/
# 应该显示两个约8MB的文件
```

## 构建APK

字体放置完成后，正常构建：
```bash
flutter clean
flutter pub get
flutter build apk --release
```

字体将自动打包进APK，用户无需网络下载即可使用PDF导出功能。
