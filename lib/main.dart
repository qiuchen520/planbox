import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/db.dart';
import 'pages/home_shell.dart';
import 'palette.dart';
import 'services/notify.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先读回用户选的配色，避免启动瞬间闪一下默认色
  await Pal.load();

  // 通知：初始化失败（缺权限 / 插件异常）不能影响 App 启动，内部已吞异常
  await Notify.i.init();
  DB.taskHook = (task, op) async {
    switch (op) {
      case 'delete':
        if (task.id != null) await Notify.i.cancelTask(task.id!);
        break;
      case 'clear':
        await Notify.i.resyncAll();
        break;
      default:
        await Notify.i.syncTask(task);
    }
  };

  // 手机重启、系统清理闹钟之后，靠启动时重排一遍补回来
  unawaited(Notify.i.resyncAll());

  runApp(PlanBoxApp());
}

/// 全屏沉浸：默认把顶部状态栏（时间 / 电量那一行）藏起来。
/// 用 immersiveSticky 而不是 manual —— 从屏幕顶部下滑能临时唤出来看一眼，
/// 过几秒没人碰它自己再收回去，正是「显示一回然后删掉」的效果。
void _enterImmersive() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

class PlanBoxApp extends StatefulWidget {
  PlanBoxApp({super.key});

  @override
  State<PlanBoxApp> createState() => _PlanBoxAppState();
}

class _PlanBoxAppState extends State<PlanBoxApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 弹过输入法、从后台切回来之后，部分系统会把状态栏又放出来，这里补一刀。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  @override
  Widget build(BuildContext context) {
    // 配色变化时重建 MaterialApp，让 theme 重新生成
    return ValueListenableBuilder<int>(
      valueListenable: Pal.rev,
      builder: (context, _, __) => MaterialApp(
        title: 'PlanBox',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: HomeShell(),
      ),
    );
  }
}