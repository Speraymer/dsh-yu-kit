<#
.SYNOPSIS
  把 dsh-yu-kit 的十个插件装进一个 DSH profile，并验证安装结果。

.DESCRIPTION
  只做两件事：装插件、验证 profile。
  不做的事：不去要 key、不登录账号、不覆盖 profile 配置和人格。
  那些必须人动手的步骤，脚本最后会打出来（也在 MANUAL-STEPS.md 里）。

.EXAMPLE
  .\install.ps1
  .\install.ps1 -Profile desktop -DshInstallDir "D:\DeepSeek Harness"
  .\install.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [string]$Profile = "desktop",
  [string]$DshInstallDir = "",
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
    $DshInstallDir,
    (Join-Path $env:PROGRAMFILES "DeepSeek Harness"),
    (Join-Path ${env:ProgramFiles(x86)} "DeepSeek Harness"),
    (Join-Path $env:LOCALAPPDATA "Programs\DeepSeek Harness"),
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
Say "`nDSH_HOME : $dshHome"
Say "profile  : $Profile"
if ($DryRun) { Say "`n(这是 dry-run，不改任何东西)" }

# ---------------------------------------------------------------------------
# 2. 装插件
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
    Warn "为避免半安装状态被误报为成功，脚本到此停止。修复后直接重跑即可。"
    exit 1
  } else {
    if ($DryRun) { Ok "dry-run 计划检查完成（未实际安装）" }
    else { Ok "10 个插件全部装好" }
  }
}

# ---------------------------------------------------------------------------
# 4. 验证 profile；不覆盖用户配置
# ---------------------------------------------------------------------------
Step "验证插件清单"
$profileDir = Join-Path $dshHome "profiles\$Profile"
$pkgPath = Join-Path $profileDir "package.json"
if (-not $DryRun) {
  if (-not (Test-Path $pkgPath)) { throw "找不到 profile package.json：$pkgPath" }
  $pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $deps = @($pkg.dependencies.PSObject.Properties.Name)
  $bundles = @($pkg.dsh.profile.bundles)
  $missing = @($kit.plugins | Where-Object { $deps -notcontains $_.name -or $bundles -notcontains $_.name })
  if ($missing.Count) { throw "安装校验失败，依赖或 bundle 缺少：$(($missing.name) -join ', ')" }
  $wrongVersion = @()
  foreach ($p in $kit.plugins) {
    $installedMeta = Join-Path $profileDir ("node_modules\" + $p.name + "\package.json")
    if (-not (Test-Path $installedMeta)) { $wrongVersion += "$($p.name)=未安装"; continue }
    $actual = (Get-Content $installedMeta -Raw -Encoding UTF8 | ConvertFrom-Json).version
    if ($actual -ne $p.version) { $wrongVersion += "$($p.name)=$actual（需要 $($p.version)）" }
  }
  if ($wrongVersion.Count) { throw "安装版本校验失败：$($wrongVersion -join ', ')" }
  Ok "10 个插件的 dependencies、bundles 与实际版本均正确"
}

# ---------------------------------------------------------------------------
# 5. 人格与配置只给指引，不自动写
# ---------------------------------------------------------------------------
Step "人格与配置"
$agents = Join-Path $dshHome "AGENTS.md"
if (Test-Path $agents) {
  Ok "已有 $agents —— 不动它（这是你的人格，脚本不该覆盖）。"
} else {
  Warn "还没有 $agents；请先阅读 profile\AGENTS.template.md，再由用户确认后复制。"
}
Say "  profile\cordis.patch.template.yml 只作参考；安装器不会覆盖现有 cordis.patch.yml。"

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
if (-not $DryRun) {
  if (Test-Path (Join-Path $profileDir ".plugin-manager")) {
    Warn "desktop profile 由 Electron 专管，CLI 会拒绝 --dump-config；已完成清单与版本校验，请重启 GUI 验证设置页。"
  } else {
    $code = Invoke-Dsh @("--profile", $Profile, "--dump-config")
    if ($code -ne 0) { throw "配置树验证失败（exit $code）" }
    Ok "dsh --profile $Profile --dump-config 通过"
  }
}
Say "  1) 启动或重启 DSH 桌面版"
Say "  2) 设置页确认十个插件入口"
Say "  3) 按 MANUAL-STEPS.md 完成人工登录与 key 配置"
