package top.planbox

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * 桌面悬浮窗：时钟 + 今日任务 + 番茄钟。
 *
 * 设计取舍：
 * - 全部视图用代码搭，不引 XML —— 仓库不保存 android/ 目录，layout 文件没地方放。
 * - 倒计时在原生侧按「锚点」自己算（anchorMs + remainAtAnchor），
 *   这样 App 在后台、Dart 的 Timer 被系统降频时，悬浮窗上的数字仍然是准的。
 * - 它是一条独立的前台服务，**不依赖专注守护**：不开守护也能挂着，
 *   顺带把进程优先级抬起来，白噪音 / 计时不容易被系统回收。
 * - 守护幕布是另一层 overlay，盖上来的时候会压住悬浮窗，所以
 *   OverlayService 每次铺幕布都会调一次 rebring() 把自己重新置顶。
 */
class HudService : Service() {

    companion object {
        private const val CH_ID = "planbox_hud"
        private const val NOTIF_ID = 4211
        const val PREFS = "planbox_hud"
        private const val KEY_X = "x"
        private const val KEY_Y = "y"
        private const val KEY_SCALE = "scale"
        private const val KEY_MINI = "mini"
        private const val KEY_DATA = "data"
        private const val KEY_SESS = "sess"
        private const val MAX_ROWS = 6

        const val ACTION_START = "top.planbox.HUD_START"
        const val ACTION_STOP = "top.planbox.HUD_STOP"

        private val BG = 0xF01A2130.toInt()
        private val FG = 0xFFE8EDF6.toInt()
        private val DIM = 0xFF9AA6B8.toInt()
        private val ACC = 0xFF5B9CFF.toInt()
        private val OK = 0xFF57C98A.toInt()

        @Volatile
        var running: Boolean = false
            private set

        @Volatile
        private var inst: HudService? = null

        fun start(ctx: Context) {
            if (running) return
            val i = Intent(ctx, HudService::class.java).setAction(ACTION_START)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(i)
                } else {
                    ctx.startService(i)
                }
            } catch (_: Throwable) {
                // 忽略：权限 / 后台启动限制，下次打开 App 还会再试
            }
        }

        fun stop(ctx: Context) {
            try {
                ctx.stopService(Intent(ctx, HudService::class.java))
            } catch (_: Throwable) {
                // ignore
            }
        }

        /** Flutter 推今日任务 */
        fun pushData(ctx: Context, json: String) {
            prefs(ctx).edit().putString(KEY_DATA, json).apply()
            inst?.applyData()
        }

        /** Flutter 推番茄钟会话；空串表示这一轮结束了 */
        fun pushSession(ctx: Context, json: String) {
            prefs(ctx).edit().putString(KEY_SESS, json).apply()
            inst?.applySession()
        }

        /** 重新置顶：幕布盖上来之后要把自己拎回最上层 */
        fun rebring() {
            inst?.rebring()
        }

        private fun prefs(ctx: Context) =
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private val prefs by lazy { getSharedPreferences(PREFS, Context.MODE_PRIVATE) }

    private var root: FrameLayout? = null
    private var panel: LinearLayout? = null
    private var mini: FrameLayout? = null
    private var clockText: TextView? = null
    private var dateText: TextView? = null
    private var sessionTitle: TextView? = null
    private var sessionTime: TextView? = null
    private var sessionBtn: TextView? = null
    private var sessionBar: ProgressBar? = null
    private var sessionBox: LinearLayout? = null
    private var tasksBox: LinearLayout? = null
    private var footText: TextView? = null
    private var miniClock: TextView? = null
    private var lp: WindowManager.LayoutParams? = null

    private var scale = 1f
    private var miniMode = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForegroundSafely()
        if (!FocusPerms.canOverlay(this)) {
            stopSelf()
            return
        }
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        scale = prefs.getFloat(KEY_SCALE, 1f).coerceIn(0.45f, 1.8f)
        miniMode = prefs.getBoolean(KEY_MINI, false)
        build()
        applyData()
        applySession()
        applyMode()
        applyScale()
        running = true
        inst = this
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        if (inst === this) inst = null
        handler.removeCallbacksAndMessages(null)
        try {
            root?.let { wm.removeView(it) }
        } catch (_: Throwable) {
            // ignore
        }
        root = null
        try {
            stopForeground(true)
        } catch (_: Throwable) {
            // ignore
        }
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NOTIF_ID)
        } catch (_: Throwable) {
            // ignore
        }
        super.onDestroy()
    }

    // ── 通知（前台服务必须有） ────────────────────────────
    private fun startForegroundSafely() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (nm.getNotificationChannel(CH_ID) == null) {
                    nm.createNotificationChannel(
                        NotificationChannel(
                            CH_ID, "桌面悬浮窗", NotificationManager.IMPORTANCE_MIN,
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
            val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CH_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            startForeground(
                NOTIF_ID,
                b.setContentTitle("悬浮窗运行中")
                    .setContentText("今日任务和番茄钟挂在桌面上")
                    .setSmallIcon(applicationInfo.icon)
                    .setContentIntent(pi)
                    .setOngoing(true)
                    .build(),
            )
        } catch (_: Throwable) {
            // 通知挂了不影响悬浮窗本体
        }
    }

    // ── 视图 ──────────────────────────────────────────────
    private fun dp(v: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics)
            .roundToInt()

    private fun round(color: Int, radius: Float): GradientDrawable =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = dp(radius).toFloat()
        }

    private fun build() {
        val fl = FrameLayout(this)
        fl.addView(buildPanel())
        fl.addView(buildMini())

        val x = prefs.getInt(KEY_X, dp(12f))
        val y = prefs.getInt(KEY_Y, dp(90f))
        val params = WindowManager.LayoutParams(
            WRAP_CONTENT,
            WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            this.x = x
            this.y = y
        }
        lp = params
        try {
            wm.addView(fl, params)
            root = fl
        } catch (_: Throwable) {
            stopSelf()
        }
    }

    private fun buildPanel(): View {
        val p = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = round(BG, 16f)
            setPadding(dp(12f), dp(9f), dp(12f), dp(10f))
            layoutParams = FrameLayout.LayoutParams(dp(238f), WRAP_CONTENT)
        }

        // 头部：时钟 + 两个小按钮，整行可拖
        val head = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        clockText = TextView(this).apply {
            text = "00:00"
            setTextColor(FG)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 21f)
            setTypeface(typeface, Typeface.BOLD)
            letterSpacing = 0.04f
        }
        head.addView(clockText, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        head.addView(smallBtn("－", "收起成小圆点") {
            miniMode = true
            prefs.edit().putBoolean(KEY_MINI, true).apply()
            applyMode()
        })
        head.addView(smallBtn("×", "关掉悬浮窗") {
            prefs.edit().putBoolean(KEY_MINI, false).apply()
            HudChannel.current?.emit("hudOff")
            stopSelf()
        })
        p.addView(head, fullWidth())

        dateText = TextView(this).apply {
            setTextColor(DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
            text = ""
        }
        p.addView(dateText)

        // 番茄钟区
        sessionBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            setPadding(0, dp(7f), 0, dp(2f))
        }
        val sessTop = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        sessionTime = TextView(this).apply {
            setTextColor(ACC)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTypeface(typeface, Typeface.BOLD)
            text = "25:00"
        }
        sessionBtn = TextView(this).apply {
            setTextColor(FG)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(dp(8f), dp(3f), dp(8f), dp(3f))
            background = round(0x33FFFFFF, 9f)
            text = "暂停"
            setOnClickListener { HudChannel.current?.emit("toggleTimer") }
        }
        sessionTitle = TextView(this).apply {
            setTextColor(DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            text = ""
        }
        sessTop.addView(sessionTime)
        sessTop.addView(
            sessionTitle,
            LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).apply { marginStart = dp(7f) },
        )
        sessTop.addView(sessionBtn)
        sessionBar = ProgressBar(
            this, null, android.R.attr.progressBarStyleHorizontal,
        ).apply {
            max = 1000
            progress = 0
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(4f),
            ).apply { topMargin = dp(5f) }
        }
        sessionBox.addView(sessTop)
        sessionBox.addView(sessionBar)
        p.addView(sessionBox)

        // 任务列表
        tasksBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(4f), 0, 0)
        }
        p.addView(tasksBox)

        val foot = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(6f), 0, 0)
        }
        footText = TextView(this).apply {
            setTextColor(DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
        }
        val addBtn = TextView(this).apply {
            setTextColor(ACC)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            setPadding(dp(8f), dp(3f), dp(8f), dp(3f))
            background = round(0x225B9CFF, 9f)
            text = "＋ 新建"
            setOnClickListener {
                if (!openApp("newTask", null)) HudChannel.current?.emit("newTask")
            }
        }
        foot.addView(footText, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        foot.addView(addBtn)
        p.addView(foot)

        // 拖动 + 双指缩放
        dragOn(head)
        scaleOn(p)
        return p
    }

    private fun buildMini(): View {
        val box = FrameLayout(this).apply {
            background = round(ACC, 22f)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(dp(56f), dp(56f))
        }
        miniClock = TextView(this).apply {
            setTextColor(0xFF101828.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12.5f)
            setTypeface(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            text = "00:00"
        }
        box.addView(
            miniClock,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        box.setOnClickListener {
            miniMode = false
            prefs.edit().putBoolean(KEY_MINI, false).apply()
            applyMode()
        }
        dragOn(box)
        return box
    }

    private fun smallBtn(label: String, hint: String, onTap: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            contentDescription = hint
            setTextColor(DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            gravity = Gravity.CENTER
            setPadding(dp(9f), dp(1f), dp(9f), dp(1f))
            setOnClickListener { onTap() }
        }
    }

    private fun fullWidth(): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, WRAP_CONTENT)

    private fun dragOn(v: View) {
        var dx = 0f
        var dy = 0f
        var moved = false
        v.setOnTouchListener { _, e ->
            val params = lp ?: return@setOnTouchListener false
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dx = e.rawX - params.x
                    dy = e.rawY - params.y
                    moved = false
                }
                MotionEvent.ACTION_MOVE -> {
                    if (abs(e.rawX - dx - params.x) > dp(3f) ||
                        abs(e.rawY - dy - params.y) > dp(3f)
                    ) {
                        moved = true
                    }
                    params.x = (e.rawX - dx).roundToInt()
                    params.y = (e.rawY - dy).roundToInt()
                    try {
                        root?.let { wm.updateViewLayout(it, params) }
                    } catch (_: Throwable) {
                        // ignore
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    prefs.edit().putInt(KEY_X, params.x).putInt(KEY_Y, params.y).apply()
                    // 手指没挪动 → 当成一次点击（迷你圆点靠它展开）
                    if (!moved && e.actionMasked == MotionEvent.ACTION_UP) {
                        v.performClick()
                    }
                    return@setOnTouchListener true
                }
            }
            true
        }
    }

    private fun scaleOn(v: View) {
        val detector = ScaleGestureDetector(this, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(d: ScaleGestureDetector): Boolean {
                scale = (scale * d.scaleFactor).coerceIn(0.45f, 1.8f)
                applyScale()
                return true
            }
        })
        v.setOnTouchListener { _, e ->
            detector.onTouchEvent(e)
            if (e.actionMasked == MotionEvent.ACTION_UP) {
                prefs.edit().putFloat(KEY_SCALE, scale).apply()
            }
            // 返回 false：不吞事件，里面的按钮/行照样能点
            false
        }
    }

    private fun applyScale() {
        panel?.scaleX = scale
        panel?.scaleY = scale
        mini?.scaleX = scale
        mini?.scaleY = scale
    }

    private fun applyMode() {
        panel?.visibility = if (miniMode) View.GONE else View.VISIBLE
        mini?.visibility = if (miniMode) View.VISIBLE else View.GONE
    }

    fun rebring() {
        val r = root ?: return
        val params = lp ?: return
        try {
            wm.removeView(r)
        } catch (_: Throwable) {
            // ignore
        }
        try {
            wm.addView(r, params)
        } catch (_: Throwable) {
            // ignore
        }
    }

    // ── 数据渲染 ──────────────────────────────────────────
    fun applyData() {
        val box = tasksBox ?: return
        box.removeAllViews()
        val raw = prefs.getString(KEY_DATA, "") ?: ""
        var count = 0
        var doneCount = 0
        try {
            val o = JSONObject(raw)
            val arr: JSONArray = o.optJSONArray("tasks") ?: JSONArray()
            dateText?.text = o.optString("date", "")
            for (i in 0 until arr.length()) {
                val t = arr.optJSONObject(i) ?: continue
                if (t.optBoolean("done", false)) doneCount++
            }
            val limit = minOf(arr.length(), MAX_ROWS)
            for (i in 0 until limit) {
                val t = arr.optJSONObject(i) ?: continue
                box.addView(taskRow(t))
                count++
            }
            val total = arr.length()
            footText?.text = when {
                total == 0 -> "今天没有任务"
                else -> "还有 ${total - doneCount} 条 · 共 $total 条"
            }
        } catch (_: Throwable) {
            footText?.text = "今天没有任务"
        }
        if (count == 0) {
            val empty = TextView(this).apply {
                setTextColor(DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                text = "点「＋ 新建」加一条"
                setPadding(0, dp(4f), 0, dp(4f))
            }
            box.addView(empty)
        }
    }

    private fun taskRow(t: JSONObject): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(4f), 0, dp(4f))
        }
        val id = t.optInt("id", -1)
        val done = t.optBoolean("done", false)
        val dot = TextView(this).apply {
            text = if (done) "●" else "○"
            setTextColor(if (done) OK else DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setPadding(0, 0, dp(7f), 0)
            setOnClickListener {
                if (done) {
                    HudChannel.current?.emit("alreadyDone")
                } else {
                    val sent = HudChannel.current?.emit(
                        "checkin", mapOf("taskId" to id),
                    ) ?: false
                    if (!sent) openApp("checkin", id)
                }
            }
        }
        val title = TextView(this).apply {
            text = t.optString("title", "")
            setTextColor(if (done) DIM else FG)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        val whenText = TextView(this).apply {
            text = t.optString("time", "")
            setTextColor(DIM)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            setPadding(dp(6f), 0, 0, 0)
        }
        row.addView(dot)
        row.addView(title, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        row.addView(whenText)
        row.setOnClickListener {
            if (!done) {
                val sent = HudChannel.current?.emit(
                    "focus", mapOf("taskId" to id),
                ) ?: false
                if (!sent) openApp("focus", id)
            }
        }
        return row
    }

    fun applySession() {
        val box = sessionBox ?: return
        val raw = prefs.getString(KEY_SESS, "") ?: ""
        if (raw.isEmpty()) {
            box.visibility = View.GONE
            return
        }
        box.visibility = View.VISIBLE
        try {
            val o = JSONObject(raw)
            sessionTitle?.text = o.optString("title", "专注")
            renderSession(o)
        } catch (_: Throwable) {
            box.visibility = View.GONE
        }
    }

    private fun renderSession(o: JSONObject) {
        val total = o.optInt("total", 0)
        val remainAtAnchor = o.optInt("remain", 0)
        val anchorMs = o.optLong("anchorMs", 0L)
        val running = o.optBoolean("running", false)
        var remain = remainAtAnchor
        if (running && anchorMs > 0) {
            val passed = ((System.currentTimeMillis() - anchorMs) / 1000L).toInt()
            remain = remainAtAnchor - passed
        }
        if (remain < 0) remain = 0
        sessionTime?.text = "%02d:%02d".format(remain / 60, remain % 60)
        sessionBtn?.text = if (remain <= 0) "结束" else if (running) "暂停" else "继续"
        if (total > 0) {
            sessionBar?.progress = (1000 * (total - remain) / total).coerceIn(0, 1000)
        }
        miniClock?.text = if (remain > 0) "%02d:%02d".format(remain / 60, remain % 60) else "☕"
    }

    // ── 每秒刷新 ──────────────────────────────────────────
    private val tick = object : Runnable {
        override fun run() {
            val n = java.util.Calendar.getInstance()
            val hh = String.format("%02d", n.get(java.util.Calendar.HOUR_OF_DAY))
            val mm = String.format("%02d", n.get(java.util.Calendar.MINUTE))
            clockText?.text = "$hh:$mm"
            if (miniMode) {
                val raw = prefs.getString(KEY_SESS, "") ?: ""
                if (raw.isEmpty()) miniClock?.text = "$hh:$mm"
            }
            val sess = prefs.getString(KEY_SESS, "") ?: ""
            if (sess.isNotEmpty()) {
                try {
                    renderSession(JSONObject(sess))
                } catch (_: Throwable) {
                    // ignore
                }
            }
            handler.postDelayed(this, 500)
        }
    }

    /** 拉起 App 并把动作带上；进程活着时通常不会走到这里 */
    private fun openApp(action: String, taskId: Int?): Boolean {
        return try {
            val i = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                putExtra("hud_action", action)
                if (taskId != null) putExtra("hud_task", taskId)
            }
            startActivity(i)
            true
        } catch (_: Throwable) {
            false
        }
    }
}