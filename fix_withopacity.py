import os
import re

LIB_DIR = 'lib'

for root, dirs, files in os.walk(LIB_DIR):
    for filename in files:
        if not filename.endswith('.dart'):
            continue
        filepath = os.path.join(root, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        if '.withOpacity(' not in content:
            continue
        
        # Simple direct replacement: .withOpacity( -> .withValues(alpha:
        new_content = content.replace('.withOpacity(', '.withValues(alpha: ')
        
        if new_content != content:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f'Updated: {filepath}')
