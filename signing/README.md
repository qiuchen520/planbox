# 签名说明（重要）

## 为什么要固定签名

Android 的硬规定：**同一个包名，只有签名一致的 APK 才能覆盖安装**。

以前每构建一次就用一个新的 debug keystore，于是每次升级都得先卸载旧版。卸载 = 数据全没，课表和计划全白填。

从 v0.3.0 开始，PlanBox 固定用 `signing/planbox.jks` 签名，**以后直接覆盖安装，数据不丢**。

## 参数（不要改）

| 项 | 值 |
| --- | --- |
| 文件 | `signing/planbox.jks` |
| 格式 | JKS |
| 别名 alias | `planbox` |
| storepass | `planbox2026` |
| keypass | `planbox2026` |
| 算法 | RSA 2048 |
| 有效期 | 10000 天（至 2054-03） |
| 证书主体 | CN=PlanBox, OU=PlanBox, O=PlanBox, L=Beijing, ST=Beijing, C=CN |

**两条铁律：**

1. 不要重新生成签名库。换了签名 = 所有人必须卸载重装 = 数据全丢。
2. 不要改 `applicationId`（`top.planbox`）。改了就是另一个 App，同样无法覆盖。

## 安全提醒

仓库是公开的，所以放在仓库里的 `planbox.jks.b64` 实际上等于把签名钥匙公开了。理论上别人可以拿它签一个同样包名的假 APK。

现在的场景（自己用 + 同学装着玩）影响不大，但等你真想让更多人用时，建议按下面做：

1. 把 `planbox.jks.b64` 的内容转成字符串，存到 GitHub 仓库的 **Settings → Secrets and variables → Actions**，名字叫 `KEYSTORE_B64`。
2. 删掉仓库里的 `signing/planbox.jks.b64`。

CI 已经写好了回退顺序：有 `KEYSTORE_B64` 就用它，没有才读仓库里的文件。

## 备份

`planbox.jks` 丢了就真的回不去了（只能换个新包名重新开始）。请把它和密码一起备份到你自己的云盘。
