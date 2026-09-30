#!/usr/bin/env python3
"""从 android.jar 里读出 @RemoteView / @RemotableViewMethod 标注 —— 离线确认
RemoteViews 到底允许用哪些 View 类、哪些方法。

为什么需要它：RemoteViews 是在**启动器进程**里被 apply 的，用到不在白名单里的
View 类或方法就会抛异常，宿主于是显示「无法加载小部件」占位图；而这条异常在 App
侧完全看不到 —— onUpdate 里的 try/catch 拦不住，因为是对方进程在炸。所以必须在
打包前把白名单查实，不能靠猜。

    python tool/inspect_android_jar_annotations.py View
    python tool/inspect_android_jar_annotations.py --classes View LinearLayout ImageView
    python tool/inspect_android_jar_annotations.py --list-methods View RemoteView

⚠️ **只能查「类级」注解（`@RemoteView`），查不了「方法级」注解（`@RemotableViewMethod`）。**
原因是 `@RemotableViewMethod` 的保留级别是 **SOURCE**，编译后根本不进 class 文件
（`TextView.class` 里搜 "RemotableViewMethod" 命中 0 次）。所以 `--list-methods` 看不到
方法时**不代表方法没被标注**，别据此下结论 —— 方法白名单只能靠 AOSP 源码
（`RemoteViews.getMethod()`）或官方文档确认。

类级就不一样了：`@RemoteView` 是 RUNTIME 级，能在 android.jar 里读到，所以
「`android.view.View` / `ViewGroup` 没有 @RemoteView」这个结论是可靠的 ——
也这正是小组件里不能用 `<View>` 当分隔线的原因。
"""
from __future__ import annotations

import struct
import sys
import zipfile
from pathlib import Path

SDK = Path.home() / "AppData/Local/Android/Sdk/platforms"

ALIASES = {
    "View": "android/view/View",
    "ViewGroup": "android/view/ViewGroup",
    "TextView": "android/widget/TextView",
    "ImageView": "android/widget/ImageView",
    "LinearLayout": "android/widget/LinearLayout",
    "FrameLayout": "android/widget/FrameLayout",
    "RelativeLayout": "android/widget/RelativeLayout",
    "GridLayout": "android/widget/GridLayout",
    "Button": "android/widget/Button",
    "ProgressBar": "android/widget/ProgressBar",
    "Chronometer": "android/widget/Chronometer",
    "ViewStub": "android/view/ViewStub",
}


def find_android_jar() -> Path:
    cands = sorted(SDK.glob("android-*/android.jar"))
    if not cands:
        raise SystemExit(f"没在 {SDK} 下找到 android.jar")
    return cands[-1]


class ClassFile:
    """顺序解析 class 文件，抽出「类级注解」与「方法级注解」。"""

    def __init__(self, data: bytes):
        self.d = data
        self.cp: list[str | None] = [None]        # 索引 → Utf8 字符串
        self.class_annotations: list[str] = []
        self.method_annotations: dict[str, list[str]] = {}
        self._run()

    # ------------------------------------------------------------------
    def _utf8(self, idx: int) -> str:
        return self.cp[idx] if 0 <= idx < len(self.cp) and self.cp[idx] else ""

    def _annotation_types(self, body: bytes) -> list[str]:
        """注解体里凡是能解成 `Landroid/...;` 的常量池索引都算命中。
        比完整解析 element_value 稳，且足够回答「有没有被标注」。"""
        hits: list[str] = []
        for pos in range(0, len(body) - 1):
            s = self._utf8(struct.unpack_from(">H", body, pos)[0])
            if s.startswith("Landroid/") and s.endswith(";"):
                hits.append(s)
        return hits

    def _run(self) -> None:
        d = self.d
        off = 8                                   # magic + minor + major

        # ---- 常量池 ----
        cp_count = struct.unpack_from(">H", d, off)[0]
        off += 2
        i = 1
        while i < cp_count:
            tag = d[off]
            off += 1
            if tag == 1:                          # Utf8
                n = struct.unpack_from(">H", d, off)[0]
                off += 2
                self.cp.append(d[off:off + n].decode("utf-8", "replace"))
                off += n
            elif tag in (3, 4):                   # Integer / Float
                self.cp.append(None); off += 4
            elif tag in (5, 6):                   # Long / Double（占两格）
                self.cp.append(None); self.cp.append(None); off += 8; i += 1
            elif tag in (7, 8, 16, 19, 20):       # Class/String/MethodType/Module/Package
                self.cp.append(None); off += 2
            elif tag == 15:                       # MethodHandle
                self.cp.append(None); off += 3
            else:                                 # 9,10,11,12,17,18 → 两个 u2
                self.cp.append(None); off += 4
            i += 1

        # ---- 类头 ----
        off += 6                                  # access_flags, this_class, super_class
        ifc = struct.unpack_from(">H", d, off)[0]
        off += 2 + ifc * 2

        # ---- 字段（跳过，但字段上也可能挂注解，这里不需要）----
        fc = struct.unpack_from(">H", d, off)[0]
        off += 2
        for _ in range(fc):
            ac = struct.unpack_from(">H", d, off + 6)[0]
            off += 8
            for _a in range(ac):
                off += 6 + struct.unpack_from(">I", d, off + 2)[0]

        # ---- 方法 ----
        mc = struct.unpack_from(">H", d, off)[0]
        off += 2
        for _ in range(mc):
            name = self._utf8(struct.unpack_from(">H", d, off + 2)[0])
            ac = struct.unpack_from(">H", d, off + 6)[0]
            off += 8
            found: list[str] = []
            for _a in range(ac):
                a_name = self._utf8(struct.unpack_from(">H", d, off)[0])
                a_len = struct.unpack_from(">I", d, off + 2)[0]
                off += 6
                body = d[off:off + a_len]
                off += a_len
                if a_name == "RuntimeVisibleAnnotations":
                    found.extend(self._annotation_types(body))
            if found:
                self.method_annotations.setdefault(name, []).extend(found)

        # ---- 类级属性 ----
        cc = struct.unpack_from(">H", d, off)[0]
        off += 2
        for _ in range(cc):
            a_name = self._utf8(struct.unpack_from(">H", d, off)[0])
            a_len = struct.unpack_from(">I", d, off + 2)[0]
            off += 6
            body = d[off:off + a_len]
            off += a_len
            if a_name == "RuntimeVisibleAnnotations":
                self.class_annotations.extend(self._annotation_types(body))


def load(zf: zipfile.ZipFile, cls: str) -> ClassFile | None:
    entry = f"{cls}.class"
    return ClassFile(zf.read(entry)) if entry in zf.namelist() else None


def main() -> int:
    argv = sys.argv[1:]
    if not argv:
        print(__doc__)
        return 2

    jar = find_android_jar()
    zf = zipfile.ZipFile(jar)
    print(f"[android.jar] {jar}\n")

    if argv[0] == "--list-methods":
        cls = ALIASES.get(argv[1], argv[1]).replace(".", "/")
        want = argv[2] if len(argv) > 2 else "RemotableViewMethod"
        cf = load(zf, cls)
        if cf is None:
            print(f"!! 没有 {cls}"); return 1
        names = sorted(
            m for m, a in cf.method_annotations.items()
            if any(want in x for x in a)
        )
        print(f"{cls.replace('/', '.')} 上带 @{want} 的方法共 {len(names)} 个：")
        for n in names:
            print(f"  - {n}")
        return 0

    if argv[0] == "--classes":
        items = [(ALIASES.get(a, a).replace(".", "/"), []) for a in argv[1:]]
    else:
        cls = ALIASES.get(argv[0], argv[0]).replace(".", "/")
        items = [(cls, argv[1:])]

    bad = 0
    for cls, methods in items:
        cf = load(zf, cls)
        if cf is None:
            print(f"??  {cls.replace('/', '.')} 不在 android.jar 里"); continue
        ok = any("RemoteView;" in a for a in cf.class_annotations)
        if not ok:
            bad += 1
        print(f"{'OK' if ok else 'NO'}  @RemoteView  {cls.replace('/', '.')}")
        for m in methods:
            annos = cf.method_annotations.get(m)
            if annos is None:
                print(f"      ??  未找到方法 {m}"); continue
            good = any("RemotableViewMethod" in a for a in annos)
            if not good:
                bad += 1
            print(f"      {'OK' if good else 'NO'}  @RemotableViewMethod  {m}")
    print(f"\n不合规项：{bad}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
