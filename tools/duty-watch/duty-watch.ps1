<#
.SYNOPSIS
  duty-watch —— 定时任务看门狗：探网关、看四个任务有没有真的在跑、出问题就通知你。

.DESCRIPTION
  为什么要有它：定时任务失败是**静默**的。网关被代理劫走（403）、额度用完、key 失效、
  任务卡住 —— 你的感受都只是「今天怎么没刷」。这个脚本把这些变成一条能收到的消息。

  三件事：
    1. 探活：按配置请求几个地址，状态码不在白名单里就报警
    2. 新鲜度：读每个源 config.json 的 lastRunAt，超过阈值没跑就报警
    3. 结果扫描：lastResult 里出现失败字样（403 / 401 / 失败 / 超时 / NO_ADAPTER…）就报警

  通知：找得到 dsh-wechat-send 就推微信，找不到就只写日志 + 打印。
  去重：同一类问题在 cooldownHours 内不重复推。

.PARAMETER Config
  配置文件路径。默认取 $DSH_HOME\duty-watch.json，没有再退到脚本旁边的 duty-watch.config.json。

.PARAMETER DryRun
  只打印不推送（第一次装好先这么跑一遍）。

.EXAMPLE
  .\duty-watch.ps1 -DryRun
  .\duty-watch.ps1
#>
[CmdletBinding()]
param(
  [string]$Config,
  [switch]$DryRun
)

$ErrorActionPreference = "Continue"
$here = $PSScriptRoot
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE ".dsh" }

function Write-Log($msg) {
  $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
  Write-Host $line
  try { Add-Content -Path (Join-Path $dshHome "duty-watch.log") -Value $line -Encoding UTF8 } catch {}
}

# ---------------------------------------------------------------- 配置
if (-not $Config) {
  foreach ($c in @((Join-Path $dshHome "duty-watch.json"), (Join-Path $here "duty-watch.config.json"))) {
    if (Test-Path $c) { $Config = $c; break }
  }
}
if (-not $Config -or -not (Test-Path $Config)) {
  Write-Log "没有配置文件。先把 duty-watch.config.example.json 复制成 $dshHome\duty-watch.json 再改。"
  exit 2
}
$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Log "配置：$Config"

$problems = New-Object System.Collections.ArrayList
function Add-Problem($key, $text) { [void]$problems.Add([pscustomobject]@{ key = $key; text = $text }) }

# ---------------------------------------------------------------- 1. 探活
# ⚠️ 必须**绕过系统代理**：DSH 自己发请求不走系统代理，走的是它自己的代理策略
#    （见 $DSH_HOME/.env 里的 no_proxy）。如果这里用 Invoke-WebRequest，它会吃系统代理，
#    探出来是 403，而 DSH 其实是好的 —— 那就变成狼来了。
#    所以优先用 curl.exe --noproxy "*"；没有 curl 才退回 Invoke-WebRequest + 关掉默认代理。
$curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (-not $curl) { Write-Log "  提示：没找到 curl.exe，退回 Invoke-WebRequest（会关掉默认代理）" }

# 从 $DSH_HOME/.credentials.yaml 的 refs: 段里取一个密钥（不进配置、不进日志）
function Get-CredentialRef([string]$name) {
  if (-not $name) { return $null }
  $file = Join-Path $dshHome ".credentials.yaml"
  if (-not (Test-Path $file)) { return $null }
  $text = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)
  $inRefs = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^refs:\s*$') { $inRefs = $true; continue }
    if ($inRefs -and $line -match '^\S') { break }
    if ($inRefs -and $line -match ("^\s+" + [regex]::Escape($name) + ':\s*(\S+)\s*$')) { return $Matches[1] }
  }
  return $null
}

foreach ($p in @($cfg.probes)) {
  if (-not $p) { continue }
  $timeout = if ($p.timeoutSec) { [int]$p.timeoutSec } else { 10 }
  $expect = if ($p.expect) { @($p.expect | ForEach-Object { [int]$_ }) } else { @(200) }
  $status = $null
  $err = $null

  # 带凭据才算真测：同济那个网关不带 key 回 403（不是 401），
  # 光看状态码分不清「没带钥匙」和「被代理劫走」。
  $authHeader = $null
  if ($p.authRef) {
    $key = Get-CredentialRef ([string]$p.authRef)
    if (-not $key) {
      Add-Problem "probe:$($p.name):cred" "$($p.name)：凭据库里没有 $($p.authRef)"
      continue
    }
    $authHeader = "Authorization: Bearer $key"
  }

  if ($curl) {
    $curlArgs = @("-s", "-o", "NUL", "-w", "%{http_code}", "--noproxy", "*", "-m", "$timeout")
    if ($authHeader) { $curlArgs += @("-H", $authHeader) }
    $curlArgs += $p.url
    $raw = & $curl $curlArgs 2>&1
    $code = ([string]$raw).Trim()
    if ($code -eq "000" -or $code -eq "") { $err = "连不上（DNS 或网络不通）" }
    elseif ($code -match '^\d{3}$') { $status = [int]$code }
    else { $err = "curl 返回「$code」" }
  } else {
    try {
      [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy
      $hdr = @{}
      if ($authHeader) { $hdr["Authorization"] = $authHeader.Substring($authHeader.IndexOf(":") + 1).Trim() }
      $resp = Invoke-WebRequest -Uri $p.url -Method Get -TimeoutSec $timeout -UseBasicParsing -Headers $hdr -ErrorAction Stop
      $status = [int]$resp.StatusCode
    } catch {
      $r = $_.Exception.Response
      if ($r) { $status = [int]$r.StatusCode } else { $err = $_.Exception.Message }
    } finally {
      [System.Net.WebRequest]::DefaultWebProxy = $null
    }
  }

  if ($err) {
    Add-Problem "probe:$($p.name)" "$($p.name)：$err"
  } elseif ($expect -notcontains $status) {
    $hint = if ($status -eq 403) { "（403 常见原因：请求被代理劫走 —— 检查 no_proxy）" }
            elseif ($status -eq 401) { "（401：凭据失效或没带 key）" }
            elseif ($status -eq 404) { "（404：地址写错，或者路由变了）" }
            else { "" }
    Add-Problem "probe:$($p.name)" "$($p.name) 返回 HTTP $status$hint"
  } else {
    Write-Log "  探活 ok：$($p.name) HTTP $status"
  }
}

# ---------------------------------------------------------------- 2+3. 源
function Resolve-PathLike($path) {
  if (-not $path) { return $null }
  return ($path -replace '^~', $env:USERPROFILE) -replace '\$DSH_HOME', $dshHome
}

foreach ($s in @($cfg.sources)) {
  if (-not $s) { continue }
  $path = Resolve-PathLike $s.config
  if (-not (Test-Path $path)) {
    Add-Problem "src:$($s.name):missing" "$($s.name)：找不到配置 $path"
    continue
  }
  try { $sc = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { Add-Problem "src:$($s.name):parse" "$($s.name)：配置读不出来（JSON 坏了？）"; continue }

  # 关掉的任务不查新鲜度，但结果里如果有失败字样仍然提示
  $enabled = $true
  if ($s.enabledField) {
    $v = $sc.PSObject.Properties[$s.enabledField]
    if ($v -and $v.Value -eq $false) { $enabled = $false }
  }

  if ($enabled -and $s.maxAgeHours) {
    $stamp = $null
    foreach ($f in @("lastRunAt", "lastRun")) {
      $v = $sc.PSObject.Properties[$f]
      if (-not $v -or -not $v.Value) { continue }
      $raw = [string]$v.Value
      $parsed = [datetime]::MinValue
      if ([datetime]::TryParse($raw, [ref]$parsed)) { $stamp = $parsed.ToUniversalTime(); break }
      # persona-distill 用的是 2026-10-26-101243 这种
      if ($raw -match '^(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})$') {
        $stamp = [datetime]::SpecifyKind(
          [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4], [int]$Matches[5], [int]$Matches[6]),
          [DateTimeKind]::Local).ToUniversalTime()
        break
      }
    }
    if (-not $stamp) {
      Add-Problem "src:$($s.name):never" "$($s.name)：从来没跑过（没有 lastRunAt）"
    } else {
      $ageHours = ([datetime]::UtcNow - $stamp).TotalHours
      if ($ageHours -gt [double]$s.maxAgeHours) {
        Add-Problem "src:$($s.name):stale" ("{0}：{1:N1} 小时没跑了（阈值 {2} 小时，上次 {3}）" -f $s.name, $ageHours, $s.maxAgeHours, $stamp.ToLocalTime().ToString("MM-dd HH:mm"))
      } else {
        Write-Log ("  新鲜度 ok：{0}（{1:N1} 小时前）" -f $s.name, $ageHours)
      }
    }
  } elseif (-not $enabled) {
    Write-Log "  跳过新鲜度：$($s.name)（自动跑是关的）"
  }

  $lr = $sc.PSObject.Properties["lastResult"]
  if ($lr -and $lr.Value) {
    $text = [string]$lr.Value
    if ($text -match '失败|error|403|401|超时|timeout|NO_ADAPTER|MISSING_CREDENTIAL|UNKNOWN_MODEL') {
      Add-Problem "src:$($s.name):lastresult" "$($s.name)：上次结果是「$text」"
    }
  }
}

# ---------------------------------------------------------------- 汇总 + 通知
if ($problems.Count -eq 0) {
  Write-Log "全部正常。"
  exit 0
}

Write-Log ("发现问题 {0} 条：" -f $problems.Count)
foreach ($p in $problems) { Write-Log "  - $($p.text)" }

# 去重：同类问题 cooldown 内不重复推
$statePath = Join-Path $dshHome "duty-watch-state.json"
$state = @{}
if (Test-Path $statePath) {
  try { (Get-Content $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value } } catch {}
}
$cooldown = if ($cfg.notify -and $cfg.notify.cooldownHours) { [double]$cfg.notify.cooldownHours } else { 6 }
$fresh = @()
foreach ($p in $problems) {
  $last = $state[$p.key]
  if ($last) {
    $t = [datetime]::MinValue
    if ([datetime]::TryParse([string]$last, [ref]$t) -and ([datetime]::UtcNow - $t.ToUniversalTime()).TotalHours -lt $cooldown) { continue }
  }
  $fresh += $p
  $state[$p.key] = [datetime]::UtcNow.ToString("o")
}
try { [IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false))) } catch {}

if ($fresh.Count -eq 0) { Write-Log "都在冷却期内，这次不推。"; exit 1 }

$lines = @("【定时任务看门狗】" + (Get-Date -Format "MM-dd HH:mm"))
foreach ($p in $fresh) { $lines += "· " + $p.text }
$message = ($lines -join "`n")
# 发出去时压成一行（命令行参数里换行容易被吞）
$flat = ($lines -join " · ")

# 找 dsh-wechat-send
$sender = $null
if ($cfg.notify -and $cfg.notify.wechatSend) { $sender = Resolve-PathLike $cfg.notify.wechatSend }
if (-not $sender) {
  foreach ($c in @(
    (Join-Path $dshHome "profiles\desktop\node_modules\.bin\dsh-wechat-send.CMD"),
    (Join-Path $dshHome "profiles\desktop\node_modules\.bin\dsh-wechat-send.cmd")
  )) { if (Test-Path $c) { $sender = $c; break } }
}
$mode = if ($cfg.notify -and $cfg.notify.mode) { $cfg.notify.mode } else { "auto" }

if ($DryRun) {
  Write-Log "DRY-RUN：本该推送下面这条（没真发）"
  $message -split "`n" | ForEach-Object { Write-Log "    $_" }
  exit 1
}

if ($mode -ne "off" -and $sender) {
  try {
    & $sender $flat 2>&1 | ForEach-Object { Write-Log "    send: $_" }
    switch ($LASTEXITCODE) {
      0 { Write-Log "已推送微信。" }
      3 { Write-Log "微信窗口关着，消息已排队（你下次在微信里说一句话就会补发）。" }
      default { Write-Log "推送失败，退出码 $LASTEXITCODE。日志里还有完整记录。" }
    }
  } catch { Write-Log "推送失败：$($_.Exception.Message)" }
} else {
  Write-Log "没找到 dsh-wechat-send 或通知被关掉，只写日志。"
}

exit 1
