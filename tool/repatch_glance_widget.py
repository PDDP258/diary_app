#!/usr/bin/env python3
"""重新给 glance_widget_android 打本地补丁（幂等）。

为什么需要这个脚本
------------------
`glance_widget_android` 2.0.1 刻意不在自己的 `plugins {}` 里应用 Kotlin Gradle Plugin，
而是指望 Flutter ≥3.47 的加载器给插件模块注入 `kotlin-android`。本项目跑在 Flutter 3.41，
于是该模块的 Kotlin 源码根本不编译，Release 构建报「找不到符号 GlanceWidgetPlugin」，
脚本编译期还会报 `Unresolved reference: kotlin / compilerOptions / jvmTarget`。

我们在 pub 缓存里就地打了三处补丁（自带 KGP classpath、显式 apply KGP、按任务设置
JVM 目标）。**这些改动只存在于本机 pub 缓存里**，以下任一操作都会把它冲掉：

  * `flutter pub cache clean` / `flutter pub cache repair`
  * `flutter pub get` 重新解压该包（锁文件变化、换机、CI 构建等）
  * 删除 `%LOCALAPPDATA%\\Pub\\Cache`

跑一次本脚本即可恢复。验证：`flutter build apk --release --no-pub`。

详细背景见 docs/wayfinder/course_schedule_map.md 的 Fog 段。
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

PACKAGE = "glance_widget_android-2.0.1"
RELATIVE = Path("android") / "build.gradle.kts"
MARKER = "PATCHED for 小记日记"

KGP_CLASSPATH_ANCHOR = (
    '        classpath("org.jetbrains.kotlin:compose-compiler-gradle-plugin:$composeCompilerVersion")\n'
)
KGP_CLASSPATH_PATCH = (
    KGP_CLASSPATH_ANCHOR
    + "        // " + MARKER + " (见 docs/wayfinder/course_schedule_map.md 的 Fog)\n"
    + "        // Flutter 3.41 的加载器不会给插件模块应用 kotlin-android，没有 KGP 这个模块的\n"
    + "        // Kotlin 源码根本不编译（Release 构建报「找不到符号 GlanceWidgetPlugin」）。\n"
    + '        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$composeCompilerVersion")\n'
)

COMPOSE_APPLY_ANCHOR = 'apply(plugin = "org.jetbrains.kotlin.plugin.compose")\n'
COMPOSE_APPLY_PATCH = (
    COMPOSE_APPLY_ANCHOR
    + "\n// " + MARKER + "：显式应用 KGP。上游指望宿主 Flutter 加载器注入（3.47+ 才可靠），\n"
    + "// 3.41 下这个模块的 Kotlin 源码完全不编译。重复应用是幂等的。\n"
    + 'apply(plugin = "org.jetbrains.kotlin.android")\n'
)

KOTLIN_BLOCK_PATCH = (
    "// " + MARKER + "：顶层 `kotlin {}` 在 Kotlin DSL 脚本编译期拿不到类型安全访问器\n"
    "// （报 `Unresolved reference: kotlin` / `compilerOptions` / `jvmTarget`），\n"
    "// 因为该插件没在 `plugins {}` 里声明。改为按任务等价设置 JVM 目标。\n"
    "// 注意：Kotlin 2.2 起旧的 `kotlinOptions { jvmTarget = \"17\" }` 是**编译错误**，\n"
    "// 必须用 compilerOptions DSL。\n"
    "tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {\n"
    "    compilerOptions {\n"
    "        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)\n"
    "    }\n"
    "}\n"
)


def find_build_file() -> Path:
    candidates = []
    local = os.environ.get("LOCALAPPDATA")
    if local:
        for cache in ("Pub", "pub"):
            candidates.append(
                Path(local) / cache / "Cache" / "hosted" / "pub.flutter-io.cn" / PACKAGE / RELATIVE
            )
            candidates.append(
                Path(local) / cache / "Cache" / "hosted" / "pub.dev" / PACKAGE / RELATIVE
            )
    candidates.append(Path.home() / ".pub-cache" / "hosted" / "pub.flutter-io.cn" / PACKAGE / RELATIVE)
    candidates.append(Path.home() / ".pub-cache" / "hosted" / "pub.dev" / PACKAGE / RELATIVE)

    for path in candidates:
        if path.is_file():
            return path
    raise SystemExit(
        "找不到 %s。先跑一次 `flutter pub get` 让 pub 把依赖拉下来，再执行本脚本。\n"
        "尝试过的路径：\n  %s" % (RELATIVE, "\n  ".join(str(c) for c in candidates))
    )


def main() -> int:
    build_file = find_build_file()
    text = build_file.read_text(encoding="utf-8")

    if MARKER in text:
        print(f"补丁已存在，无需处理：{build_file}")
        return 0

    if KGP_CLASSPATH_ANCHOR not in text:
        raise SystemExit(f"锚点缺失（compose-compiler classpath）：{build_file}\n插件版本可能变了，请人工核对。")
    text = text.replace(KGP_CLASSPATH_ANCHOR, KGP_CLASSPATH_PATCH, 1)

    if COMPOSE_APPLY_ANCHOR not in text:
        raise SystemExit(f"锚点缺失（compose 插件 apply）：{build_file}")
    text = text.replace(COMPOSE_APPLY_ANCHOR, COMPOSE_APPLY_PATCH, 1)

    # 上游的 `kotlin {}` 块：从 `kotlin {` 起按花括号配对找到整块替换
    start = text.find("kotlin {\n    compilerOptions {")
    if start < 0:
        raise SystemExit(f"锚点缺失（顶层 kotlin 块）：{build_file}")
    brace_start = text.index("{", start)
    depth = 0
    i = brace_start
    while i < len(text):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    else:
        raise SystemExit(f"顶层 kotlin 块结构异常：{build_file}")
    end = i + 1  # 指向闭合花括号之后，保留其后的空行
    text = text[:start] + KOTLIN_BLOCK_PATCH.rstrip("\n") + text[end:]

    build_file.write_text(text, encoding="utf-8")
    print(f"补丁已应用：{build_file}")
    print("验证：flutter build apk --release --no-pub")
    return 0


if __name__ == "__main__":
    sys.exit(main())
