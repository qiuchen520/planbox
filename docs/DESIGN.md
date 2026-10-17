# 设计文档 v0.1 —— 学生计划类 App（暂名：`PlanBox` / 中文名：「计划盒」）

> 状态：草案，待技术选型确认
> 日期：2026-10-17
> 目标设备：读书郎 C30（msm8998 / Android 10 / 2560×1600 / 3.1GB 可用内存）
> 开源协议建议：GPL-3.0（防闭源商用）或 Apache-2.0（宽松）

---

## 1. 项目定位

**一句话**：给「学习机 + 学生」用的、离线优先、零广告、零注册的每日计划工具。

### 1.1 真实痛点（来自本次实测）

| # | 痛点 | 现有 App 的问题 |
|---|---|---|
| 1 | 作业散落在微信群、黑板、口头通知 | 通用待办 App 只有「条目」，没有「科目 + 截止 + 预估时长」 |
| 2 | 课程表要靠截图 / 手抄 | 开源课表几乎没有，商业课表广告多、要联网 |
| 3 | 学习机桌面本身有显示 bug（本项目起因） | 桌面生态混乱，装什么都可能被家庭教育管控拦 |
| 4 | 内存只有 3.1GB 可用 | 大厂 App 后台常驻、推送 SDK 一堆，卡 |
| 5 | 家长端可能限制上网 | 需要**纯离线可用** |
| 6 | 数据要能带得走 | 现有 App 导出能力差，换机就丢 |

### 1.2 不做什么（明确边界，防止膨胀）

- ❌ 不做社交 / 排行榜 / 打卡圈
- ❌ 不做云账号体系（同步用 CalDAV / WebDAV，自己填地址）
- ❌ 不做 AI 生成计划（v1 不做，可作为插件式后续）
- ❌ 不做广告、埋点、任何第三方统计 SDK
- ❌ 不请求非必要权限（不要定位、不要通讯录、不要无障碍）

---

## 2. 功能设计

### 2.1 功能分级

| 级别 | 模块 | 内容 |
|---|---|---|
| **M1 MVP** | 今日 | 今日待办、勾选、进度条、快速录入（自动识别「作业/复习/背」打标签） |
| **M1 MVP** | 作业 | 科目、截止时间、预估时长、优先级、备注、完成状态 |
| **M2** | 课表 | 周视图 5×8 格、科目颜色、**单双周/多周轮换**、当天高亮 |
| **M2** | 提醒 | 本地通知（截止前 1 天 / 当天早 7:30） |
| **M3** | 打卡 | 习惯列表、连续天数、周热力图 |
| **M3** | 专注 | 番茄钟（15/25/45）、结束后记录一段会话 |
| **M4** | 统计 | 本周完成率、各科耗时、连续天数曲线 |
| **M4** | 数据 | 导出/导入 JSON、导出 `.ics` 日历、自动本地备份 |
| **M5** | 桌面 | 桌面小部件（今日待办 3 条 + 进度） |
| **M5** | 同步（可选） | CalDAV（任务）+ 课表 ICS 订阅 |

### 2.2 核心用户流程

```
早上开机 → 小部件看到「今天 5 件事」→ 点进 App
   → 今日页确认顺序 → 开始第一个番茄钟（25 分）
   → 结束勾掉 → 中间课间看「今日课程」
放学 → 快速录入老师布置的作业（3 秒一条）
晚上 → 打卡（背单词 / 运动）→ 看进度条满了没
周末 → 统计页看本周完成率 → 清掉没做完的
```

**关键指标（自用验收）**
- 冷启动 → 看到今日页：**< 1 秒**
- 录入一条作业：**≤ 2 次点击 + 1 次输入**
- 安装包体积：**< 15MB**
- 后台常驻内存：**< 60MB**

---

## 3. 技术选型（本次要拍板的部分）

### 3.1 候选对比

| 维度 | **Flutter (Dart)** | **Kotlin + Jetpack Compose** | React Native | 单页 HTML (PWA) |
|---|---|---|---|---|
| 出品方 | Google | Google（Android 官方推荐语言） | Meta | — |
| 跨平台 | ✅ Android/iOS/Windows/Web/Linux 一套代码 | ❌ 仅 Android（Compose Multiplatform 可跨但成熟度一般） | ✅ 移动端 | ✅ 任意浏览器 |
| 平板大屏适配 | ✅ 强（布局自由，`LayoutBuilder`） | ✅ 强（WindowSizeClass 官方支持） | 🟡 一般 | ✅ 强（CSS Grid） |
| 系统能力（通知/闹钟/小部件） | 🟡 需插件，插件生态成熟 | ✅ **原生最强**（AlarmManager、Glance 小部件、WorkManager） | 🟡 依赖原生模块 | ❌ 基本没有（无后台提醒） |
| 包体积 | 🟡 20MB 起（可 --split-per-abi 降到 ~8-10MB/架构） | ✅ **2-4MB** | 🟡 20MB+ | ✅ <1MB |
| 低内存设备表现 | 🟡 Dart VM 常驻 ~40-60MB | ✅ 较低 | 🟡 较高 | ✅ 最低 |
| 学习成本（对你） | 中（Dart 语法像 TS/Kotlin 混合体） | 中高（Gradle + Compose 心智模型） | 中 | 低（会 HTML/JS 就行） |
| **云端构建难度**（关键！） | ✅ **极低**：`subosito/flutter-action` 一行搞定 | 🟡 中：要有 JDK + Gradle 缓存，能跑但慢 | 🟡 中 | —（不用构建） |
| 本机（沙箱）能否编译 | ❌ | ❌ | ❌ | ✅ 直接改 |
| 开源社区热度 | 极高 | 高 | 高 | — |

### 3.2 推荐方案

> **主体用 Flutter，理由如下（按重要性排序）：**

1. **构建链路最短**：你的开发环境是「平板 + 我（沙箱）」，沙箱里没有 Flutter SDK / Android SDK，**真机也装不了 Android Studio**。
   所以现实路径是：**我写代码 → 推到你的 GitHub 仓库 → GitHub Actions 云端编译 → 产出 APK → 你下载安装**。
   Flutter 的 Actions 配置只要 15 行，Kotlin 的 Gradle 构建在免费 runner 上要跑 5-10 分钟且缓存难调。

2. **平板 UI 一次设计到位**：2560×1600 横屏做「左侧导航 + 三栏内容」很舒服，Flutter 的布局系统做这种自适应最省事。

3. **后续可扩展**：同一份代码将来能出 Windows 版 / 网页版，甚至给同学用 iOS，不必重写。

4. **数据层现成**：`drift`（SQLite）+ `flutter_local_notifications` + `table_calendar`，都是成熟方案。

> **什么情况下改选 Kotlin + Compose：**
> - 如果你**非常在意包体积**（想要 3MB 的 APK）
> - 如果**桌面小部件 + 精确闹钟**是 M1 必须项（Android 上原生实现最稳，Flutter 要靠 `home_widget` 插件，跨进程数据共享有坑）
> - 如果这个项目你想当「学 Android 开发」的练习（Kotlin 是官方语言，学习资料最多，对以后有帮助）

**我的结论：`Flutter 做 v0.1 验证交互` → 若确认要长期做且重视小部件，`v0.2 可以只用 Kotlin 重写小部件模块`（Flutter 支持在一个项目里嵌原生 View，不必全重写）。**

### 3.3 具体技术栈（Flutter 路线）

| 层 | 选择 | 说明 |
|---|---|---|
| 框架 | Flutter 3.x / Dart 3 | stable channel |
| 状态管理 | **Riverpod 2** | 比 Provider 清晰，可测试 |
| 路由 | **go_router** | 声明式，支持深链 |
| 数据库 | **drift**（SQLite） | 类型安全、支持迁移、可导出 |
| 键值配置 | shared_preferences | 主题、首屏设置 |
| 通知 | flutter_local_notifications + timezone | Android 10 上 `AlarmManager` 需注意省电策略 |
| 日期/本地化 | intl + flutter_localizations | 中文周起始日 = 周一 |
| 图表 | fl_chart（或自绘 CustomPainter） | 热力图自绘更轻 |
| 图标 | material_symbols_icons | 体积小 |
| 测试 | flutter_test + mocktail | 至少覆盖数据层 |

**目录结构（Clean Architecture 简化版）**

```
lib/
├── main.dart
├── app.dart                    # 主题 / 路由 / 全局 Provider
├── core/
│   ├── db/                     # drift 数据库 + 迁移
│   ├── theme/                  # 颜色、字号、间距 token
│   ├── utils/                  # 日期、周次计算
│   └── notify/                 # 通知调度
├── features/
│   ├── today/                  # 今日（page + widgets + provider）
│   ├── tasks/                  # 作业/待办
│   ├── timetable/              # 课表
│   ├── habits/                 # 打卡
│   ├── focus/                  # 番茄钟
│   ├── stats/                  # 统计
│   └── settings/               # 设置/导入导出
└── l10n/                       # 中文（默认）/ 英文
```

---

## 4. 数据模型

```sql
-- 科目
CREATE TABLE subject (
  id        INTEGER PRIMARY KEY,
  name      TEXT NOT NULL,          -- 语文/数学/英语...
  color     INTEGER NOT NULL,       -- ARGB
  archived  INTEGER NOT NULL DEFAULT 0
);

-- 课程（课表单元）
CREATE TABLE course (
  id        INTEGER PRIMARY KEY,
  subject_id INTEGER NOT NULL REFERENCES subject(id),
  weekday   INTEGER NOT NULL,       -- 1=周一 ... 7=周日
  period    INTEGER NOT NULL,       -- 第几节 1..10
  week_type INTEGER NOT NULL DEFAULT 0, -- 0=每周 1=单周 2=双周 3=自定义
  room      TEXT,
  note      TEXT,
  UNIQUE(weekday, period, week_type)
);

-- 任务（作业 / 待办 / 考试）
CREATE TABLE task (
  id          INTEGER PRIMARY KEY,
  title       TEXT NOT NULL,
  type        INTEGER NOT NULL DEFAULT 0, -- 0待办 1作业 2考试
  subject_id  INTEGER REFERENCES subject(id),
  due_at      INTEGER,              -- epoch millis，可空
  estimate_min INTEGER,             -- 预估分钟
  priority    INTEGER NOT NULL DEFAULT 1, -- 0低 1中 2高
  done        INTEGER NOT NULL DEFAULT 0,
  done_at     INTEGER,
  note        TEXT,
  remind_at   INTEGER,              -- 已排定的提醒时间
  created_at  INTEGER NOT NULL,
  sort_order  INTEGER NOT NULL DEFAULT 0
);

-- 习惯
CREATE TABLE habit (
  id        INTEGER PRIMARY KEY,
  name      TEXT NOT NULL,
  icon      TEXT,
  freq_json TEXT,                   -- {"type":"daily"} 或 {"type":"weekly","days":[1,3,5]}
  archived  INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- 打卡记录（一行 = 一天一次）
CREATE TABLE habit_log (
  habit_id INTEGER NOT NULL REFERENCES habit(id),
  date     TEXT NOT NULL,           -- 'YYYY-MM-DD'
  PRIMARY KEY(habit_id, date)
);

-- 专注会话
CREATE TABLE focus_session (
  id         INTEGER PRIMARY KEY,
  task_id    INTEGER REFERENCES task(id),
  start_at   INTEGER NOT NULL,
  end_at     INTEGER,
  planned_min INTEGER NOT NULL,
  completed  INTEGER NOT NULL DEFAULT 0
);

-- 设置（键值）
CREATE TABLE setting ( key TEXT PRIMARY KEY, value TEXT );
```

**设计要点**
- 时间统一存 **epoch millis（UTC）**，展示时转本地时区
- 打卡日期存 `'YYYY-MM-DD'` 字符串，**按本地日期算**（避免时区抖动）
- 所有表带 `created_at`，便于将来做同步冲突解决
- 软删除用 `archived`，保证导入导出可追回

---

## 5. UI 设计

### 5.1 布局自适应

| 断点 | 宽度 | 布局 |
|---|---|---|
| 紧凑（手机/竖屏） | < 600dp | 底部 4 个 Tab + 单列 |
| 中等（平板竖屏） | 600–840dp | 左侧窄导航（图标+文字）+ 单列，最大宽 720dp 居中 |
| **展开（平板横屏）** | **> 840dp** | **左侧 200dp 导航 + 主内容 + 右侧 320dp「今日简报」侧栏** |

> 你的 C30 是 2560×1600、density 2 → **1280×800 dp**，正好落在「展开」档，享受三栏布局。

### 5.2 视觉规范

```
背景  #0F1115（深） / #F7F8FA（浅）
卡片  #181B22 / #FFFFFF
主色  #5B9CFF  （蓝，专注感）
成功  #3DDC84
警告  #FFB340
危险  #FF5D6C
科目色板（8 色循环）：
  #5B9CFF 语文 · #FF8A65 数学 · #4DD0E1 英语 · #BA68C8 物理
  #81C784 化学 · #FFD54F 历史 · #F06292 生物 · #9575CD 地理
圆角 12–16dp，间距 8 的倍数，字号 12/14/16/20/26
字体 系统默认（Android = Noto Sans SC），保证零额外体积
```

### 5.3 页面草图（今日页 · 横屏）

```
┌──────────┬──────────────────────────────────────────┬──────────────────┐
│ PlanBox  │  10 月 17 日  星期五            7/9 完成  │  下一节课         │
│          │  ███████████░░░░░░░░░░  78%              │  第 5 节 数学     │
│ ☀ 今天 ● │  ┌────────────────────────────────────┐  │  ────────────────  │
│ 🗓 课表  │  │ ○ 数学作业 P32-35        学习  ⏰今天 │  │  今日课程          │
│ 📝 作业  │  │ ✓ 英语单词 Unit5         学习         │  │  1 语文  2 数学    │
│ 🔥 打卡  │  │ ○ 背《出师表》第一段     背诵  ⏰明早 │  │  3 英语  4 物理    │
│ ⏱ 专注  │  │ ○ 整理游戏存档文件夹     娱乐         │  │  5 数学  6 体育    │
│ 📊 统计  │  └────────────────────────────────────┘  │  ────────────────  │
│          │  [ 快速添加…                  ] [ + ]     │  连续打卡          │
│ ⚙ 设置   │                                          │  🔥 12 天 背单词   │
└──────────┴──────────────────────────────────────────┴──────────────────┘
```

---

## 6. 构建与发布

### 6.1 为什么必须用 CI 构建

```
我（沙箱）          → 只能写代码，没有 Flutter/Android SDK，无法编译
你（平板）          → 装不了 Android Studio，无法本地编译
GitHub Actions      → 唯一可行的编译环境（免费额度 2000 分钟/月）
```

### 6.2 流水线

```yaml
# .github/workflows/android.yml（草案）
name: Build APK
on:
  push: { branches: [main], tags: ['v*'] }
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build apk --release --split-per-abi
      - uses: actions/upload-artifact@v4
        with: { name: apk, path: build/app/outputs/flutter-apk/*.apk }
```

- 签名：`key.properties` 从 Actions Secrets 注入（`KS_BASE64` / `KS_PASS` / `KEY_ALIAS`）
- 打 tag → 自动创建 GitHub Release 并上传 APK
- 目标 ABI：`arm64-v8a`（C30 是 64 位 msm8998）+ `armeabi-v7a` 兼容

### 6.3 发布清单

- [ ] `README.md`（截图 + 安装说明 + 设计理念）
- [ ] `LICENSE`（GPL-3.0）
- [ ] `CHANGELOG.md`
- [ ] `docs/DESIGN.md`（本文）
- [ ] 隐私说明：**不联网、不收集数据**（这是卖点，要写明显）
- [ ] Release v0.1.0：`PlanBox-v0.1.0-arm64-v8a.apk`
- [ ] （可选）上 F-Droid：要求无 Google 依赖、可复现构建，门槛较高，v1 之后再考虑

---

## 7. 里程碑

| 版本 | 内容 | 预估工作量 | 验收标准 |
|---|---|---|---|
| **v0.1** | 项目骨架 + 主题 + 今日页（本地存储） | 1 天 | 能加待办、勾选、重启后数据还在 |
| **v0.2** | 作业模块 + 科目 + 截止时间 | 1 天 | 作业能按科目/时间排序 |
| **v0.3** | 课表（含单双周） | 1 天 | 横屏 5×8 可编辑 |
| **v0.4** | 本地通知提醒 | 半天 | 截止前收到通知 |
| **v0.5** | 打卡 + 番茄钟 | 1 天 | 连续天数正确计算 |
| **v0.6** | 统计 + JSON/ICS 导出 | 1 天 | 能导出再导入不丢数据 |
| **v0.7** | 桌面小部件（可选 Kotlin 原生） | 1-2 天 | 桌面显示今日 3 条 |
| **v1.0** | 打磨 + 文档 + 开源发布 | 1 天 | GitHub Release 出 APK |

> 每个版本都对应一次 `tag` + 一个 APK，**你随时能装上试**，不好用就退回上一版。

---

## 8. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 沙箱与平板都无法本地编译 | 阻塞开发 | 全部走 GitHub Actions；v0.1 必须先把流水线跑通**再写功能** |
| Actions 免费额度 | 2000 分钟/月，Flutter 一次构建约 3-5 分钟 | 限制触发条件（只在 push 和 tag），开 cache |
| 读书郎家庭管控拦截安装 | 装不上 | ✅ 已验证可以装未知来源 APK（Lawnchair、Loop 均成功） |
| 精确提醒被省电策略杀 | 提醒不准 | Android 10 用 `AlarmManager.setExactAndAllowWhileIdle` + 引导用户加白名单 |
| 桌面小部件跨进程数据 | Flutter 插件坑多 | 小部件推迟到 v0.7，必要时用原生 Kotlin 写 |
| 项目膨胀导致半途而废 | 最常见死法 | 严格按里程碑，**v0.6 之前不加新功能**，先做到能用 |
| 隐私/合规 | 若开源被关注 | 全程离线、无 SDK，README 明写 |

---

## 9. 待确认决策（需要你拍板）

1. **技术栈**：Flutter（我推荐）还是 Kotlin + Compose（更原生、包更小、能学 Android 开发）？
2. **开源协议**：GPL-3.0（防闭源）还是 Apache-2.0（宽松）？
3. **项目名**：`PlanBox` / 「计划盒」 / 你自己取一个？
4. **GitHub 仓库**：新建一个空仓库（public），我有 github 工具可以直接推代码 + 看 Actions 结果。
5. **第一版取舍**：先做「今日 + 作业」（能立刻用），还是先做「课表」（视觉冲击强）？

---

## 10. 附：为什么不用现成的

| 现成方案 | 为什么被否 |
|---|---|
| Tasks.org | 功能强但偏「GTD 专业向」，录入一条作业要点 3 层菜单；无课表 |
| Loop | 只能打卡，不能管作业 |
| Fossify Calendar | 是日历不是「学生计划」，没有科目/课表概念 |
| 商业课表 App | 广告、要登录、要定位、体积大 |
| 读书郎自带「学习规划师」 | 绑定自家生态，界面老，数据导不出 |

> **自研的真正收益不是「功能更多」，而是「录入快、界面干净、数据归你」。**
