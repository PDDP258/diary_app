# 版本更新说明

## 自动版本更新指南

每次使用AI导出APK时，请按以下步骤更新版本号：

### 版本号格式
- 当前版本: `1.0.beta`
- 更新后版本: `1.0.beta` (开发版本)

### 更新步骤

1. **更新 pubspec.yaml 中的版本号:**
   ```yaml
   version: 1.0.beta+1  # 开发版本
   ```

2. **版本号说明:**
   - 第一个数字 (0): 主版本，通常不轻易改变
   - 第二个数字 (1): 次版本，每次导出APK时+1
   - 第三个数字 (0): 修订号，用于bug修复

3. **自动递增脚本 (可选):**
   
   可以使用以下Python脚本自动更新版本:
   
   ```python
   import re
   
   with open('pubspec.yaml', 'r', encoding='utf-8') as f:
       content = f.read()
   
   # 查找版本号并增加
   match = re.search(r'version: (\d+)\.(\d+)\.(\d+)\+(\d+)', content)
   if match:
       major, minor, patch, build = map(int, match.groups())
       minor += 1  # 次版本号+1
       new_version = f'version: {major}.{minor}.{patch}+{build}'
       content = re.sub(r'version: \d+\.\d+\.\d+\+\d+', new_version, content)
       
       with open('pubspec.yaml', 'w', encoding='utf-8') as f:
           f.write(content)
       print(f'版本已更新: {new_version}')
   ```

### Android构建版本

在 `android/app/build.gradle.kts` 中:
- `versionCode`: 应该是递增的整数
- `versionName`: 应该与pubspec.yaml中的版本一致

### 更新日志

建议每次更新时在CHANGES.md中添加更新说明。
