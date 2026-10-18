package top.planbox

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 仓库不保存 android/ 目录，这个文件由 tools/patch_android.py 在 CI 里覆盖
 * flutter create 生成的同名文件，负责把原生能力挂到 Flutter 侧：
 * - FocusChannel：专注锁 / 权限 / 白名单
 * - HudChannel：桌面悬浮窗（数据下发 + 点击回调）
 */
class MainActivity : FlutterActivity() {

    private var hud: HudChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FocusChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger).attach()
        val h = HudChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        h.attach()
        hud = h
        // 悬浮窗点了「开始专注 / 打卡」但当时引擎不在，动作挂在启动 Intent 上。
        // 这一刻 Dart 的 handler 还没装好，所以先存着，等 Dart 自己来 takeLaunch。
        h.stashLaunch(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        hud?.deliverLaunch(intent)
    }

    override fun onDestroy() {
        hud?.detach()
        hud = null
        super.onDestroy()
    }
}