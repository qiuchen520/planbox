package top.planbox

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 仓库不保存 android/ 目录，这个文件由 tools/patch_android.py 在 CI 里覆盖
 * flutter create 生成的同名文件，负责把专注锁的原生能力挂到 Flutter 侧。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FocusChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger).attach()
    }
}
