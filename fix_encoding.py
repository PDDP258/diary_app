#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os

# 读取文件
file_path = 'lib/screens/profile_screen.dart'
with open(file_path, 'rb') as f:
    content = f.read()

# 尝试解码
try:
    text = content.decode('utf-8')
except:
    text = content.decode('latin-1')

# 常见的乱码映射
corrections = {
    '涓婚': '主题',
    '閰嶈壊': '配色',
    '鍒囨崲': '切换',
    '鏁翠釜': '整个',
    '搴旂敤': '应用',
    '鐨勯厤': '的配',
    '鑹查': '色风',
    '锟?': '格',
    '妗岄潰': '桌面',
    '鍥炬爣': '图标',
    '鏇存崲': '更换',
    '鎵嬫満': '手机',
    '妗岄潰涓婄殑': '桌面上的',
    '搴旂敤鍥炬爣': '应用图标',
    '棰滆壊': '颜色',
    '搴旂敤锟?': '应用锁',
    '鏈惎锟?': '未启用',
    '宸茶В閿佹墍鏈変富锟?': '已解锁所有主题',
    '宸叉竻锟?': '已清除',
    '椤归潰鏃ヨ': '项非日记',
    '鏁版嵁': '数据',
    '椤规暟鎹紝鏃ヨ鍜岀邯蹇垫棩淇濈暀': '项数据，日记和纪念日保留',
    '娓呴櫎澶辫触': '清除失败',
    '瑙ｉ攣涓婚澶辫触': '解锁主题失败',
    '宸茶В閿�': '已解锁',
    '鏈変富': '有主',
    '涓婚': '主题',
    '鑲簨': '颜',
    '鑹�': '颜',
    '鏍�': '格',
    '椤�': '项',
    '鏁�': '数',
    '��': '',  # 删除双问号
    '�?': '',   # 删除问号
}

# 应用修正
for old, new in corrections.items():
    text = text.replace(old, new)

# 写入修复后的文件
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print(f'已修复文件: {file_path}')
print(f'文件大小: {os.path.getsize(file_path)} bytes')
