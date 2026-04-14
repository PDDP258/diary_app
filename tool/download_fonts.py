#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PDF中文字体下载脚本（大陆网络优化版）
当前项目使用 NotoSerifCJKsc-VF.ttf（思源宋体可变字体，TTF格式）。

注意：dart_pdf 库不支持 CFF-based OTF 字体处理中文，必须使用 TTF 格式。
如果assets/fonts/中已存在字体文件，通常无需运行此脚本。

如需手动获取字体：
1. 从 https://github.com/life888888/cjk-fonts-ttf/releases 下载 NotoSerifCJK-SC.zip
2. 解压后将 NotoSerifCJKsc-Regular.ttf 重命名为 NotoSerifCJKsc-VF.ttf（或直接使用VF版本）
3. 放置到 assets/fonts/ 目录

使用方法:
    python tool/download_fonts.py
"""

import os
import sys
from pathlib import Path


def main():
    """主函数"""
    print("=" * 60)
    print("PDF中文字体下载工具")
    print("=" * 60)
    print()
    
    # 确定项目根目录
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    fonts_dir = project_root / 'assets' / 'fonts'
    
    print(f"字体目录: {fonts_dir}")
    print()
    
    vf_font = fonts_dir / 'NotoSerifCJKsc-VF.ttf'
    
    if vf_font.exists() and vf_font.stat().st_size > 10000000:
        size_mb = vf_font.stat().st_size / (1024 * 1024)
        print(f"[OK] 字体文件已存在: {vf_font.name} ({size_mb:.2f} MB)")
        print()
        print("无需下载。如需重新构建应用，请运行:")
        print("  flutter build apk --release")
        return 0
    else:
        print("[提示] 字体文件未找到或过小。")
        print()
        print("由于网络上缺乏稳定直接的TTF下载源，请手动下载字体:")
        print("1. 访问 https://github.com/life888888/cjk-fonts-ttf/releases")
        print("2. 下载 NotoSerifCJK-SC.zip")
        print("3. 解压后将 TTF 字体文件放入 assets/fonts/ 目录")
        print("4. 确保文件名为 NotoSerifCJKsc-VF.ttf")
        print()
        print("或者从Windows系统字体目录复制:")
        print("  C:\\Windows\\Fonts\\NotoSerifSC-VF.ttf")
        print("到:")
        print(f"  {fonts_dir}\\NotoSerifCJKsc-VF.ttf")
        return 1


if __name__ == '__main__':
    sys.exit(main())
