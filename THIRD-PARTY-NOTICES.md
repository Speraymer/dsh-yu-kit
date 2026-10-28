# 第三方声明（THIRD-PARTY NOTICES）

本仓库**不复制任何第三方插件的代码**。安装时按版本从 npm / GitHub 拉取，所以这里做的是
「列出用了什么、版权归谁、许可证在哪」，而不是重新分发。

本仓库自己的内容（安装脚本、配置模板、文档、架构图）：MIT，© 2026 Speraymer，见 [LICENSE](./LICENSE)。

---

## 一、本套件包含的插件

### 1. 自研插件（8 个，MIT，© 2026 Speraymer）

| 包名 | 版本 | 本 kit 钉的 commit | 仓库 |
|---|---|---|---|
| `dsh-persona-distill` | 2.1.0 | `d540f91a41399271f69cba2e4c1c2ee76dc72c5e` | https://github.com/Speraymer/dsh-persona-distill |
| `dsh-yu-memory` | 3.0.0 | `adf1054b30d75d61e94a5181564065aa9531a931` | https://github.com/Speraymer/dsh-yu-memory |
| `dsh-yu-mood` | 2.0.1 | `863317b42e1dbb72bef4ea9b63cd73ba72470c7f` | https://github.com/Speraymer/dsh-yu-mood |
| `dsh-yu-bili` | 2.1.0 | `0fe849c1472587e9c444b3c55c7c8cc71ee1081f` | https://github.com/Speraymer/dsh-yu-bili |
| `dsh-yu-zhihu` | 2.1.0 | `bec672a21f95231c5596fb32aced57130f0c4080` | https://github.com/Speraymer/dsh-yu-zhihu |
| `dsh-yu-weibo` | 2.1.0 | `af53bf1b009a3ebcc706057a5ebb5930ff311d2d` | https://github.com/Speraymer/dsh-yu-weibo |
| `dsh-yu-qq` | 2.0.3 | `c4f2a11f21bfdb995d9d290cd7c3dcb11d195ca7` | https://github.com/Speraymer/dsh-yu-qq |
| `dsh-yu-speak` | 2.0.1 | `de65fa217d9db118f709b6aca04cc0e9980c02af` | https://github.com/Speraymer/dsh-yu-speak |

每个仓库里都有各自的 `LICENSE`（MIT）。其中两个仓库还带 `NOTICE.md`，里面记着它们内部
沿用/改编的第三方来源：

- `dsh-yu-memory/NOTICE.md` —— 两个 MIT 上游作者（Yuuyuko、Xia Chen），以及 `lib/词典-来源.txt`
  里记录的词典来源。**这份 NOTICE 必须随该插件一起分发**，别删。
- `dsh-yu-speak/NOTICE.md` —— 声明它基于 `Yuuyuko-uu/dsh-speak-up`（其 package.json 声明 MIT）。

### 2. 第三方插件（2 个，MIT，**版权归原作者**）

#### `dsh-wechat-plugin` 0.44.0

- 许可证：**MIT**
- 版权：`Copyright (c) 2026 dsh-wechat contributors`
- 上游：https://github.com/xcisxc29/dsh-wechat
- 许可证副本：[licenses/dsh-wechat-plugin-LICENSE.txt](./licenses/dsh-wechat-plugin-LICENSE.txt)（取自该 npm 包内的 `LICENSE`，原文未改）
- 本 kit 对它的改动：**无**。按 npm 版本安装，不 patch。

#### `dsh-agnes-multimodal` 1.1.0

- 许可证：**MIT**（该包 `package.json` 声明 `"license": "MIT"`）
- 版权人：**上游未声明**
- 上游仓库：**上游未声明**
- ⚠️ **这个包没有随包发布 LICENSE 文件**，也没有 author / repository 字段。
  本仓库按它声明的许可类型补了一份 MIT 正文，版权人写作 "dsh-agnes-multimodal contributors"
  —— 那是**推定**，不是上游原文：见 [licenses/dsh-agnes-multimodal-LICENSE.txt](./licenses/dsh-agnes-multimodal-LICENSE.txt)。
- 如果你是这个包的作者，或知道它的仓库地址：开 issue 告诉我们，我们改成准确原文。
- 本 kit 对它的改动：**无**。按 npm 版本安装。

---

## 二、不在本仓库里、但会被装上的东西

| 东西 | 许可 | 说明 |
|---|---|---|
| **DSH（DeepSeek Harness）本体** | 见其官方仓库 | 本仓库只装插件、只写 profile 配置。DSH 要你自己装 |
| 插件的 npm 运行时依赖 | 各包自带 | 例如 `dsh-yu-weibo` 依赖 `@weibo-ai/weibo-cli`；由 pnpm 按各包 lockfile 安装，本仓库不分发 |
| `zhihu` CLI、`NapCat` 之类的第三方客户端 | 各自许可 | 手动安装的外部程序，不属于本套件 |
| Python venv 里的转写依赖 | 各自许可 | `dsh-yu-bili` 的本地转写会用 pip 装依赖 |

---

## 三、模板里引用的 DSH 官方插件

`profile/cordis.patch.template.yml` 里的 `preset-standard` 段落引用了 DSH 自带的插件 id
（`@deepseek-ai/dsh-tool-*`、`@deepseek-ai/dsh-compaction-*` 等）。这些是**引用**，不是分发：
它们随 DSH 本体提供，许可证见 DSH 仓库。

---

## 四、如果你要再分发本套件

- 保留本文件、`LICENSE`、`licenses/` 目录。
- 如果你把插件代码**复制**进自己的仓库（而不是按版本安装），那你就成了再分发者：
  每个插件的 `LICENSE` 和 `NOTICE.md` 都要跟着走，MIT 要求保留版权声明与许可正文。
- `dsh-agnes-multimodal` 的版权人不明 —— 要商用或大规模再分发之前，建议先联系作者确认。
