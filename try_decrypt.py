#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import zipfile
import os

# MBK文件路径
file_path = r'zz/Diary_1771591768560.mbk'

# 尝试的密码列表
passwords = [
    '23258',
    '13086166534pp',
    '13086166534',
]

print('=' * 50)
print('MBK文件解密尝试')
print('=' * 50)
print(f'文件: {file_path}')
print(f'文件大小: {os.path.getsize(file_path)} bytes')
print()

# 首先检查ZIP内容（不解密）
try:
    with zipfile.ZipFile(file_path, 'r') as zf:
        print('ZIP文件内容列表:')
        for name in zf.namelist()[:10]:  # 只显示前10个
            try:
                info = zf.getinfo(name)
                print(f'  - {name}')
                print(f'    压缩后: {info.compress_size} bytes, 原始: {info.file_size} bytes')
            except:
                print(f'  - {name}')
        print()
except Exception as e:
    print(f'读取ZIP文件列表失败: {e}')
    print()

# 尝试用密码解密
print('开始尝试密码...')
print('-' * 50)

success = False
for pwd in passwords:
    try:
        print(f'\n尝试密码: "{pwd}"')
        
        with zipfile.ZipFile(file_path, 'r') as zf:
            # 获取第一个文件尝试解密
            file_list = zf.namelist()
            if not file_list:
                print('  ZIP文件为空')
                continue
                
            first_file = file_list[0]
            print(f'  尝试读取: {first_file}')
            
            # 尝试用密码读取
            try:
                data = zf.read(first_file, pwd=pwd.encode('utf-8'))
                print(f'  ✅ 成功解密！')
                print(f'  数据大小: {len(data)} bytes')
                
                # 尝试显示内容前200字节
                try:
                    text = data[:200].decode('utf-8', errors='ignore')
                    print(f'  内容预览: {text}')
                except:
                    print(f'  原始字节: {data[:50].hex()}')
                
                success = True
                
                # 尝试解压所有文件
                print(f'\n  正在提取所有文件...')
                extract_dir = 'zz/decrypted'
                os.makedirs(extract_dir, exist_ok=True)
                
                for fname in file_list:
                    try:
                        fdata = zf.read(fname, pwd=pwd.encode('utf-8'))
                        # 保存到目录
                        out_path = os.path.join(extract_dir, fname.replace('/', '_'))
                        with open(out_path, 'wb') as f:
                            f.write(fdata)
                        print(f'    ✓ {fname} -> {len(fdata)} bytes')
                    except Exception as e2:
                        print(f'    ✗ {fname}: {e2}')
                
                print(f'\n  文件已提取到: {extract_dir}/')
                break
                
            except RuntimeError as e:
                if 'Bad password' in str(e):
                    print(f'  ❌ 密码错误')
                else:
                    print(f'  ⚠️  解密失败: {e}')
            except Exception as e:
                print(f'  ⚠️  错误: {e}')
                
    except Exception as e:
        print(f'  ⚠️  打开文件失败: {e}')

print()
print('=' * 50)
if success:
    print('✅ 解密成功！')
else:
    print('❌ 所有密码都失败了')
print('=' * 50)
