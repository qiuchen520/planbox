import 'package:flutter/material.dart';

/// 布局断点
/// - rail: 达到这个宽度改用侧边导航栏（平板/横屏）
/// - 各页面用 ContentWidth 限制正文宽度，避免平板上一行字拉得太长
class BP {
  static const double rail = 900;
  static const double reading = 780; // 文字列表类页面
  static const double grid = 1100; // 课表
}

/// 把内容限制在 [maxWidth] 内并水平居中。
/// 手机上宽度不够时自动退化为铺满，不会有副作用。
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = BP.reading,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 当前是否宽屏（平板 / 手机横屏）
bool isWideScreen(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= BP.rail;
