import 'package:flutter/material.dart';

import 'settings_page.dart';
import 'tasks_page.dart';
import 'today_page.dart';
import 'timetable_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (_index) {
          0 => const TodayPage(),
          1 => const TimetablePage(),
          2 => const TasksPage(),
          _ => const SettingsPage(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: 62,
        backgroundColor: const Color(0xFF181B22),
        indicatorColor: const Color(0xFF5B9CFF).withValues(alpha: 0.18),
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: '计划',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
