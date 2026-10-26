# duty-watch —— 定时任务看门狗

定时任务失败是**静默**的。网关被代理劫走（403）、额度用完、key 失效、任务卡住 ——
你的感受都只是「今天怎么没刷」。这个脚本把这些变成一条能收到的消息。

它不跑任务，只**看**任务。

---

## 它查什么

| 检查 | 怎么查 | 什么时候算有问题 |
|---|---|---|
| 网关探活 | 直接请求 `/v1/models`，**带上凭据**、**绕过系统代理** | 状态码不在白名单 / 连不上 / 凭据库里没有那个 ref |
| 任务新鲜度 | 读每个源 `config.json` 的 `lastRunAt` | 超过阈值没跑（自动跑是关的任务会跳过） |
| 上次结果 | 扫 `lastResult` 里的字样 | 出现 `失败` / `error` / `403` / `401` / `超时` / `NO_ADAPTER` / `MISSING_CREDENTIAL` / `UNKNOWN_MODEL` |

出问题就推微信（找得到 `dsh-wechat-send` 时），同一类问题 `cooldownHours` 内不重复推。

⚠️ **微信推送是尽力而为，不是保证。** 实测过：微信有「回复窗口」限制，你最近没跟它说过话时，
消息会被拒绝（`ret=-2 prepare failed`），插件会**排队等你下次发消息时补发**。所以：

- 脚本退出码：`0`=已发送，`3`=已排队，其它=真失败 —— 三种都写进日志。
- 真出问题时，日志（`$DSH_HOME\duty-watch.log`）是**一定能看到的**那份记录；微信是加分项。
- 想稳一点：把 `cooldownHours` 调小（多推几次），或者自己加一个别的出口（比如桌面通知、邮件）。

**两个刻意的设计：**

1. **必须绕过系统代理**。DSH 自己发请求不走系统代理，走的是它自己的代理策略
   （`$DSH_HOME/.env` 里的 `no_proxy`）。如果探针用 `Invoke-WebRequest`，它会吃系统代理，
   探出来 403 而 DSH 其实是好的 —— 那就成了狼来了。所以优先用 `curl.exe --noproxy "*"`。
2. **必须带凭据**。同济那个网关不带 key 回 403（不是 401），光看状态码分不清
   「没带钥匙」和「被代理劫走」。

---

## 装

```powershell
# 1. 放配置（按需改阈值）
Copy-Item .\duty-watch.config.example.json "$env:USERPROFILE\.dsh\duty-watch.json"

# 2. 先手动跑一遍，看它说什么（-DryRun = 不推微信）
.\duty-watch.ps1 -DryRun

# 3. 注册成计划任务（每 6 小时）
.\install-task.ps1
```

跑一次就退出的用法（适合别的调度器）：

```powershell
.\duty-watch.ps1            # 退出码 0=全部正常，1=有问题，2=配置缺失
```

---

## 配置

默认找 `$DSH_HOME\duty-watch.json`，没有再找脚本旁边的 `duty-watch.config.json`。

```jsonc
{
  "notify": {
    "mode": "auto",          // auto=找到 dsh-wechat-send 就推；off=只写日志
    "cooldownHours": 6,      // 同类问题多久内不重复推
    "wechatSend": ""         // 留空=自动找；也可以写死路径
  },
  "probes": [
    {
      "name": "同济 AGI 网关",
      "url": "https://agi.tongji.edu.cn/v1/models",
      "authRef": "TONGJI_AGI_API_KEY",   // 从 $DSH_HOME/.credentials.yaml 的 refs: 段取
      "expect": [200],
      "timeoutSec": 10
    }
  ],
  "sources": [
    {
      "name": "刷知乎",
      "config": "~/.dsh/zhihu-duty/config.json",
      "enabledField": "autoRun",   // 这个字段是 false 就跳过新鲜度检查；null = 总是检查
      "maxAgeHours": 3
    }
  ]
}
```

- `authRef` 写的是 `.credentials.yaml` 里 `refs:` 下面的键名。**密钥不写进配置文件，也不进日志。**
- 阈值怎么定：比它自己的间隔大一点。刷知乎是每 60 分钟一轮 → 3 小时；微博/B站每天 → 26 小时；人格蒸馏每天 10:10 → 30 小时。

---

## 输出

- 日志：`$DSH_HOME\duty-watch.log`（只记状态和 ID，不记密钥）
- 去重状态：`$DSH_HOME\duty-watch-state.json`
- 微信消息长这样：

```
【定时任务看门狗】10-27 03:26 · 同济 AGI 网关 返回 HTTP 403（403 常见原因：请求被代理劫走 —— 检查 no_proxy） · 刷知乎：4.2 小时没跑了（阈值 3 小时，上次 10-27 00:41）
```

---

## 它不做什么

- **不替你跑任务**，也不重试。它只报警。
- **不改任何配置**。想让它修，得你自己或者让 agent 动手。
- **不查微信/QQ 通道本身**（那些是出口，挂了不影响定时任务写日报）。要查可以自己在 `probes` 里加一条。
