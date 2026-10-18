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
# 专注守护额外要：读前台应用（使用情况访问）、盖在别的应用上层（悬浮窗）、前台服务
PERMISSIONS = [
    # 联网：检查更新、测速、下 APK 全靠它。release 包 Flutter 不会自带，
    # 少了它所有请求都会变成 SocketException: Failed host lookup，加速器也救不回来。
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.VIBRATE",
    "android.permission.RECEIVE_BOOT_COMPLETED",
    "android.permission.SCHEDULE_EXACT_ALARM",
    "android.permission.WAKE_LOCK",
    "android.permission.PACKAGE_USAGE_STATS",
    "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    "android.permission.SYSTEM_ALERT_WINDOW",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
    # 检查更新下完要拉起系统安装器，Android 8 起必须有这个
    "android.permission.REQUEST_INSTALL_PACKAGES",
]

# 专注守护的前台服务声明（Android 14 起必须写清 foregroundServiceType）
SERVICE_XML = """    <service
        android:name=".OverlayService"
        android:exported="false"
        android:foregroundServiceType="specialUse">
        <property
            android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
            android:value="focus_guard" />
    </service>
    <service
        android:name=".HudService"
        android:exported="false"
        android:foregroundServiceType="specialUse">
        <property
            android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
            android:value="task_hud" />
    </service>
"""

# Android 11+ 的包可见性：不声明这条，白名单里读不到已安装应用
QUERIES_XML = """    <queries>
        <intent>
            <action android:name="android.intent.action.MAIN" />
            <category android:name="android.intent.category.LAUNCHER" />
        </intent>
    </queries>
"""

# 更新包下到 getExternalFilesDir(Download)，通过 FileProvider 交给安装器
FILE_PATHS_XML = """<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-files-path name="dl" path="." />
    <files-path name="files" path="." />
</paths>
"""

PROVIDER_XML = """    <provider
        android:name="androidx.core.content.FileProvider"
        android:authorities="${applicationId}.fileprovider"
        android:exported="false"
        android:grantUriPermissions="true">
        <meta-data
            android:name="android.support.FILE_PROVIDER_PATHS"
            android:resource="@xml/file_paths" />
    </provider>
"""

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
    # 包可见性（白名单要列出已安装应用）
    if "<queries>" not in text:
        text = text.replace("<application", QUERIES_XML + "    <application", 1)
    # 专注守护的前台服务
    if 'android:name=".OverlayService"' not in text:
        text = text.replace("</application>", SERVICE_XML + "</application>", 1)
    # 更新包安装走的 FileProvider
    if "androidx.core.content.FileProvider" not in text:
        text = text.replace("</application>", PROVIDER_XML + "</application>", 1)
    MANIFEST.write_text(text, encoding="utf-8")
    # FileProvider 的可见路径表
    xml_dir = APP / "src" / "main" / "res" / "xml"
    xml_dir.mkdir(parents=True, exist_ok=True)
    (xml_dir / "file_paths.xml").write_text(FILE_PATHS_XML, encoding="utf-8")
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
            '    implementation("androidx.core:core:1.13.1")\n'
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
        s += "\n\ndependencies {\n    coreLibraryDesugaring '%s'\n    implementation 'androidx.core:core:1.13.1'\n}\n" % DESUGAR_LIB
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


def patch_icon() -> None:
    """把仓库里的 assets/icon/* 拷进生成的 res/，并写自适应图标描述。

    仓库不存 android/ 目录，所以图标只能在构建时灌进去。
    """
    src_root = ROOT / "assets" / "icon"
    if not src_root.is_dir():
        print("没有 assets/icon，跳过图标（先用 flutter 默认图标）")
        return
    res = APP / "src" / "main" / "res"
    copied = 0
    for dens_dir in src_root.iterdir():
        if not dens_dir.is_dir() or not dens_dir.name.startswith("mipmap-"):
            continue
        dst = res / dens_dir.name
        dst.mkdir(parents=True, exist_ok=True)
        for f in dens_dir.iterdir():
            if f.suffix.lower() == ".png":
                (dst / f.name).write_bytes(f.read_bytes())
                copied += 1
    # 自适应图标：背景色 + 前景图
    colors = res / "values" / "colors.xml"
    colors.parent.mkdir(parents=True, exist_ok=True)
    if not colors.exists():
        colors.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            '    <color name="ic_launcher_background">#5B9CFF</color>\n'
            "</resources>\n",
            encoding="utf-8",
        )
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    print("图标已安装：%d 个 png + 1 个 adaptive-icon" % copied)


def patch_native() -> None:
    """把 android_src/ 里的 Kotlin 源码灌进生成的 android/ 工程。

    仓库不保存 android/（每次构建 flutter create 现生成），所以
    MainActivity 也要一起覆盖 —— flutter create 生成的那份没有 Channels 注册。
    """
    src = ROOT / "android_src"
    if not src.is_dir():
        print("没有 android_src，跳过原生代码（专注锁不会生效）")
        return
    dst = APP / "src" / "main" / "kotlin" / "top" / "planbox"
    dst.mkdir(parents=True, exist_ok=True)
    names = []
    for f in sorted(src.glob("*.kt")):
        (dst / f.name).write_bytes(f.read_bytes())
        names.append(f.name)
    print("原生代码已写入：%s" % ", ".join(names))


if __name__ == "__main__":
    patch_manifest()
    patch_native()
    patch_gradle()
    patch_gradle_properties()
    patch_icon()
