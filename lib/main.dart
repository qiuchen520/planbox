import 'package:flutter/material.dart';

import 'pages/home_shell.dart';
import 'palette.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先读回用户选的配色，避免启动瞬间闪一下默认色
  await Pal.load();
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