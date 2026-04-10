# 方案2：打包字体到APK - 实施指南

## 状态：代码已配置完成 ✅

所有代码层面的配置已完成，您只需要放置字体文件即可。

---

## 已完成的工作

### 1. pubspec.yaml 已配置
```yaml
flutter:
  assets:
    - assets/fonts/NotoSansSC-Regular.otf
    - assets/fonts/NotoSansSC-Bold.otf
```

### 2. 字体服务已优化
- 优先从assets加载字体（打包的字体）
- 同时缓存到本地，加速后续使用
- 自动降级到其他方式（如果打包字体不存在）

### 3. CDN源已配置（备选）
- GitHub Raw
- jsDelivr多个节点
- ghproxy等国内代理

---

## 您需要做的

### 步骤1：获取字体文件

**方式A：浏览器下载（最简单）**

1. 浏览器打开（可能需要代理）：
   ```
   https://github.com/notofonts/noto-cjk/releases
   ```

2. 下载：`01_NotoSansCJK-OTF-VF.zip`

3. 解压，找到：
   ```
   OTF/SimplifiedChinese/NotoSansSC-Regular.otf
   OTF/SimplifiedChinese/NotoSansSC-Bold.otf
   ```

**方式B：手机网络下载**

如果电脑网络不好，可以用手机流量访问GitHub，下载后传到电脑。

### 步骤2：放置字体文件

复制到项目目录：
```
assets/fonts/
├── NotoSansSC-Regular.otf  (约8MB)
└── NotoSansSC-Bold.otf     (约8MB)
```

### 步骤3：验证

检查文件是否存在：
```bash
dir assets\fonts\*.otf
# 应该显示两个文件
```

### 步骤4：构建APK

```bash
flutter clean
flutter pub get
flutter build apk --release
```

---

## 打包后的效果

### APK体积
- 原APK：约XX MB
- 添加字体后：约XX + 16 MB

### 用户体验
- ✅ 打开PDF导出 → 立即使用（无等待）
- ✅ 无需网络下载字体
- ✅ 导出速度更快

### 日志输出
```
PDF: 开始加载中文字体...
FontDownload: 使用打包字体: NotoSansSC-Regular.otf (8.00MB)
PDF: 使用中文字体成功
```

---

## 故障排除

### 构建时提示"Asset not found"
```
Error: unable to find asset "assets/fonts/NotoSansSC-Regular.otf"
```

**解决：**
- 检查字体文件是否放置正确
- 检查文件名是否完全一致（区分大小写）

### PDF仍显示方框
**原因：** 字体文件损坏或不完整

**解决：**
- 重新下载字体文件
- 检查文件大小是否约8MB

---

## 字体文件信息

| 文件 | 大小 | MD5校验（参考） |
|------|------|----------------|
| NotoSansSC-Regular.otf | 8,000,000+ bytes | 不同版本不同 |
| NotoSansSC-Bold.otf | 8,000,000+ bytes | 不同版本不同 |

**注意：** 只要大于7MB且能正常打开就是有效文件。

---

## 总结

✅ **代码配置已完成**  
⏳ **等待您放置字体文件**  
⏳ **然后构建APK**

一旦字体文件就位，用户将获得最佳的PDF导出体验，完全不受网络环境影响！
