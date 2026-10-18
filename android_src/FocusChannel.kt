package top.planbox

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Flutter <-> 原生 的桥。频道名 planbox/focus。
 *
 * 只暴露三件事：
 * 1. 两个特殊权限的查询 / 跳转（使用情况访问、悬浮窗）
 * 2. 专注锁服务的启停
 * 3. 白名单下发 + 已安装应用清单（含图标，所以不需要额外的 device_apps 插件）
 */
class FocusChannel(
    private val ctx: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "planbox/focus")

    fun attach() {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "canUsage" -> result.success(hasUsageAccess())
                    "canOverlay" -> result.success(canOverlay())
                    "openUsage" -> {
                        openUsageSettings()
                        result.success(true)
                    }
                    "openOverlay" -> {
                        openOverlaySettings()
                        result.success(true)
                    }
                    "start" -> {
                        val minutes = call.argument<Int>("minutes") ?: 0
                        OverlayService.start(ctx, minutes)
                        result.success(true)
                    }
                    "stop" -> {
                        OverlayService.stop(ctx)
                        result.success(true)
                    }
                    "isRunning" -> result.success(OverlayService.running)
                    "ignoringBattery" -> result.success(isIgnoringBattery())
                    "openBattery" -> {
                        openBatterySettings()
                        result.success(true)
                    }
                    "openAppDetails" -> {
                        openAppDetails()
                        result.success(true)
                    }
                    "setWhitelist" -> {
                        val list = call.argument<List<String>>("packages") ?: emptyList()
                        setWhitelist(list)
                        result.success(true)
                    }
                    "listApps" -> result.success(listApps())
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("focus_channel", t.message ?: t.javaClass.simpleName, null)
            }
        }
    }

    // ── 权限 ───────────────────────────────────────────────

    private fun hasUsageAccess(): Boolean {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        val mode = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName,
                )
            }
        } catch (_: Throwable) {
            return false
        }
        // 有的 ROM 不认 checkOp 的返回值，退回读 Setting 文本
        if (mode == AppOpsManager.MODE_ALLOWED) return true
        return try {
            Settings.Secure.getInt(
                ctx.contentResolver, "app_ops_allowed_usage_stats", 0,
            ) != 0
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * 悬浮窗是否真的能用。
     *
     * 只信 Settings.canDrawOverlays 会在不少定制 ROM 上误报 false（读的是另一份开关），
     * 所以再查一遍 AppOps 里的 OPSTR_SYSTEM_ALERT_WINDOW，两者任一为真就算给了。
     */
    private fun canOverlay(): Boolean {
        try {
            if (Settings.canDrawOverlays(ctx)) return true
        } catch (_: Throwable) {
            // 继续走 AppOps
        }
        return try {
            val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
                ?: return false
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                    Process.myUid(), ctx.packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(
                    AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                    Process.myUid(), ctx.packageName,
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Throwable) {
            false
        }
    }

    private fun isIgnoringBattery(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
            val pm = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager
                ?: return true
            pm.isIgnoringBatteryOptimizations(ctx.packageName)
        } catch (_: Throwable) {
            true
        }
    }

    private fun openBatterySettings() {
        launchFirst(
            listOf(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${ctx.packageName}")),
                Intent(Settings.ACTION_SETTINGS),
            ),
        )
    }

    private fun openAppDetails() {
        launchFirst(
            listOf(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${ctx.packageName}")),
                Intent(Settings.ACTION_SETTINGS),
            ),
        )
    }

    private fun openUsageSettings() {
        val intents = listOf(
            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:$ctx.packageName")),
            Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        launchFirst(intents)
    }

    private fun openOverlaySettings() {
        // 读书郎这类定制 ROM 常常不认带 package 的那个 action，逐级退让
        val intents = listOf(
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}")),
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${ctx.packageName}")),
            Intent(Settings.ACTION_SETTINGS),
        )
        launchFirst(intents)
    }

    private fun launchFirst(intents: List<Intent>) {
        for (i in intents) {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                ctx.startActivity(i)
                return
            } catch (_: Throwable) {
                // 换下一个
            }
        }
    }

    // ── 白名单 ─────────────────────────────────────────────

    private fun setWhitelist(packages: List<String>) {
        ctx.getSharedPreferences(OverlayService.PREFS, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(OverlayService.KEY_WHITELIST, packages.toHashSet())
            .apply()
    }

    // ── 已安装应用（图标转 base64 PNG，Flutter 直接 Image.memory） ──

    private fun listApps(): List<Map<String, Any?>> {
        val pm = ctx.packageManager
        val intent = Intent(Intent.ACTION_MAIN, null).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(intent, 0)
            }
        } catch (_: Throwable) {
            emptyList()
        }
        val out = ArrayList<Map<String, Any?>>()
        val seen = HashSet<String>()
        for (ri in resolved) {
            val act = ri.activityInfo ?: continue
            val pkg = act.packageName ?: continue
            if (pkg == ctx.packageName || !seen.add(pkg)) continue
            val label = try {
                act.loadLabel(pm)?.toString() ?: pkg
            } catch (_: Throwable) {
                pkg
            }
            val icon = try {
                act.loadIcon(pm)
            } catch (_: Throwable) {
                null
            }
            out.add(
                hashMapOf(
                    "package" to pkg,
                    "label" to label,
                    "icon" to iconToBase64(icon),
                ),
            )
        }
        out.sortWith(Comparator { a, b ->
            val la = a["label"] as? String ?: ""
            val lb = b["label"] as? String ?: ""
            la.compareTo(lb, ignoreCase = true)
        })
        return out
    }

    private fun iconToBase64(d: Drawable?): String? {
        if (d == null) return null
        return try {
            val size = 96
            val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            d.setBounds(0, 0, size, size)
            d.draw(c)
            val bos = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
            bmp.recycle()
            Base64.encodeToString(bos.toByteArray(), Base64.NO_WRAP)
        } catch (_: Throwable) {
            null
        }
    }
}
