package top.planbox

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter <-> 悬浮窗 的桥。频道名 planbox/hud。
 *
 * 约定的分工：
 * - Dart 侧只负责「数据」：今日任务列表、番茄钟的锚点状态，push 过来就走。
 * - 原生侧负责「渲染 + 计时 + 手势」：每秒自己按锚点算剩余时间，
 *   所以 App 被压到后台、Dart 的 Timer 停摆，悬浮窗上的数字照样在走。
 * - 悬浮窗上的点击反过来走 emit()，App 进程活着就即时生效；
 *   引擎没了（进程被回收）就先把动作存下来，等下次拉起 App 再补上。
 */
class HudChannel(private val ctx: Context, messenger: BinaryMessenger) {

    companion object {
        /** 当前活着的桥。Service 要发动作时先看它，为 null 说明 Flutter 引擎不在了 */
        @Volatile
        var current: HudChannel? = null

        /** 引擎不在时暂存的启动动作，等 Dart 主动 takeLaunch 取走 */
        @Volatile
        var pendingLaunch: String? = null
    }

    private val ch = MethodChannel(messenger, "planbox/hud")

    fun attach() {
        current = this
        ch.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            try {
                when (call.method) {
                    "canShow" -> result.success(FocusPerms.canOverlay(ctx))
                    "isRunning" -> result.success(HudService.running)
                    "start" -> {
                        if (!FocusPerms.canOverlay(ctx)) {
                            result.success(false)
                        } else {
                            HudService.start(ctx)
                            result.success(true)
                        }
                    }
                    "stop" -> {
                        HudService.stop(ctx)
                        result.success(true)
                    }
                    "push" -> {
                        val json = call.argument<String>("json") ?: ""
                        HudService.pushData(ctx, json)
                        result.success(true)
                    }
                    "pushSession" -> {
                        val json = call.argument<String>("json") ?: ""
                        HudService.pushSession(ctx, json)
                        result.success(true)
                    }
                    "clearSession" -> {
                        HudService.pushSession(ctx, "")
                        result.success(true)
                    }
                    "takeLaunch" -> {
                        val p = pendingLaunch
                        pendingLaunch = null
                        result.success(p)
                    }
                    "raise" -> {
                        HudService.rebring()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                result.error("hud_channel", t.message ?: t.javaClass.simpleName, null)
            }
        }
    }

    fun detach() {
        if (current === this) current = null
        ch.setMethodCallHandler(null)
    }

    /** 把悬浮窗上的一次点击交给 Flutter。返回 false 表示引擎不在（调用方可退回「拉起 App」） */
    fun emit(action: String, extra: Map<String, Any?> = emptyMap()): Boolean {
        val cur = current ?: return false
        return try {
            val args = HashMap<String, Any?>(extra)
            args["action"] = action
            cur.ch.invokeMethod("action", args)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Activity 被外部拉起时带来的动作（悬浮窗在引擎不在的情况下点了任务）。
     * 以 "launch" 事件交给 Dart，由它决定是开番茄还是打卡。
     */
    fun deliverLaunch(intent: Intent?) {
        val payload = launchPayload(intent) ?: return
        if (!emit("launch", mapOf("payload" to payload))) {
            pendingLaunch = payload
        }
    }

    /** 刚 attach 时 Dart 还没装好 handler，先存着等它来取 */
    fun stashLaunch(intent: Intent?) {
        val payload = launchPayload(intent) ?: return
        pendingLaunch = payload
    }

    private fun launchPayload(intent: Intent?): String? {
        val action = intent?.getStringExtra("hud_action") ?: return null
        if (action.isEmpty()) return null
        val taskId = intent.getIntExtra("hud_task", -1)
        intent.removeExtra("hud_action")
        return "{\"action\":\"$action\",\"taskId\":$taskId}"
    }
}
