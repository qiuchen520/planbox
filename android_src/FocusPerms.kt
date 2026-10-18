package top.planbox

import android.app.AppOpsManager
import android.content.Context
import android.os.Build
import android.os.Process
import android.provider.Settings

/**
 * 两个特殊权限的统一判定。
 *
 * 为什么不直接用 Settings.canDrawOverlays：不少定制 ROM（读书郎 / 部分 MIUI）
 * 上它对「已经给了」的悬浮窗仍返回 false，服务照这个判就会立刻自己退出，
 * 表现就是「授权了但完全不拦」。所以统一改成「Settings 说给 或 AppOps 说给」。
 */
object FocusPerms {

    fun canOverlay(ctx: Context): Boolean {
        try {
            if (Settings.canDrawOverlays(ctx)) return true
        } catch (_: Throwable) {
            // 继续走 AppOps
        }
        return checkOp(ctx, AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW)
    }

    fun hasUsage(ctx: Context): Boolean =
        checkOp(ctx, AppOpsManager.OPSTR_GET_USAGE_STATS)

    private fun checkOp(ctx: Context, op: String): Boolean {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false
        return try {
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(op, Process.myUid(), ctx.packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(op, Process.myUid(), ctx.packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Throwable) {
            false
        }
    }
}