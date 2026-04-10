# PDF中文字体配置指南（大陆网络优化版）

## 问题说明

由于网络原因，从海外CDN下载8MB字体文件在中国大陆地区经常失败。本指南提供多种解决方案，确保PDF导出功能可靠运行。

## 推荐方案

### 方案1：应用内下载（自动，推荐）

应用会自动尝试从多个国内CDN下载字体，无需用户操作。

**优化特点：**
- 优先使用jsDelivr国内节点
- 备选清华大学、中科大、阿里云镜像
- 智能超时策略（快速失败+长超时重试）
- 下载失败会自动使用系统字体（桌面端）

**如遇下载失败：**
1. 切换WiFi/移动数据重试
2. 检查是否开启代理/VPN
3. 尝试方案2或方案3

---

### 方案2：打包字体到APK（最可靠）⭐

将字体文件直接打包进APK，无需网络下载。

**优点：**
- ✓ 完全无需网络
- ✓ 导出PDF秒开
- ✗ APK体积增加约16MB

**步骤：**

1. **下载字体文件**

   从以下任一地址下载：
   
   **国内源（推荐）：**
   ```
   https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Regular.otf
   https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Bold.otf
   ```
   
   或使用脚本自动下载：
   ```bash
   python tool/download_fonts.py
   ```

2. **放置字体文件**

   ```
   assets/fonts/NotoSansSC-Regular.otf
   assets/fonts/NotoSansSC-Bold.otf
   ```

3. **启用字体配置**

   编辑 `pubspec.yaml`，**取消注释**字体配置：
   ```yaml
   flutter:
     uses-material-design: true
     assets:
       - assets/images/splash_cover.png
       # === 中文字体（用于PDF导出）===
       - assets/fonts/NotoSansSC-Regular.otf
       - assets/fonts/NotoSansSC-Bold.otf
   ```

4. **重新构建**

   ```bash
   flutter clean
   flutter pub get
   flutter build apk --release
   ```

---

### 方案3：手动下载后导入（给用户备选）

如果应用内下载失败，用户可以手动下载字体后导入。

**操作步骤：**
1. 从电脑下载字体文件
2. 通过文件管理器复制到手机：
   ```
   Android/data/com.example.diary_app/files/fonts/
   ```
3. 重启应用即可使用

---

## 网络优化详情

### CDN源优先级（自动选择）

| 优先级 | CDN | 特点 |
|--------|-----|------|
| 1 | jsDelivr国内节点 | 最稳定 |
| 2 | 清华大学镜像 | 教育网快 |
| 3 | 中科大镜像 | 电信快 |
| 4 | 阿里云镜像 | 全国均衡 |
| 5 | ghproxy等代理 | 备选 |

### 下载策略

```
第一轮：快速尝试（8-15秒超时）
  ↓ 失败
第二轮：长超时重试（45秒超时）
  ↓ 失败
使用系统字体（桌面端）或显示方框（移动端）
```

---

## 故障排除

### 问题1：PDF导出时一直"正在下载字体"

**原因：** 网络连接问题或CDN被墙

**解决：**
1. 等待2-3分钟（字体较大）
2. 切换网络（WiFi ↔ 移动数据）
3. 使用方案2打包字体

### 问题2：PDF中中文显示为方框 □□□

**原因：** 字体加载失败

**解决：**
1. 应用设置中清除字体缓存
2. 重启应用重试
3. 使用方案2打包字体

### 问题3：APK体积太大

**解决：** 使用字体子集化

```bash
# 使用 fonttools 提取常用3500字
pip install fonttools
pyftsubset NotoSansSC-Regular.otf \
  --text-file=common_chars.txt \
  --output-file=NotoSansSC-Regular-Subset.otf
```

可将8MB字体压缩到约800KB。

---

## 技术实现

### 字体加载优先级

```dart
1. 已缓存字体（应用文档目录）← 上次下载成功
2. Assets字体（打包在APK中）← 方案2
3. 自动下载字体（国内CDN）← 方案1
4. 系统字体（Windows/macOS/Linux）← 桌面端备用
5. 默认字体（不支持中文）← 最后手段
```

### 相关文件

| 文件 | 作用 |
|------|------|
| `lib/services/font_download_service.dart` | 字体下载和缓存 |
| `lib/services/pdf_export_service.dart` | PDF导出 |
| `tool/download_fonts.py` | 字体下载脚本 |

---

## 字体文件信息

| 文件名 | 大小 | 用途 |
|--------|------|------|
| NotoSansSC-Regular.otf | ~8MB | 常规文本 |
| NotoSansSC-Bold.otf | ~8MB | 标题粗体 |
| **合计** | **~16MB** | - |

---

## 推荐配置

### 对于个人用户
使用**方案1**（应用内下载），首次导出时等待下载完成即可。

### 对于发布到应用市场
使用**方案2**（打包字体），确保所有用户都能正常使用，无需担心网络问题。

### 对于APK体积敏感
1. 使用字体子集化（仅3500常用字）
2. 或使用方案1+网络检测提示

---

## 更新日志

- 2026-03-28: 针对大陆网络优化CDN源和下载策略
- 2026-03-28: 添加多重镜像和智能重试机制
