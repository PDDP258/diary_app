import re

filepath = 'lib/screens/profile_screen.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Two patterns: with comma before closing showSnackBar paren, and without
patterns = [
    re.compile(
        r'ScaffoldMessenger\.of\(context\)\.showSnackBar\(\s*'
        r'(?:const\s+)?SnackBar\(\s*content:\s*Text\((.*?)\)\s*\),\s*\);',
        re.DOTALL
    ),
    re.compile(
        r'ScaffoldMessenger\.of\(context\)\.showSnackBar\(\s*'
        r'(?:const\s+)?SnackBar\(\s*content:\s*Text\((.*?)\)\s*\)\s*\);',
        re.DOTALL
    ),
]

def get_method(text_arg):
    if '失败' in text_arg or '错误' in text_arg:
        return 'showError'
    if '开发中' in text_arg:
        return 'showToast'
    return 'showSuccess'

def replacer(match):
    text_arg = match.group(1).strip()
    method = get_method(text_arg)
    return f'context.{method}({text_arg});'

new_content = content
for pat in patterns:
    new_content = pat.sub(replacer, new_content)

if new_content != content:
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    count = content.count('ScaffoldMessenger.of(context).showSnackBar')
    print(f'Replaced {count} SnackBar usages.')
else:
    print('No replacements made.')
