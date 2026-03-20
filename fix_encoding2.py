#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os

# 读取文件
file_path = 'lib/screens/profile_screen.dart'
with open(file_path, 'rb') as f:
    content = f.read()

# 尝试解码为 utf-8
try:
    text = content.decode('utf-8')
except:
    text = content.decode('latin-1')

# 定义需要替换的乱码模式
replacements = [
    ('涓婚閰嶈壊', '主题配色'),
    ('鍒囨崲鏁翠釜搴旂敤鐨勯厤鑹查锟?', '切换整个应用的配色风格'),
    ('鏇存崲鎵嬫満妗岄潰涓婄殑搴旂敤鍥炬爣棰滆壊', '更换手机桌面上的应用图标颜色'),
    ('搴旂敤锟?', '应用锁'),
    ('鏈惎锟?', '未启用'),
    ('已启�?', '已启用'),
    ('未启�?', '未启用'),
    ('妗岄潰鍥炬爣', '桌面图标'),
    ('涓婚', '主题'),
    ('閰嶈壊', '配色'),
    ('搴旂敤', '应用'),
    ('鍥炬爣', '图标'),
    ('鏇存崲', '更换'),
    ('鎵嬫満', '手机'),
    ('妗岄潰', '桌面'),
    ('棰滆壊', '颜色'),
    ('涓撳睘', '专属'),
    ('锟?', ''),  # 删除多余的字符
    ('��', ''),   # 删除替换字符
]

# 应用替换
for old, new in replacements:
    text = text.replace(old, new)

# 修复特定行的乱码
# 行 136 附近: 主题配色
# 行 162 附近: 应用锁
lines = text.split('\n')
for i, line in enumerate(lines):
    # 修复注释和字符串中的乱码
    if '//' in line and '��' in line:
        lines[i] = line.replace('��', '')
    if "'" in line and '��' in line:
        lines[i] = line.replace('��', '')
    # 修复其他乱码模式
    if '������ɫ' in line:
        lines[i] = line.replace('������ɫ', '主题配色')
    if '�л�����Ӧ�õ���ɫ���' in line:
        lines[i] = line.replace('�л�����Ӧ�õ���ɫ���', '切换整个应用的配色风格')
    if 'Ӧ����' in line:
        lines[i] = line.replace('Ӧ����', '应用锁')
    if 'δ����' in line:
        lines[i] = line.replace('δ����', '未启用')
    if '����' in line:
        lines[i] = line.replace('����', '')

text = '\n'.join(lines)

# 写入修复后的文件
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print(f'已修复文件: {file_path}')
print(f'文件大小: {os.path.getsize(file_path)} bytes')
