# 给 agent 的安装指引

> 你是被叫来装这套东西的 agent。这份文件是给你的作业单：按顺序执行，每一步都有成功判据和失败处理。
> **不要跳步，不要猜路径，不要在没验证的情况下说"装好了"。**

---

## 0. 先读这四条硬规则

1. **不要编造任何凭证。** API key、cookie、token、QQ 号、UID 全都只能来自用户。拿不到就停下来问。
2. **不要碰 `~/.dsh/AGENTS.md` 的 `HAND:BEGIN … HAND:END` 段。** 那是用户手写的人格。你可以在 `AUTO:BEGIN … AUTO:END` 里写，但那是蒸馏插件的活，一般也不用你动。
3. **不要默认打开自动评论/自动发帖/自动点赞。** 那会拿用户的账号公开发言。要开必须得到用户明确同意，一次一个平台。
4. **不要把任何密钥写进仓库、日志或回复里。** 密钥只进 DSH 的凭据库（设置 → 模型 里填）。

另外：**装到"要人动手"的地方就停**，把剩下的事列给用户（见第 6 步），不要假装装完了。

---

## 1. 环境检查

逐条跑，任何一条不满足就停下来告诉用户缺什么：

```powershell
node -v          # 需要 >= 22
git --version    # 需要能访问 github.com
dsh --version    # 桌面版通常没有 dsh 在 PATH，见下
```

**如果 `dsh` 不在 PATH 里**（桌面版常见）：CLI 藏在 app.asar 内，用 Electron 当 node 跑：

```powershell
$installDir = "<用户确认的 DSH 安装目录>"
$exe = Join-Path $installDir "DeepSeek Harness.exe"
$cli = Join-Path $installDir "resources\app.asar\dsh\node_modules\@deepseek-ai\dsh-desktop-host\lib\cli.js"
$env:ELECTRON_RUN_AS_NODE = "1"
Start-Process -FilePath $exe -ArgumentList @("--expose-internals", $cli, "--version") -NoNewWindow -Wait -PassThru
Remove-Item Env:\ELECTRON_RUN_AS_NODE
```

⚠️ **两个坑，踩了会白费时间：**
- `& $exe ...`（调用运算符）**拿不到输出也拿不到退出码** —— Electron 是 GUI 子系统程序。必须 `Start-Process -Wait -PassThru` 才可靠。
- 普通 PowerShell 的 `Test-Path` **看不见 app.asar 内部**。只能验 `resources\app.asar` 这个文件存在，内部路径按约定拼。

---

## 2. 确认目标 profile

```powershell
Get-Content "$env:USERPROFILE\.dsh\profiles\<profile>\package.json"
```

判据：
- `dsh.profile.bundles` 里应该有 `@deepseek-ai/dsh-web-app` —— 没有就说明这不是桌面版 profile，插件会装上但**界面里不会出现**，要换 profile 或先补 bundle。
- 没有 `cordis.patch.yml` 也行；安装器不会自动创建或覆盖它。

安装器不会覆盖 `cordis.patch.yml`。模板仅供新环境人工对照；需要合并时先备份并逐项征得用户确认。

---

## 3. 装插件

清单在 `plugins.json`（版本钉死到 commit，不要自己改成 `#main`，那会让不同人装出不同东西）。

```powershell
dsh plugin --profile <profile> add <source>     # 逐个跑，source 从 plugins.json 取
```

**成功判据**：`profiles/<profile>/package.json` 的 `dependencies` 里出现这个包名，且 `dsh.profile.bundles` 里也加上了它。

**失败处理**（按出现频率排序）：
| 报错 | 原因 | 怎么办 |
|---|---|---|
| `ECONNRESET` / `ETIMEDOUT` / `Could not connect to github.com` | 网络抖动 | **重试 2 次**，间隔 5 秒。这个最常见，别当配置问题 |
| `ERR_PNPM_SPEC_NOT_SUPPORTED_BY_ANY_RESOLVER` | 规格写错（漏了 `github:` 前缀） | 照 plugins.json 原样抄 |
| `allowBuilds` / `approve-builds` 提示 | pnpm 拦了构建脚本 | 按 pnpm 打印的 key 写进 `profiles/<profile>/pnpm-workspace.yaml` 的 `allowBuilds:`，再重跑 |
| `peer dependencies` 警告 | 正常 | 忽略 |

装完核对数量：`plugins.json` 里有 10 个，`dependencies` 里就应该有 10 个。少一个就补装，别继续。

---

## 4. 配置边界

不要用模板覆盖现有 profile。模板只说明可选字段；账号、UID、路径和行为开关应在对应插件设置页由用户填写。

| 占位符 | 填什么 | 拿不到时 |
|---|---|---|
| `{{WORKSPACE}}` | 给它干活的工作区绝对路径 | 问用户；或 `$env:USERPROFILE\dsh-workspace` |
| `{{PYTHON}}` | venv 里的 python 绝对路径 | 先填 `python`，在手动清单里提醒用户改 |
| `{{OWNER_UID}}` | 用户自己的平台 UID（B站/QQ） | **填 0**，在手动清单里提醒。填错比填 0 危险 |
| `{{BILI_MENTION}}` | 用户自己的 B 站昵称 | 留空 |

若用户明确要求新建配置，才复制模板到一个新文件并逐项替换；不得自动写入正在使用的 `cordis.patch.yml`。

---

## 5. 人格骨架

已存在的 `~/.dsh/AGENTS.md` 绝不覆盖。不存在时，把模板内容和目标路径展示给用户，取得明确确认后再复制；人格是用户的，不是 Agent 的。

---

## 6. 交给用户的事（你做不到）

装到这里就停。把下面清单原样交给用户，并逐条说明为什么必须他动手：

1. **模型 key**：设置 → 模型。没有它一句话都说不了。
2. **人格手写段**：打开 `~/.dsh/AGENTS.md`，把 `<尖括号>` 换成他自己的话。**这套东西里唯一不能自动化的部分。**
3. **B站**：扫码登录 + 填 pythonPath / workspace / dmUid / mentionName。
4. **知乎**：装 zhihu CLI 并登录 + 填 cliPath。
5. **QQ**：先跑起 OneBot 客户端（NapCat 等），再填群号 / 私聊对象 / 自己的 UID / 群会话表。
6. **微信**：扫码登录（会过期，要重扫）。
7. **多模态**：`platform.agnes-ai.cn` 建 key → 设置 → 多模态配置。
8. **微博**：公开版固定只读，不登录，也没有可开启的写操作。
9. **定时与频率**：时间段、每日条数、主动开口频率。建议先全保守，观察几天。

完整版（含症状对照表）在 `MANUAL-STEPS.md`，让用户自己看一遍。

---

## 7. 验收（缺一条都不算装完）

```powershell
# a) 配置树能组出来（exit 0，且没有 "not found" 之外的新错误）
dsh --profile <profile> --dump-config
```

逐条确认：
- [ ] 非 Electron 专管 profile：`--dump-config` 退出码 0；Electron 专管的 desktop profile 会明确拒绝该命令，应改为核对 package 清单、实际版本并重启 GUI
- [ ] 非 Electron 专管 profile 的配置树能搜到十个插件节点；Electron 专管 profile 则核对 `package.json`、实际版本与 GUI 设置页
- [ ] 启动 GUI 后，设置里能看到这十个插件的页面
- [ ] 用户填完模型 key 后，能正常回一句话
- [ ] 聊几轮后 `~/.dsh/global-memory/chat.json` 在变大
- [ ] `~/.dsh/AGENTS.md` 的 HAND 段与用户写的一致（没被你或蒸馏覆盖）

**不要在没有实际验证的情况下报告"装好了"。** 装不上就说装不上，卡在哪一步、报了什么错，原样贴出来。

---

## 8. 回滚

```powershell
# 卸插件（保留用户数据）
dsh plugin --profile <profile> remove dsh-yu-bili dsh-yu-zhihu dsh-yu-weibo dsh-yu-memory `
  dsh-yu-mood dsh-yu-qq dsh-yu-speak dsh-persona-distill dsh-wechat-plugin dsh-agnes-multimodal

# 还原配置
Copy-Item "$env:USERPROFILE\.dsh\profiles\<profile>\cordis.patch.yml.bak-*" `
          "$env:USERPROFILE\.dsh\profiles\<profile>\cordis.patch.yml"
```

不要主动删 `~/.dsh`。那里面有用户的长期记忆和人格。
