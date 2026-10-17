# 签名说明（重要）

## 为什么要有这个东西

Android 规定：**同一个包名，只有签名一致的 APK 才能覆盖安装**。
早期每构建一次都是临时调试签名，所以每次升级都得先卸载，**卸载 = 数据全丢**。
项目因此维护一把**固定签名库**，从 v0.4.8 起所有 APK 都用它签名，
升级直接覆盖安装，课表和计划都会保留。

## 当前签名（v0.4.8 起）

| 项 | 值 |
|---|---|
| 别名 alias | 见 Secret `KEY_ALIAS` |
| 库口令 / 密钥口令 | 见 Secret `KEYSTORE_PASS` / `KEY_PASS` |
| 算法 | RSA 4096 / SHA384withRSA |
| 库格式 | PKCS12 |
| 有效期 | 12000 天 |
| CN / O / C | PlanBox / qiuchen520 / CN |
| 证书指纹 SHA-256 | `47:B5:11:80:9F:52:4C:E6:97:12:95:5C:6C:14:9D:7E:B9:3B:A2:3A:E6:84:29:F1:75:EC:93:DF:CB:43:6F:E9` |

口令**不在本仓库、不在任何文档里**，只存在于两处：

1. GitHub Actions Secret（构建时注入）
2. 设备本地 `/sdcard/PlanBox/keystore-info.txt`（请抄进密码管理器后删除该文件）

## 签名库放在哪

**只放在 GitHub Actions Secret 里**（仓库 Settings → Secrets and variables → Actions）：

| Secret | 内容 |
|---|---|
| `KEYSTORE_B64` | 签名库的单行 base64 文本 |
| `KEYSTORE_PASS` | 库口令 |
| `KEY_ALIAS` | 密钥别名 |
| `KEY_PASS` | 密钥口令 |

工作流 `Sign APK with fixed keystore` 的做法：

```bash
printf '%s' "$KEYSTORE_B64" | base64 -d > /tmp/planbox.jks
apksigner sign --ks /tmp/planbox.jks --ks-key-alias "$KEY_ALIAS" \
  --ks-pass env:KEYSTORE_PASS --key-pass env:KEY_PASS ...
```

四个 Secret 任一缺失，工作流会直接 `exit 1`，**不会**回退到任何仓库内的备份。
这是故意的：让「漏配 Secret」立刻暴露，而不是悄悄用一把旧钥匙继续发版。

## 安全历史（必须知道）

- **v0.3.0 ~ v0.4.4**：`signing/planbox.jks.b64` 曾被**直接提交进公开仓库**，
  工作流缺 Secret 时会回退使用它。该密钥（旧口令，RSA 2048）
  **已视为泄露**，任何拿到文件的人都能签出「签名与官方一致」的 APK。
- **v0.4.5**：删除仓库内 `.b64`，改为只从 Secret 读取。
- **v0.4.8（2026-10-17）**：**整体轮换签名**。旧库作废，新库为 RSA 4096 独立生成。
  代价是这一次升级必须**卸载重装**（`adb` / 系统卸载会清数据），此后恢复为可覆盖升级。

> 注意：git 历史里仍然留着旧 `.b64` 文件（已作废，不再能用于任何新版本）。
> 若要彻底从历史里铲掉，需要 `git filter-repo` 重写历史并强推——破坏性操作，按需再做。

## 千万别做的事

- 不要把签名库（`.jks`）、`.b64`、口令写进仓库、文档、聊天或截图。
- 不要改 `applicationId`（`top.planbox`），改了等于换了一个 App。
- 不要「为了省事」用调试签名发版——那会让下一次正式升级装不上。
- 轮换签名前，务必确认能接受「用户需卸载重装」这个代价。
