import 'dart:async';

import 'package:flutter/material.dart';

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

class PlanBoxApp extends StatelessWidget {
  PlanBoxApp({super.key});

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