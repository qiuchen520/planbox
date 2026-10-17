#!/usr/bin/env python3
"""给 CI 里 `flutter create` 现生成的 android/ 工程打补丁。

仓库不保存 android/ 目录（每次构建都由 flutter create 重新生成），
所以「通知权限」「core library desugaring」这类必须改原生工程的配置，
只能放在这个脚本里，由 workflow 在 scaffold 之后调用：

    python3 tools/patch_android.py
"""

from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "android" / "app"
MANIFEST = APP / "src" / "main" / "AndroidManifest.xml"

# 通知要用到的权限：发通知 / 震动 / 开机后恢复闹钟 / 精确闹钟
PERMISSIONS = [
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.VIBRATE",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.SCHEDULE_EXACT_ALARM",
    "android.permission.WAKE_LOCK",
]

DESUGAR_LIB = "com.android.tools:desugar_jdk_libs:2.1.4"


def patch_manifest() -> None:
    if not MANIFEST.exists():
        sys.exit("找不到 AndroidManifest.xml，flutter create 似乎没有成功")

    text = MANIFEST.read_text(encoding="utf-8")

    # 应用名
    text = text.replace('android:label="planbox"', 'android:label="计划盒"')

    missing = [p for p in PERMISSIONS if p not in text]
    if missing:
        block = "".join(
            '    <uses-permission android:name="%s"/>\n' % p for p in missing
        )
        # 权限必须位于 <manifest> 内、<application> 之前
        if "<application" not in text:
            sys.exit("AndroidManifest.xml 里没有 <application>，结构异常")
        text = text.replace("<application", block + "    <application", 1)

    MANIFEST.write_text(text, encoding="utf-8")
    print("manifest 已处理，新增权限：%s" % (", ".join(missing) or "无"))


def _patch_kts(path: pathlib.Path) -> None:
    s = path.read_text(encoding="utf-8")
    if "isCoreLibraryDesugaringEnabled" not in s:
        s = s.replace(
            "compileOptions {",
            "compileOptions {\n        isCoreLibraryDesugaringEnabled = true",
            1,
        )
    if "coreLibraryDesugaring" not in s:
        s += (
            "\n\ndependencies {\n"
            '    coreLibraryDesugaring("%s")\n'
            "}\n" % DESUGAR_LIB
        )
    path.write_text(s, encoding="utf-8")


def _patch_groovy(path: pathlib.Path) -> None:
    s = path.read_text(encoding="utf-8")
    if "coreLibraryDesugaringEnabled" not in s:
        s = s.replace(
            "compileOptions {",
            "compileOptions {\n        coreLibraryDesugaringEnabled true",
            1,
        )
    if "coreLibraryDesugaring" not in s:
        s += "\n\ndependencies {\n    coreLibraryDesugaring '%s'\n}\n" % DESUGAR_LIB
    path.write_text(s, encoding="utf-8")


def patch_gradle() -> None:
    # flutter_local_notifications 要用 java.time，必须开 desugaring
    kts = APP / "build.gradle.kts"
    groovy = APP / "build.gradle"
    if kts.exists():
        _patch_kts(kts)
        print("build.gradle.kts 已开启 desugaring")
    elif groovy.exists():
        _patch_groovy(groovy)
        print("build.gradle 已开启 desugaring")
    else:
        sys.exit("找不到 app/build.gradle(.kts)，无法开启 desugaring")


def patch_gradle_properties() -> None:
    """兜底：放宽 Kotlin 的 JVM target 一致性校验。

    背景：某些插件（如 flutter_timezone）自己把 Kotlin 目标写死 1.8，
    而 AGP 默认 Java 11，Kotlin 1.8+ 会把这种不一致直接判成 error：
        Inconsistent JVM-target compatibility (11) vs (1.8)
    强改各子模块的 jvmTarget 需要动它们的 buildscript 类路径，很容易连带崩；
    官方给的开关就是把这个校验降级，构建照常进行（字节码跑在 Android 上没问题）。
    """
    props = ROOT / "android" / "gradle.properties"
    props.parent.mkdir(parents=True, exist_ok=True)
    line = "kotlin.jvm.target.validation.mode=warning"
    text = props.read_text(encoding="utf-8") if props.exists() else ""
    if "kotlin.jvm.target.validation.mode" in text:
        print("gradle.properties 已有 jvm target 校验配置，跳过")
        return
    if text and not text.endswith("\n"):
        text += "\n"
    props.write_text(text + line + "\n", encoding="utf-8")
    print("gradle.properties 已放宽 Kotlin jvm target 校验")


if __name__ == "__main__":
    patch_manifest()
    patch_gradle()
    patch_gradle_properties()
