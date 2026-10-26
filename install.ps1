<#
.SYNOPSIS
  把 dsh-yu-kit 的十个插件装进一个 DSH profile，并写好配置骨架。

.DESCRIPTION
  只做三件事：装插件、写 profile 配置、放人格骨架。
  不做的事：不去要你的 key、不登录任何账号、不覆盖你写过的人格。
  那些必须人动手的步骤，脚本最后会打出来（也在 MANUAL-STEPS.md 里）。

.EXAMPLE
  .\install.ps1
  .\install.ps1 -Profile desktop -Workspace "D:\my-workspace"
  .\install.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [string]$Profile = "desktop",
  [string]$Workspace = (Join-Path $env:USERPROFILE "dsh-workspace"),
  [switch]$SkipPlugins,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$kit = Get-Content (Join-Path $root "plugins.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE ".dsh" }

function Say($msg) { Write-Host $msg }
function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Ok($msg)   { Write-Host "  + $msg" -ForegroundColor Green }

# ---------------------------------------------------------------------------
# 1. 找 dsh CLI
#    桌面版不把 dsh 放进 PATH，它藏在 app.asar 里，得用 Electron 当 node 跑。
# ---------------------------------------------------------------------------
function Resolve-Dsh {
  $cmd = Get-Command dsh -ErrorAction SilentlyContinue
  if ($cmd) { return @{ Kind = "path"; Path = $cmd.Source } }

  $candidates = @(
    (Join-Path $env:PROGRAMFILES "DeepSeek Harness"),
    (Join-Path ${env:ProgramFiles(x86)} "DeepSeek Harness"),
    (Join-Path $env:LOCALAPPDATA "Programs\DeepSeek Harness"),
    "H:\DeepSeekHarness",
    (Join-Path $env:LOCALAPPDATA "DeepSeekHarness")
  ) | Where-Object { $_ -and (Test-Path $_) }

  foreach ($dir in $candidates) {
    $exe = Join-Path $dir "DeepSeek Harness.exe"
    $asar = Join-Path $dir "resources\app.asar"
    # ⚠️ app.asar 是个文件，它内部的路径只有 Electron 能看见 —— 这里只验外层，
    #    内层 cli.js 按约定拼，不做 Test-Path（普通 PowerShell 看不见 asar 内部）。
    if ((Test-Path $exe) -and (Test-Path $asar)) {
      $cli = Join-Path $dir "resources\app.asar\dsh\node_modules\@deepseek-ai\dsh-desktop-host\lib\cli.js"
      return @{ Kind = "electron"; Exe = $exe; Cli = $cli }
    }
  }
  return $null
}

$dsh = Resolve-Dsh
if (-not $dsh) {
  Warn "找不到 dsh。请先装 DSH 桌面版，或把 dsh 放进 PATH 再跑一次。"
  Warn "手工装也行：docs 见 AGENT-INSTALL.md 的『没有 CLI 时』一节。"
  exit 1
}
Ok ("dsh: " + $(if ($dsh.Kind -eq "path") { $dsh.Path } else { "$($dsh.Exe) (app.asar)" }))

function Invoke-Dsh {
  param([string[]]$DshArgs)
  if ($DryRun) { Say ("  [dry-run] dsh " + ($DshArgs -join " ")); return 0 }
  if ($dsh.Kind -eq "path") {
    & $dsh.Path @DshArgs
    return $LASTEXITCODE
  }
  # ⚠️ 桌面版的 exe 是 **GUI 子系统**程序：用 `& $exe` 调用拿不到 stdout 也拿不到
  #    退出码（PowerShell 直接返回空）。必须 Start-Process + -PassThru 才可靠。
  $old = $env:ELECTRON_RUN_AS_NODE
  $env:ELECTRON_RUN_AS_NODE = "1"
  try {
    $proc = Start-Process -FilePath $dsh.Exe -ArgumentList (@("--expose-internals", $dsh.Cli) + $DshArgs) -NoNewWindow -Wait -PassThru
    return $proc.ExitCode
  } finally {
    $env:ELECTRON_RUN_AS_NODE = $old
  }
}

# ---------------------------------------------------------------------------
# 2. 探测 python（B站转写要用）
# ---------------------------------------------------------------------------
$venvPy = Join-Path $dshHome "bili-duty\.venv\Scripts\python.exe"
$python = if (Test-Path $venvPy) { $venvPy } else {
  $p = Get-Command python -ErrorAction SilentlyContinue
  if ($p) { $p.Source } else { "python" }
}

Say "`nDSH_HOME : $dshHome"
Say "profile  : $Profile"
Say "工作区   : $Workspace"
Say "python   : $python"
if ($DryRun) { Say "`n(这是 dry-run，不改任何东西)" }

# ---------------------------------------------------------------------------
# 3. 装插件
# ---------------------------------------------------------------------------
if ($SkipPlugins) {
  Step "跳过插件安装（-SkipPlugins）"
} else {
  # 先看一眼这个 profile 是不是桌面版 profile：不是的话插件会装上但界面里看不到。
  $pkgPath = Join-Path $dshHome "profiles\$Profile\package.json"
  if (Test-Path $pkgPath) {
    $bundles = @()
    try { $bundles = (Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json).dsh.profile.bundles } catch {}
    if ($bundles -and ($bundles -notcontains "@deepseek-ai/dsh-web-app")) {
      Warn "profile「$Profile」里没有 @deepseek-ai/dsh-web-app —— 这不是桌面版 profile。"
      Warn "插件会装上，但 GUI 里不会出现它们的设置页。想用界面请装进 desktop 那类 profile。"
    }
  }

  Step "装插件（10 个，版本钉死）"
  $failed = @()
  foreach ($p in $kit.plugins) {
    Say ("  -> " + $p.name + "  " + $p.version)
    $code = 1
    for ($try = 1; $try -le 3; $try++) {
      $code = Invoke-Dsh @("plugin", "--profile", $Profile, "add", $p.source)
      if ($code -eq 0) { break }
      # ⚠️ 最常见的失败是网络抖动（ECONNRESET / ETIMEDOUT），不是配置问题 —— 值得重试。
      if ($try -lt 3 -and -not $DryRun) {
        Warn "第 $try 次失败（exit $code），5 秒后重试…"
        Start-Sleep -Seconds 5
      }
    }
    if ($code -ne 0) {
      $failed += $p
      Warn "$($p.name) 装了 3 次都没成（exit $code）。"
      Warn "先按这个顺序排查："
      Warn "  1. 网络：能不能访问 github.com / registry.npmjs.org（最常见）"
      Warn "  2. git 与 pnpm 是否可用"
      Warn "  3. 若 pnpm 提示 allowBuilds / approve-builds，按它打印的 key 写进"
      Warn "     $dshHome\profiles\$Profile\pnpm-workspace.yaml 的 allowBuilds: 再重跑"
      Warn "单独补装：dsh plugin --profile $Profile add $($p.source)"
    }
  }
  if ($failed.Count -gt 0) {
    Warn ""
    Warn "有 $($failed.Count) 个没装上：$(($failed | ForEach-Object { $_.name }) -join ', ')"
    Warn "其余照常继续。补装完再重跑一次这个脚本（加 -SkipPlugins 只写配置）。"
  } else {
    Ok "10 个插件全部装好"
  }
}

# ---------------------------------------------------------------------------
# 4. 写 profile 配置
# ---------------------------------------------------------------------------
Step "写 profile 配置"
$profileDir = Join-Path $dshHome "profiles\$Profile"
$patchPath = Join-Path $profileDir "cordis.patch.yml"
$template = Get-Content (Join-Path $root "profile\cordis.patch.template.yml") -Raw -Encoding UTF8

$rendered = $template.
  Replace("{{WORKSPACE}}",     $Workspace.Replace("\", "\\")).
  Replace("{{PYTHON}}",        $python.Replace("\", "\\")).
  Replace("{{OWNER_UID}}",     "0").
  Replace("{{BILI_MENTION}}",  "")

if ($DryRun) {
  Say "  [dry-run] 会写: $patchPath"
} else {
  New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
  if (Test-Path $patchPath) {
    $bak = "$patchPath.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item $patchPath $bak
    Warn "原有配置已备份到: $bak"
    Warn "新写进去的是模板 —— 你之前的个性化设置不会自动合并，需要自己比对补回去。"
  }
  [IO.File]::WriteAllText($patchPath, $rendered, (New-Object System.Text.UTF8Encoding($false)))
  Ok "写入: $patchPath"
}

# ---------------------------------------------------------------------------
# 5. 人格骨架
# ---------------------------------------------------------------------------
Step "人格骨架"
$agents = Join-Path $dshHome "AGENTS.md"
if (Test-Path $agents) {
  Ok "已有 $agents —— 不动它（这是你的人格，脚本不该覆盖）。"
  Say "  想换成本套的骨架：先备份，再把 profile\AGENTS.template.md 拷过去。"
} elseif ($DryRun) {
  Say "  [dry-run] 会放一份骨架到: $agents"
} else {
  Copy-Item (Join-Path $root "profile\AGENTS.template.md") $agents
  Ok "放了一份骨架到 $agents —— 打开它，把 <尖括号> 换成你自己的话。"
}

# ---------------------------------------------------------------------------
# 6. 还要人动手的地方
# ---------------------------------------------------------------------------
Step "还要你自己动手（脚本做不到）"
$i = 0
foreach ($p in $kit.plugins) {
  if (-not $p.manual -or $p.manual.Count -eq 0) { continue }
  $i++
  Write-Host ("  [{0}] {1}" -f $i, $p.name) -ForegroundColor White
  foreach ($m in $p.manual) { Say ("      - " + $m) }
}
Say ""
Warn "模型 key 还没填 —— 没 key 一句话都说不了：设置 → 模型。"
Warn "人格还没写 —— 那是全套东西里唯一不能自动化的部分。"
Warn "完整清单（含微信扫码、QQ 客户端、Agnes key）：MANUAL-STEPS.md"

Step "装完这样验"
Say "  1) dsh --profile $Profile --dump-config    # 能打出配置树就说明插件装上了"
Say "  2) 启动 DSH 桌面版，左侧应该能看到这些插件的设置页"
Say "  3) 设置 → 模型，填 key，随便说一句话"
Say "  4) 只登 B站，跑一轮（插件设置页有『立刻跑一轮』），看它写出来的日报像不像人"
