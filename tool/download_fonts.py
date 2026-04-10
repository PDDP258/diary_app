#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PDF中文字体下载脚本（大陆网络优化版）
自动从国内CDN下载Noto Sans SC字体文件

使用方法:
    python tool/download_fonts.py
"""

import os
import sys
import urllib.request
import ssl
from pathlib import Path

# 字体配置 - 按可靠性排序
FONTS = {
    'NotoSansSC-Regular.otf': {
        'urls': [
            # GitHub Release 直接下载
            'https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/01_NotoSansCJK-OTF-VF.zip',
            # jsDelivr（文件在release中）
            'https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Regular.otf',
            'https://fastly.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Regular.otf',
            # 国内代理
            'https://ghproxy.com/https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/01_NotoSansCJK-OTF-VF.zip',
            'https://mirror.ghproxy.com/https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/01_NotoSansCJK-OTF-VF.zip',
        ],
        'size': 8 * 1024 * 1024,
        'direct_url': 'https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Regular.otf',
    },
    'NotoSansSC-Bold.otf': {
        'urls': [
            'https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/01_NotoSansCJK-OTF-VF.zip',
            'https://cdn.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Bold.otf',
            'https://fastly.jsdelivr.net/gh/notofonts/noto-cjk@Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Bold.otf',
            'https://ghproxy.com/https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/01_NotoSansCJK-OTF-VF.zip',
            'https://mirror.ghproxy.com/https://github.com/notofonts/noto-cjk/releases/download/Sans2.004/01_NotoSansCJK-OTF-VF.zip',
        ],
        'size': 8 * 1024 * 1024,
        'direct_url': 'https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/SimplifiedChinese/NotoSansSC-Bold.otf',
    },
}

# 创建SSL上下文（忽略证书验证）
ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE


def is_valid_font_header(data: bytes) -> bool:
    """验证字体文件头"""
    if len(data) < 4:
        return False
    
    # OTF字体以 "OTTO" 开头
    if data[:4] == b'OTTO':
        return True
    # TTF字体
    if data[:4] == b'\x00\x01\x00\x00':
        return True
    if data[:4] == b'true':
        return True
    
    return False


def download_with_timeout(url: str, dest_path: str, timeout: int = 60) -> bool:
    """下载文件，带超时"""
    try:
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        }
        
        request = urllib.request.Request(url, headers=headers)
        
        # 设置超时
        response = urllib.request.urlopen(
            request, 
            context=ssl_context, 
            timeout=timeout
        )
        
        if response.status == 200:
            data = response.read()
            
            # 验证文件
            if len(data) < 10000:
                print(f"    [跳过] 文件太小 ({len(data)} bytes)")
                return False
            
            if not is_valid_font_header(data):
                print(f"    [跳过] 无效的文件头")
                return False
            
            with open(dest_path, 'wb') as f:
                f.write(data)
            
            size_mb = len(data) / (1024 * 1024)
            print(f"    [成功] {size_mb:.2f} MB")
            return True
        else:
            print(f"    [失败] HTTP {response.status}")
            return False
            
    except urllib.error.HTTPError as e:
        print(f"    [失败] HTTP {e.code}")
        return False
    except Exception as e:
        print(f"    [失败] {str(e)[:40]}")
        return False


def download_font(font_name: str, config: dict, dest_dir: Path) -> bool:
    """下载单个字体"""
    print(f"\n[+] 下载: {font_name}")
    
    dest_path = dest_dir / font_name
    
    # 检查是否已存在
    if dest_path.exists():
        file_size = dest_path.stat().st_size
        if file_size > 10000:
            size_mb = file_size / (1024 * 1024)
            print(f"    [已存在] {size_mb:.2f} MB，跳过")
            return True
    
    # 尝试所有URL
    urls = config['urls']
    for i, url in enumerate(urls, 1):
        host = urllib.parse.urlparse(url).netloc[:30]
        print(f"  尝试 [{i}/{len(urls)}] {host}...")
        
        # 前3个使用短超时，后面的使用长超时
        timeout = 15 if i <= 3 else 45
        
        if download_with_timeout(url, str(dest_path), timeout):
            return True
    
    return False


def main():
    """主函数"""
    print("=" * 60)
    print("PDF中文字体下载工具（大陆网络优化版）")
    print("=" * 60)
    print()
    
    # 确定项目根目录
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    fonts_dir = project_root / 'assets' / 'fonts'
    
    print(f"字体目录: {fonts_dir}")
    print()
    
    # 创建字体目录
    fonts_dir.mkdir(parents=True, exist_ok=True)
    
    success_count = 0
    
    for font_name, config in FONTS.items():
        if download_font(font_name, config, fonts_dir):
            success_count += 1
    
    # 总结
    print("\n" + "=" * 60)
    print(f"下载结果: {success_count}/{len(FONTS)} 个字体文件")
    
    if success_count == len(FONTS):
        print()
        print("[OK] 所有字体下载成功！")
        print()
        print("下一步操作:")
        print("1. 编辑 pubspec.yaml 文件")
        print("2. 取消以下行的注释:")
        print("   - assets/fonts/NotoSansSC-Regular.otf")
        print("   - assets/fonts/NotoSansSC-Bold.otf")
        print("3. 重新构建应用: flutter build apk --release")
        return 0
    else:
        print()
        print("[警告] 部分字体下载失败")
        print()
        print("建议:")
        print("1. 检查网络连接")
        print("2. 开启代理/VPN后重试")
        print("3. 或手动下载字体文件:")
        print("   https://github.com/notofonts/noto-cjk/releases")
        return 1


if __name__ == '__main__':
    sys.exit(main())
