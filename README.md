# PlanBox · 计划盒

**给「学习机 / 学生」用的离线计划工具** —— 不联网 · 不登录 · 不广告 · 数据全在本机。

## 这是什么

用 **Flutter** 写的学生计划 App，目标是替代那些「功能很多但录入很烦」的通用待办工具。

| 模块 | 状态 |
|---|---|
| 课表（周视图 / 单双周） | v0.1 开发中 |
| 作业（科目 / 截止 / 预估时长） | 计划中 |
| 今日（待办 + 进度） | 计划中 |
| 打卡（连续天数 / 热力图） | 计划中 |
| 专注（番茄钟） | 计划中 |
| 统计 / 导出 | 计划中 |

## 下载

前往 **Releases** 下载最新 APK：

- `app-arm64-v8a-release.apk` —— 绝大多数现代设备（含本项目目标设备）
- `app-armeabi-v7a-release.apk` —— 老设备

> 本项目**不需要**任何敏感权限（无网络、无定位、无通讯录、无无障碍）。

## 构建

本项目**不依赖本地 Android SDK**，全部通过 GitHub Actions 云端构建：

```
push / tag -> Actions -> flutter create 补齐平台文件 -> flutter build apk --split-per-abi -> Releases
```

每次 push 到 `main` 会自动发一个 `v0.1.0-buildN` 预发布（带 APK）；
推送 `v*` tag 则发正式版。

## 技术栈

- Flutter 3.x / Dart 3（stable channel）
- Material 3 深色主题
- `applicationId`: `top.planbox`
- 目标设备：Android 10+（已在读书郎 C30 / msm8998 / 2560x1600 上验证）

## 文档

- `docs/DESIGN.md` —— 完整设计文档（定位、功能、选型、数据模型、UI、CI、里程碑）

## 开源协议

**GPL-3.0** —— 可自由使用、修改、分发，但修改后的版本必须以同样协议开源。

---

<sub>本项目起于一次「学习机桌面图标重复」的排障，最后变成了「干脆自己写一个」。</sub>
