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
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * 专注锁：前台服务 + 每秒查一次前台包名，跑偏了就铺一层全屏幕布，
 * 5 秒倒计时结束把 PlanBox 拉回前台。
 *
 * 几条硬性原则（都是踩过的坑）：
 * - 自己、桌面、系统 UI、以及「用户点开的那个设置页」永远不拦，否则会把自己锁死；
 * - 息屏 / 锁屏时不铺幕布（否则亮屏后一层黑压在锁屏上）；
 * - 任何异常都只走「撤幕布」，绝不进入死循环；
 * - 连续拉回失败多次就主动收工，避免把设备卡在循环里；
 * - 幕布底部有一行小字，长按可以紧急退出（防死锁的最后一根保险丝）。
 */
class OverlayService : Service() {

    companion object {
        private const val CH_ID = "focus_guard"
        private const val NOTIF_ID = 4210
        private const val POLL_MS = 900L
        private const val COUNT_SEC = 5
        private const val MAX_SHOW_MS = 45_000L
        private const val MAX_LAUNCH_PER_MIN = 8

        const val ACTION_START = "top.planbox.FOCUS_START"
        const val ACTION_STOP = "top.planbox.FOCUS_STOP"

        const val PREFS = "planbox_focus"
        const val KEY_WHITELIST = "whitelist"
        const val KEY_PAUSE_UNTIL = "pause_until"

        /** 给 Flutter 侧查进程是否还活着 */
        @Volatile
        var running: Boolean = false

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
                // 后台启动受限时静默失败，Flutter 侧用 isRunning 判定
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

    private var remain = COUNT_SEC
    private var shownAt = 0L
    private var launchCount = 0
    private var lastLaunchAt = 0L
    private var polling = false

    private var whitelist: Set<String> = emptySet()
    private var launcherPkg: String? = null

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // 上一次点了「紧急退出」，给一段真正的喘息时间
        val pauseUntil = prefs.getLong(KEY_PAUSE_UNTIL, 0L)
        if (System.currentTimeMillis() < pauseUntil) {
            stopSelf()
            return
        }
        if (!Settings.canDrawOverlays(this) || !hasUsageAccess()) {
            stopSelf()
            return
        }
        startForegroundSafely()
        whitelist = prefs.getStringSet(KEY_WHITELIST, emptySet())?.toHashSet() ?: emptySet()
        launcherPkg = resolveLauncher()
        running = true
        polling = true
        handler.post(poll)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
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

    // ── 通知（前台服务必须有，否则会被系统当后台服务掐掉） ──

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
            // 通知建不起来也不该让守护直接死掉
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
        // 权限被撤了就别硬撑，直接收工（Flutter 侧会记为违规）
        if (!Settings.canDrawOverlays(this) || !hasUsageAccess()) {
            stopSelf()
            return
        }
        // 幕布挂太久说明拉回一直失败，撤掉避免卡死
        if (overlay != null && SystemClock.uptimeMillis() - shownAt > MAX_SHOW_MS) {
            hideOverlay()
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
        if (fg == null || fg == packageName || isAllowed(fg)) {
            hideOverlay()
            return
        }
        showOverlay(fg)
    }

    private fun hasUsageAccess(): Boolean {
        return try {
            val ops = getSystemService(Context.APP_OPS_SERVICE) as android.app.AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(
                    android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(), packageName,
                )
            }
            mode == android.app.AppOpsManager.MODE_ALLOWED
        } catch (_: Throwable) {
            false
        }
    }

    private fun foregroundPackage(): String? {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return null
        val now = System.currentTimeMillis()
        val events = try {
            usm.queryEvents(now - 15_000, now)
        } catch (_: Throwable) {
            return null
        }
        val e = UsageEvents.Event()
        val want = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            UsageEvents.Event.ACTIVITY_RESUMED
        } else {
            UsageEvents.Event.MOVE_TO_FOREGROUND
        }
        var last: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == want) last = e.packageName
        }
        return last
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
        // 系统界面 / 通话界面 / 权限授予页：拦了就会死锁
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
            // 吞掉所有按键，包括返回
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
            countText = this
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
        // 防死锁保险丝：长按这行小字 = 立刻解除拦截
        root.addView(
            TextView(this).apply {
                text = "长按这里 3 秒可紧急退出"
                setTextColor(Color.parseColor("#33FFFFFF"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                gravity = Gravity.CENTER
                setPadding(dp(24), dp(40), dp(24), dp(24))
                setOnLongClickListener {
                    emergencyExit()
                    true
                }
            },
        )

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
        } catch (_: Throwable) {
            // 加不上就什么都不做，下一轮再试
            return
        }
        overlay = root
        countText = cd
        shownAt = SystemClock.uptimeMillis()
        remain = COUNT_SEC
        cd.text = "$remain"
        handler.postDelayed(ticker, 1000L)
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
        // 一直被系统拦回来就认输收工，绝不无限重试
        if (launchCount > MAX_LAUNCH_PER_MIN) {
            hideOverlay()
            stopSelf()
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
            hideOverlay()
            return
        }
        // 等 App 真的画出来再撤幕布，否则会闪一下桌面
        handler.postDelayed({ hideOverlay() }, 650L)
    }

    private fun emergencyExit() {
        try {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putLong(KEY_PAUSE_UNTIL, System.currentTimeMillis() + 10 * 60_000L)
                .apply()
        } catch (_: Throwable) {
            // ignore
        }
        hideOverlay()
        Toast.makeText(this, "已紧急退出，10 分钟内不再拦截", Toast.LENGTH_LONG).show()
        stopSelf()
    }

    private fun hideOverlay() {
        handler.removeCallbacks(ticker)
        val v = overlay ?: return
        overlay = null
        countText = null
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