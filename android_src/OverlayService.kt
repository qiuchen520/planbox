package top.planbox

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * 专注锁：前台服务 + 每 0.9 秒查一次前台包名，跑偏了就铺一层全屏幕布，
 * 5 秒倒计时结束把 PlanBox 拉回前台。
 *
 * 这一版针对「授权了但完全不拦」做过专门加固：
 * - 权限判定走 FocusPerms（Settings 与 AppOps 任一为真），不再被 ROM 的
 *   canDrawOverlays 假 false 误杀；
 * - 一定先 startForeground 再考虑退出，否则 API 26+ 会直接崩掉进程（
 *   "did not then call Service.startForeground"），表现同样是「什么都没发生」；
 * - 前台包名取 UsageEvents 的 MOVE_TO_FOREGROUND / ACTIVITY_RESUMED，
 *   事件流拿不到时退回 queryUsageStats 的 lastTimeUsed；
 * - 系统拦住后台启动时（很多 ROM 有「后台弹出界面」限制），幕布**不撤**，
 *   改成提示手动回 App，避免「倒计时结束你还在刷」；
 * - 一直拦着超过 60 秒会把紧急退出提示变亮，防止真锁死。
 */
class OverlayService : Service() {

    companion object {
        private const val CH_ID = "focus_guard"
        private const val NOTIF_ID = 4210
        private const val POLL_MS = 900L
        private const val COUNT_SEC = 5
        private const val ESCALATE_MS = 60_000L
        private const val MAX_LAUNCH_PER_MIN = 8

        const val ACTION_START = "top.planbox.FOCUS_START"
        const val ACTION_STOP = "top.planbox.FOCUS_STOP"

        const val PREFS = "planbox_focus"
        const val KEY_WHITELIST = "whitelist"
        const val KEY_PAUSE_UNTIL = "pause_until"
        /** 长按紧急退出的时间戳。Flutter 侧靠它区分「自己退的」和「被人强杀的」 */
        const val KEY_EMERGENCY_AT = "emergency_at"

        /** 给 Flutter 侧查进程是否还活着 */
        @Volatile
        var running: Boolean = false

        // ── 自检信息（给 Flutter 的 diag 用） ──
        @Volatile
        var lastFg: String? = null

        @Volatile
        var lastTickAt: Long = 0L

        @Volatile
        var lastReason: String = ""

        fun start(ctx: Context, minutes: Int) {
            val i = Intent(ctx, OverlayService::class.java).apply {
                action = ACTION_START
                putExtra("minutes", minutes)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(i)
                } else {
                    ctx.startService(i)
                }
            } catch (_: Throwable) {
                lastReason = "start_failed"
            }
        }

        fun stop(ctx: Context) {
            try {
                ctx.stopService(Intent(ctx, OverlayService::class.java))
            } catch (_: Throwable) {
                // ignore
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var wm: WindowManager? = null
    private var overlay: View? = null
    private var countText: TextView? = null
    private var hintText: TextView? = null
    private var escalated = false

    private var remain = COUNT_SEC
    private var shownAt = 0L
    private var launchCount = 0
    private var lastLaunchAt = 0L
    private var polling = false

    private var whitelist: Set<String> = emptySet()
    private var launcherPkg: String? = null

    override fun onCreate() {
        super.onCreate()
        // 顺序很重要：先拿到前台服务身份，再谈别的。
        // 反过来（先 stopSelf 再 startForeground）在 API 26+ 会抛
        // RemoteServiceException 直接杀进程，看起来就是「授权了但毫无反应」。
        startForegroundSafely()

        wm = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // 上一次点了「紧急退出」，给一段真正的喘息时间
        if (System.currentTimeMillis() < prefs.getLong(KEY_PAUSE_UNTIL, 0L)) {
            lastReason = "paused"
            quit()
            return
        }
        if (!FocusPerms.canOverlay(this)) {
            lastReason = "no_overlay"
            quit()
            return
        }
        if (!FocusPerms.hasUsage(this)) {
            lastReason = "no_usage"
            quit()
            return
        }

        whitelist = prefs.getStringSet(KEY_WHITELIST, emptySet())?.toHashSet() ?: emptySet()
        launcherPkg = resolveLauncher()
        running = true
        lastReason = "running"
        polling = true
        handler.post(poll)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            quit()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = false
        polling = false
        handler.removeCallbacksAndMessages(null)
        hideOverlay()
        super.onDestroy()
    }

    private fun quit() {
        running = false
        polling = false
        handler.removeCallbacksAndMessages(null)
        hideOverlay()
        try {
            stopForeground(true)
        } catch (_: Throwable) {
            // ignore
        }
        stopSelf()
    }

    // ── 通知（前台服务必须有） ──

    private fun startForegroundSafely() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (nm.getNotificationChannel(CH_ID) == null) {
                    nm.createNotificationChannel(
                        NotificationChannel(
                            CH_ID, "专注守护", NotificationManager.IMPORTANCE_MIN,
                        ).apply { setShowBadge(false) },
                    )
                }
            }
            val pi = PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0),
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CH_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val n = builder
                .setContentTitle("专注守护中")
                .setContentText("这一轮还在计时，别偷偷溜走哦")
                .setSmallIcon(applicationInfo.icon)
                .setContentIntent(pi)
                .setOngoing(true)
                .build()
            startForeground(NOTIF_ID, n)
        } catch (_: Throwable) {
            lastReason = "notify_failed"
        }
    }

    // ── 轮询 ─────────────────────────────────────────────

    private val poll = object : Runnable {
        override fun run() {
            if (!polling) return
            try {
                tick()
            } catch (_: Throwable) {
                // 单次失败不中断循环
            }
            if (polling) handler.postDelayed(this, POLL_MS)
        }
    }

    private fun tick() {
        if (!FocusPerms.canOverlay(this) || !FocusPerms.hasUsage(this)) {
            lastReason = "perm_lost"
            quit()
            return
        }
        if (overlay != null && !escalated &&
            SystemClock.uptimeMillis() - shownAt > ESCALATE_MS
        ) {
            showManualHint()
        }

        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (pm != null && !pm.isInteractive) {
            hideOverlay()
            return
        }
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (km != null && km.isKeyguardLocked) {
            hideOverlay()
            return
        }

        val fg = foregroundPackage()
        lastFg = fg
        lastTickAt = System.currentTimeMillis()

        if (fg == null) {
            // 读不到前台包名（有的 ROM 事件流是空的）。不铺幕布，但把原因记下来，
            // 自检页会显示「读不到前台应用」，让人知道问题出在使用情况访问上。
            lastReason = "no_foreground"
            hideOverlay()
            return
        }
        if (fg == packageName || isAllowed(fg)) {
            hideOverlay()
            return
        }
        showOverlay(fg)
    }

    /**
     * 取前台包名。
     *
     * 优先 UsageEvents（准确），两条事件类型都认（API 29 之后叫 ACTIVITY_RESUMED，
     * 更早叫 MOVE_TO_FOREGROUND，个别 ROM 仍然只发后者）。
     * 事件流为空时退回 queryUsageStats 里 lastTimeUsed 最新的那个包。
     */
    private fun foregroundPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return null
        val now = System.currentTimeMillis()

        try {
            val events = usm.queryEvents(now - 20_000, now)
            val e = UsageEvents.Event()
            var best: String? = null
            var bestTs = 0L
            while (events.hasNextEvent()) {
                events.getNextEvent(e)
                val t = e.eventType
                val resumed = t == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                    (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                        t == UsageEvents.Event.ACTIVITY_RESUMED)
                if (resumed && e.timeStamp >= bestTs) {
                    bestTs = e.timeStamp
                    best = e.packageName
                }
            }
            if (best != null) return best
        } catch (_: Throwable) {
            // 落到下面的兜底
        }

        try {
            val stats = usm.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY, now - 60_000, now,
            )
            if (stats != null) {
                var bestPkg: String? = null
                var bestT = 0L
                for (s in stats) {
                    if (s.lastTimeUsed > bestT) {
                        bestT = s.lastTimeUsed
                        bestPkg = s.packageName
                    }
                }
                // 只有「刚刚还在用」才算前台，否则会一直误判成上一个应用
                if (bestPkg != null && now - bestT < 30_000L) return bestPkg
            }
        } catch (_: Throwable) {
            // ignore
        }
        return null
    }

    private fun resolveLauncher(): String? {
        return try {
            val i = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            @Suppress("DEPRECATION")
            packageManager.resolveActivity(i, 0)?.activityInfo?.packageName
        } catch (_: Throwable) {
            null
        }
    }

    private fun isAllowed(pkg: String): Boolean {
        if (whitelist.contains(pkg)) return true
        if (pkg == launcherPkg) return true
        if (pkg == "com.android.systemui" || pkg == "android") return true
        if (pkg == "com.android.dialer" || pkg == "com.android.incallui") return true
        if (pkg.startsWith("com.android.permissioncontroller")) return true
        if (pkg.startsWith("com.google.android.permissioncontroller")) return true
        return false
    }

    // ── 幕布 ─────────────────────────────────────────────

    private fun showOverlay(badPkg: String) {
        if (overlay != null) return
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#F00E1220"))
            isClickable = true
            isFocusable = true
            setOnKeyListener { _, _, _ -> true }
        }
        root.addView(
            TextView(this).apply {
                text = "回去学习"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 34f)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
            },
        )
        root.addView(
            TextView(this).apply {
                text = "检测到你在「${appLabel(badPkg)}」\n这一轮专注还没结束"
                setTextColor(Color.parseColor("#99FFFFFF"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                gravity = Gravity.CENTER
                setPadding(0, dp(18), 0, dp(28))
            },
        )
        val cd = TextView(this).apply {
            text = "$remain"
            setTextColor(Color.parseColor("#5B9CFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 72f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        root.addView(cd)
        root.addView(
            TextView(this).apply {
                text = "秒后自动返回"
                setTextColor(Color.parseColor("#66FFFFFF"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                gravity = Gravity.CENTER
                setPadding(0, dp(10), 0, 0)
            },
        )
        val hint = TextView(this).apply {
            text = "长按这里 3 秒可紧急退出"
            setTextColor(Color.parseColor("#33FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(40), dp(24), dp(24))
            setOnLongClickListener {
                emergencyExit()
                true
            }
        }
        root.addView(hint)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            // 不设 FLAG_NOT_FOCUSABLE / FLAG_NOT_TOUCH_MODAL：要的就是全屏吃手势
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.OPAQUE,
        )
        lp.gravity = Gravity.TOP or Gravity.START
        try {
            wm?.addView(root, lp)
        } catch (t: Throwable) {
            lastReason = "add_view_failed"
            return
        }
        overlay = root
        countText = cd
        hintText = hint
        escalated = false
        shownAt = SystemClock.uptimeMillis()
        remain = COUNT_SEC
        cd.text = "$remain"
        lastReason = "blocking"
        handler.postDelayed(ticker, 1000L)
    }

    /** 后台拉起被系统拦下时，把幕布留下并给出明确指引（别让人继续刷） */
    private fun showManualHint() {
        escalated = true
        val h = hintText ?: return
        h.text = "系统不允许自动跳回，请手动返回计划盒\n长按这里 3 秒可紧急退出"
        h.setTextColor(Color.parseColor("#B3FFFFFF"))
        h.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
    }

    private val ticker = object : Runnable {
        override fun run() {
            if (overlay == null) return
            remain--
            countText?.text = if (remain > 0) "$remain" else "0"
            if (remain <= 0) {
                pullBack()
                return
            }
            handler.postDelayed(this, 1000L)
        }
    }

    private fun pullBack() {
        val now = SystemClock.uptimeMillis()
        if (now - lastLaunchAt > 60_000L) launchCount = 0
        lastLaunchAt = now
        launchCount++
        if (launchCount > MAX_LAUNCH_PER_MIN) {
            // 怎么都拉不回来：幕布留着，让人手动处理
            lastReason = "launch_blocked"
            showManualHint()
            return
        }
        try {
            val i = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            }
            startActivity(i)
        } catch (_: Throwable) {
            lastReason = "launch_exception"
            showManualHint()
            return
        }
        // 不要无条件撤幕布：先确认 App 真的到前台了。
        // 很多 ROM 有「后台弹出界面」开关，startActivity 会静默失败。
        handler.postDelayed({
            if (overlay == null) return@postDelayed
            val fg = foregroundPackage()
            if (fg == packageName) {
                lastReason = "ok"
                hideOverlay()
            } else {
                lastReason = "launch_blocked"
                showManualHint()
                remain = COUNT_SEC
                countText?.text = "$remain"
                handler.postDelayed(ticker, 1000L)
            }
        }, 900L)
    }

    private fun emergencyExit() {
        try {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putLong(KEY_PAUSE_UNTIL, System.currentTimeMillis() + 10 * 60_000L)
                .putLong(KEY_EMERGENCY_AT, System.currentTimeMillis())
                .apply()
        } catch (_: Throwable) {
            // ignore
        }
        hideOverlay()
        Toast.makeText(this, "已紧急退出，10 分钟内不再拦截", Toast.LENGTH_LONG).show()
        lastReason = "emergency"
        quit()
    }

    private fun hideOverlay() {
        handler.removeCallbacks(ticker)
        val v = overlay ?: return
        overlay = null
        countText = null
        hintText = null
        escalated = false
        try {
            wm?.removeView(v)
        } catch (_: Throwable) {
            // 已经被系统移掉了
        }
    }

    private fun appLabel(pkg: String): String {
        return try {
            val pm = packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Throwable) {
            pkg
        }
    }

    private fun dp(v: Int): Int =
        (v * resources.displayMetrics.density).toInt()
}