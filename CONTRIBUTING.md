# 参与 PlanBox 开发

先读 [`README.md`](README.md) 和 [`docs/DESIGN.md`](docs/DESIGN.md)，了解项目定位：
**给学生用的离线计划工具，不联网、不登录、不收集数据。** 任何会让 App 变重、变慢、
或者需要服务器的改动，默认都不接受。

## 一、怎么参与

| 你可以做 | 怎么做 |
|---|---|
| 报 Bug | 开 Issue，写清：设备型号 / Android 版本 / 复现步骤 / 截图 |
| 提需求 | 开 Issue，说明「你现在的痛点」，不要只写「加个 XX 功能」 |
| 改代码 | Fork → 新分支 → PR，CI 必须绿 |
| 改文档 | 直接 PR，同样欢迎 |

Issue / PR 都可以用中文。**不要**在 Issue 里贴真实姓名、学号、班级等个人信息。

## 二、开发环境

这个项目**可以在没有 Flutter SDK 的设备上开发**——编译全部交给 GitHub Actions，
所以最常见的工作流是「改文件 → push → 看 Actions 日志」。

如果你本地有 Flutter：

```bash
flutter pub get
flutter analyze          # 静态检查
flutter test             # 单元测试（test/ 目录）
flutter run              # 需要连设备
```

注意：`android/` 目录**不在仓库里**，由 CI 用 `flutter create` 现场生成，
本地 `flutter run` 前请先自行跑一次 `flutter create --org top --project-name planbox --platforms=android .`
（它不会覆盖 `lib/` 和 `pubspec.yaml`，但会生成 `android/`）。

依赖没变的情况下不要动 `pubspec.yaml` 的版本约束；新依赖需要说明理由。

## 三、代码约定

按优先级排列，越靠前越容易在 review 里被打回：

1. **不许硬编码颜色。** 所有颜色走 `theme.dart` 的语义色：`kBg` `kCard` `kCard2`
   `kLine` `kDim` `kFaint` `kFg` `kAcc` `kOnAcc` `kDanger` `kWarn` `kOk`。
   它们是指向 `Pal` 的 **getter**（运行时可随深浅色切换），因此
   **在这些颜色前面写 `const` 会编译失败**。在新代码里写
   `const Text('x', style: TextStyle(color: kDim))` 是错的。
2. **页面宽度用 `ContentWidth`，断点用 `BP`**（`lib/responsive.dart`）。
   同一屏里的「表头」和「网格」必须放进**同一个** `ContentWidth`，
   否则两者列宽不同，一定会错位——课表页踩过这个坑。
3. **状态管理只用 `setState` + `DB.i` 直接读写**，不引入 Provider / Riverpod / Bloc。
   页面 `initState` 里 `Pal.rev.addListener` 以响应主题变化，`dispose` 里记得移除。
4. **布局用 flex，不要手算像素坐标。** 课表的跨节色块用 `Expanded(flex: span)`
   实现，位置由 flex 决定；不要回到 `Stack + Positioned(top: (p-1)*h)`。
5. 注释和提示文案用中文，变量名用英文；一行不超过约 90 字符。
6. 不留 `TODO` 死代码；调试用的 `print` 提交前删掉。

## 四、提交规范

格式：`type(scope): 中文摘要`

- `type`：`feat` / `fix` `docs` / `refactor` / `style` / `perf` / `test` / `chore` / `ci`
- `scope`：`timetable` / `calendar` / `tasks` / `today` / `settings` / `models` / `theme` / `ci` / `docs`
- 摘要一句话说清「改了什么 + 为什么」，不要写「update」这种。

例：

```
fix(timetable): 表头与网格共用同一宽度约束，修复星期列错位
feat(calendar): 新增计划日历页，月视图 + 当天清单
```

**每个提交都要签核**（DCO 1.1，见 [`DCO.txt`](DCO.txt)）：

```bash
git commit -s -m "feat(calendar): 新增计划日历页"
```

`-s` 会自动追加一行 `Signed-off-by: 你的名字 <你的邮箱>`，表示你确认自己有权提交这份代码。
没有签核的 PR 不会合并。

## 五、版本与发布

一次发布要**同时**改两处，否则 tag 会和版本号对不上：

1. `pubspec.yaml` → `version: 0.4.4+8`（`+` 后面是 build number，只增不减）
2. `.github/workflows/android.yml` → `tag_name` 与 `name` 里的 `v0.4.3` 改成新版本

发布方式：把改好版本号的提交推到 `main`，CI 会自动产出 `v0.4.4-buildN` 的 pre-release；
需要正式版就打 `v0.4.4` tag。

## 六、绝对不能碰的三件事

1. **不能改 `applicationId`（`top.planbox`）。** 改了所有人都得卸载重装，数据全丢。
2. **不能换签名库。** 同理，签名变了就无法覆盖安装。签名库走仓库 Secret
   `KEYSTORE_B64`，不要提交任何 `.jks` / `.b64` 进仓库（`.gitignore` 已拦截）。
3. **不能加网络权限 / 埋点 / 统计 SDK。** 这是项目的底线，不是可讨论项。

## 七、审查标准

PR 会被看这几件事：

- [ ] `flutter analyze` 无 error
- [ ] `flutter test` 通过
- [ ] 深色 / 浅色两种主题下都看过（配色没写死）
- [ ] 手机宽度（约 360dp）和平板宽度（约 1280dp）都试过
- [ ] 没有新增权限、没有新增联网依赖
- [ ] 提交信息符合规范且带 `Signed-off-by`