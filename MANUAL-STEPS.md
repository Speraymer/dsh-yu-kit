# 手动配置清单

**这份清单列的是脚本做不到、必须你本人动手的每一件事。** 一条不漏。
装之前扫一遍，装的时候当 check list 用。

图例：🔴 不做就用不了 ／ 🟡 想要完整功能才需要 ／ ⚪ 可选

---

## A. 前置（机器上得有）

| | 需要什么 | 怎么装 / 怎么验 | 缺了会怎样 |
|---|---|---|---|
| 🔴 | **DSH 桌面版** ≥ 0.2.1-rc.3 | 装完能打开 GUI；`dsh --version` 有输出 | 什么都不会发生 |
| 🔴 | **Node ≥ 22** | `node -v` | 插件装不上（pnpm 需要） |
| 🔴 | **git** | `git --version` | 从 GitHub 拉插件会失败 |
| 🟡 | **Python 3.10+** | `python --version` | B站没字幕的视频没法本地转写（其余照常） |

---

## B. 模型（🔴 没这个连话都说不了）

1. **准备一把 key**，二选一：
   - DeepSeek 官方：`platform.deepseek.com` → API keys → 创建
   - 任意 OpenAI 兼容网关（中转站、学校自建服务、自部署 vLLM）：拿 **base_url** + **key**
2. **填进 DSH**：设置 → 模型 → DeepSeek 行填 key；或「添加模型提供商 → 自定义模型 API」填 Provider ID / 端点 / 协议 / key。
3. **验**：随便说一句话，能回就算过。

⚠️ **这里最常见的坑**（作者踩过）：平台的「控制台接口」和「OpenAI 兼容接口」往往不是同一个地址。
   - 症状：401，报 `token malformed` / `invalid number of segments`
   - 排查：先 `curl -H "Authorization: Bearer <key>" <base_url>/models`，能列出模型再往界面里填
   - 例：`https://api.deepseek.com/v1` 是 OpenAI 兼容；某些平台的 `/api/v1` 是它自己的前端网关，不认你的 key

⚠️ **key 只存进凭据库，不要写进 `cordis.patch.yml`。** 那个文件是要进 git 的。

---

## C. 账号（每个内容源 / 出口都要你自己登一次）

### 🟡 B站（刷B站）
- 设置页「刷B站」→ 扫码登录 → 凭证落在 `~/.dsh/bili-duty/bili_credential.json`
- 填 **pythonPath**：`<DSH_HOME>\bili-duty\.venv\Scripts\python.exe`（Windows）／`.venv/bin/python`（macOS/Linux）
- 填 **workspace**：它写日报、存素材的目录
- 填 **dmUid** / **trustedCommandUid**：你自己的 B站 UID（在个人主页 URL 里）
- 填 **mentionName**：你自己的 B站昵称（评论里 @ 用）
- 验：设置页点「立刻跑一轮」，`~/.dsh/bili-duty/duty.log` 里应出现新增条目

### 🟡 知乎（刷知乎）
- 需要 zhihu CLI 且已登录；设置页会显示 `cliPath` 与登录状态
- 填 **cliPath**
- 验：跑一轮后 `~/.dsh/zhihu-duty/duty.log` 有新增

### 🟡 微博（刷微博）
- **只读模式不需要登录**（走 `m.weibo.cn` 公开接口，访客身份）
- 点赞 / 评论 / 转发 / 发博需要**微博开放平台服务**，作者那边也没开通 —— 默认就是关的
- 验：跑一轮后 `~/.dsh/weibo-duty/duty.log` 有新增

### 🟡 QQ（QQ 双向桥）
- 先自己跑一个 **OneBot 实现**（NapCat / Lagrange 之类），拿到 HTTP 或 WS 地址与 token
- 填：**群号**、**私聊对象**、**你自己的 QQ 号**
- 多群时：**群会话表**里每个群要有一行映射，并且把单群的「群会话」清空（否则保存会报「会话绑定重复」）
- 验：往群里发一句话，DSH 那边应自动开一个会话并回话

### 🟡 微信（第三方插件）
- 设置页扫码登录（iLink）
- ⚠️ 登录态会过期，过期了要重扫
- 验：微信里给那个号发消息，DSH 有反应

### 🟡 多模态（第三方插件，图片/视频生成）
- `platform.agnes-ai.cn` 注册 → 建 API key
- 填进 **设置 → 多模态配置**
- 验：让 agent 生成一张图，能出图就算过
- ⚠️ 插件内置的共享默认 key 会被风控（403「账号存在异常活动」）。看到这个错就是没填自己的 key。

---

## D. 人格与记忆（🔴 人格必须人写）

1. **写人格**：打开 `~/.dsh/AGENTS.md`，把「手写段」里的 `<尖括号>` 换成你自己的话。
   - 这套东西里**唯一不能自动化**的部分。照抄别人的说话方式，学出来的只是那个人的仿制品。
   - 写完之后，人格蒸馏插件只会改 `AUTO:BEGIN … AUTO:END` 之间的内容，**不会碰你的手写段**。
2. **设蒸馏节奏**：设置页「人格蒸馏」→ 每天几点跑、一次蒸几天。
3. **记忆**：不用配，装好就自动记。想清空就删 `~/.dsh/global-memory/`（会连长期记忆一起清）。

---

## E. 定时与行为（🟡 建议先全关，观察几天再开）

| 开关 | 默认 | 打开前先想清楚 |
|---|---|---|
| `autoComment`（B站自动评论） | **关** | 打开 = 它用**你的账号**公开发言。先看几天它写什么 |
| 知乎 `autoLike` / `autoComment` / `autoPost` | 插件默认 | 同上；发想法是公开内容 |
| 微博写操作 | **关** | 需要开放平台服务，一般开不了 |
| 每日条数 / 时间段（`peakValley` / `noon` / `night`） | 保守值 | 调高会明显烧模型额度 |
| 主动开口（`dsh-yu-speak`） | 很克制 | 调高它会频繁自己找你，也会烧额度 |
| 私信投递（`dmMode`） | `only` | `both` = 既私信你也发公开评论 |

---

## F. 平台差异

- **Windows**：作者实测环境。`tool-pwsh` 生效、`tool-bash` 自动关掉；路径里有中文/空格时 YAML 里要加引号。
- **macOS / Linux**：`install.sh` **没有在真机上跑过**。python 路径是 `.venv/bin/python`；`tool-bash` 生效、`tool-pwsh` 自动关掉。
- **权限**：模板默认 `workspace-write`（只能写工作区）。作者自己用 `danger-full-access`。想一样就改 `profile/cordis.patch.template.yml` 里的 `defaultPreset`，但先想清楚 —— 那是「不弹审批、能改任何文件」。

---

## G. 装完的验收清单

- [ ] `dsh --profile <profile> --dump-config` 能打出配置树，没有报错
- [ ] 启动 DSH，设置里能看到：鱼的记忆 / 人格蒸馏 / 心情 / 刷B站 / 刷知乎 / 刷微博 / QQ / 主动说话 / 微信 / 多模态
- [ ] 设置 → 模型，key 是绿的（不是红点）
- [ ] 随便说一句话，模型有回应
- [ ] 聊几轮之后，`~/.dsh/global-memory/chat.json` 变大了（对话记忆在记）
- [ ] `~/.dsh/AGENTS.md` 的手写段还是你写的那份（没被覆盖）
- [ ] 只登一个内容源跑一轮，日报写得像人话

---

## H. 常见症状 → 先查这里

| 症状 | 先查 |
|---|---|
| 一句话都不回 / 报 `MISSING_CREDENTIAL` | 模型 key 没填，或填到了错误的 provider 行 |
| 报 `NO_ADAPTER: no adapter registered for provider "xxx"` | 定时任务跑的是 **headless profile**，路由要同时注册在 `profiles/headless/cordis.patch.yml` |
| 插件装了但设置页不出现 | 插件装进了别的 profile；或没重启 DSH |
| 桌面版启动报 `Web authentication failed` | 上一个实例没退干净（端口/锁被占）。全杀进程再启动 |
| B站跑一轮没反应 | pythonPath 指错、venv 没建、或 B站凭证过期 |
| 图片/视频生成 403「账号存在异常活动」 | 没填自己的 Agnes key，用的是插件内置共享 key |
| 人格蒸馏没动 `AGENTS.md` | 没有原料（内容源没跑），或手写段被改坏了（AUTO 段有硬校验） |

---

## I. 卸载 / 回滚

```powershell
# 卸插件（保留你的数据）
dsh plugin --profile <profile> remove dsh-yu-bili dsh-yu-zhihu dsh-yu-weibo dsh-yu-memory `
  dsh-yu-mood dsh-yu-qq dsh-yu-speak dsh-persona-distill dsh-wechat-plugin dsh-agnes-multimodal

# 还原配置（install 时自动备份过）
Copy-Item ~/.dsh/profiles/<profile>/cordis.patch.yml.bak-* ~/.dsh/profiles/<profile>/cordis.patch.yml
```

**忘掉一切**：删 `~/.dsh`。删之前想清楚 —— 长期记忆和人格都在里面。
