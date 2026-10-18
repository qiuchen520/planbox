# PlanBox · 计划盒

**给「学习机 / 学生」用的离线计划工具** —— 不联网 · 不登录 · 不广告 · 数据全在本机。

用 **Flutter** 写的学生计划 App，目标是替代那些「功能很多但录入很烦」的通用待办工具。

## 作者

| | |
|---|---|
| 作者 | **汁原** |
| QQ | `2190462784` |
| 小红书 | **TsssT** |
| 官方 QQ 群 | **860358771**（反馈 bug、提需求、拿内测包都在这儿） |

> 应用首次启动会要求阅读并同意《使用协议与隐私说明》（数据只在本机 / 提醒不保证绝对准时 / 免责声明）。协议版本号在 `lib/pages/agreement.dart` 的 `kAgreementVersion`，改正文时 +1，老用户会重新确认一次。

## 功能现状（v0.5.2）

| 模块 | 状态 | 说明 |
|---|---|---|
| ☀️ 今日 | ✅ 已完成 | 今日课程、今日待办、进度、倒计时 |
| 🗓 课表 | ✅ 已完成 | 12 节 × 周一~周日、单双周、周次切换、多选批量铺课 |
| 📅 日历 | ✅ v0.4.3 新增 | 月视图看「哪几天有安排」，点某天看当天清单并直接加计划 |
| 📝 计划 | ✅ 已完成 | 科目 / 截止 / 预估时长 / 子步骤 / 重复规则 / 优先级 |
| 🎨 主题 | ✅ 已完成 | 深色 + 浅色双主题 |
| 🔥 打卡 | ⏳ 计划中 | 连续天数 / 热力图 |
| ⏱ 专注 | ⏳ 计划中 | 番茄钟 / 正计时 |
| 🔔 提醒 | ✅ v0.5.0 新增 | 给计划设提前提醒，声音 + 震动 + 通知，精确闹钟失败自动降级 |
| 💾 备份 | ✅ v0.5.0 新增 | JSON 导出 / 导入 / 本机备份，恢复走单事务，失败整体回滚 |
| 📊 统计 | ⏳ 计划中 | 周复盘 |

平板与手机自适应：宽度 ≥ 900 时切换为左侧竖排导航（已在读书郎 C30 / 2560×1600 上验证）。

## 下载

前往 **Releases** 下载最新 APK，文件名固定为：

| 文件 | 适用设备 |
|---|---|
| `app-arm64-v8a-release.apk` | 绝大多数现代设备（含本项目目标设备） |
| `app-armeabi-v7a-release.apk` | 老设备 |
| `app-x86_64-release.apk` | 模拟器 / x86 平板 |

> 除「通知 / 震动 / 精确闹钟 / 开机重排」外，本项目不申请任何权限：**无网络、无定位、无通讯录、无无障碍、无存储写入**。

**升级请直接覆盖安装**，不要卸载 —— 卸载会清空本地数据库。签名库已于 v0.4.8 轮换（密码只存在仓库 Secret 里，仓库内不留任何 keystore），因此 **v0.4.8 之前的版本无法覆盖升级到新版本，需要卸载后装一次**；从 v0.4.8 起可跨版本覆盖。

## 构建

本项目**不依赖本地 Android SDK**，全部通过 GitHub Actions 云端构建：

```
push / tag → Actions → flutter create 补齐平台文件 → flutter build apk --split-per-abi → 签名 → 产物
```

推 `v*` tag 会自动创建正式 Release；push 到 `main` 会生成 `v0.4.x-buildN` 的 pre-release。

## 技术栈

- Flutter 3.x / Dart 3（stable channel）
- Material 3，配色集中在 `lib/palette.dart` + `lib/theme.dart`
- 本地存储：`sqflite`（`lib/data/db.dart`）
- `applicationId`：`top.planbox`（**永不可改**，改了等于换了一个 App）

## 目录结构

```
lib/
├── main.dart            入口
├── models.dart          Lesson / Task / Override / PeriodTime
├── palette.dart         配色状态（深/浅 + 主色），持久化
├── theme.dart           ThemeData 构建 + kBg/kCard/kAcc 等语义色
├── responsive.dart      断点 BP + ContentWidth 宽度约束
├── data/db.dart         SQLite 读写
└── pages/               home_shell / today / timetable / calendar / tasks / settings
```

## 文档

- `docs/DESIGN.md` —— 完整设计文档（定位、功能、选型、数据模型、UI、CI、里程碑）
- `docs/ROADMAP.md` —— 分批交付计划与避坑清单
- `CONTRIBUTING.md` —— 参与开发的方式、代码约定、提交规范
- `SECURITY.md` —— 安全问题怎么报
- `DCO.txt` —— 贡献者声明（提交时 `-s` 签核）

## 开源协议

**GPL-3.0** —— 可自由使用、修改、分发，但修改后的版本必须以同样协议开源。

贡献采用 **DCO 1.1**（不使用 CLA）：提交时 `git commit -s` 加一行 `Signed-off-by` 即可。

---
<sub>本项目起于一次「学习机桌面图标重复」的排障，最后变成了「干脆自己写一个」。</sub>