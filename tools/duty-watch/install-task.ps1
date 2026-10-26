<#
.SYNOPSIS
  把 duty-watch 注册成 Windows 计划任务，每 N 小时跑一次。

.DESCRIPTION
  默认每 6 小时跑一次，从现在开始算。用当前用户身份运行（不需要管理员），
  这样它才能读到你的 ~/.dsh。

  第一次建议先手动跑一遍：
      .\duty-watch.ps1 -DryRun

  然后注册：
      .\install-task.ps1
      .\install-task.ps1 -EveryHours 3 -TaskName "dsh-duty-watch"

  取消：
      Unregister-ScheduledTask -TaskName "dsh-duty-watch" -Confirm:$false
#>
[CmdletBinding()]
param(
  [string]$TaskName = "dsh-duty-watch",
  [int]$EveryHours = 6,
  [string]$ScriptPath
)

$ErrorActionPreference = "Stop"

if (-not $ScriptPath) { $ScriptPath = Join-Path $PSScriptRoot "duty-watch.ps1" }
if (-not (Test-Path $ScriptPath)) { throw "找不到 $ScriptPath" }
if ($EveryHours -lt 1) { throw "-EveryHours 至少 1" }

$pwsh = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command pwsh.exe).Source }

# -NoProfile：别让用户的 profile 拖慢/污染
$action = New-ScheduledTaskAction -Execute $pwsh `
  -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath)

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
  -RepetitionInterval (New-TimeSpan -Hours $EveryHours)

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

# 交互式登录才跑：它要读 ~/.dsh，也可能要调 dsh-wechat-send
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
  Write-Host "已存在同名任务，先删掉旧的…" -ForegroundColor Yellow
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
  -Description "dsh-yu-kit 定时任务看门狗：探网关、查四个任务是否在跑、出问题推微信" | Out-Null

Write-Host ""
Write-Host "已注册计划任务：$TaskName" -ForegroundColor Green
Write-Host "  每 $EveryHours 小时跑一次；2 分钟后第一次"
Write-Host "  日志：$env:USERPROFILE\.dsh\duty-watch.log"
Write-Host "  立刻验证一次： Start-ScheduledTask -TaskName $TaskName"
Write-Host "  看结果：       Get-ScheduledTaskInfo -TaskName $TaskName"
Write-Host "  取消：         Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false"
