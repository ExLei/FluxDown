<#
.SYNOPSIS
    FluxDown 内存调试 - 步骤1: 启动应用并捕获输出
.DESCRIPTION
    后台启动 flutter run --profile，将输出实时写入日志文件。
    自动提取 VM Service URL 供后续脚本使用。
.USAGE
    .\scripts\mem_debug_launch.ps1 [-Mode profile|debug] [-Device windows]
#>
param(
    [ValidateSet("profile", "debug")]
    [string]$Mode = "profile",
    [string]$Device = "windows"
)

$ErrorActionPreference = "Stop"
$OutputDir = Join-Path (Join-Path $PSScriptRoot "..") ".mem_debug"
$LogFile = Join-Path $OutputDir "flutter_output.log"
$PidFile = Join-Path $OutputDir "flutter.pid"
$UrlFile = Join-Path $OutputDir "vm_service_url.txt"

# 创建输出目录
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# 清理旧文件
@($LogFile, $PidFile, $UrlFile) | ForEach-Object {
    if (Test-Path $_) { Remove-Item $_ -Force }
}

Write-Host "[mem_debug] 启动 flutter run -d $Device --$Mode ..." -ForegroundColor Cyan
Write-Host "[mem_debug] 日志文件: $LogFile" -ForegroundColor Gray

# 后台启动 flutter run，输出重定向到日志文件
$process = Start-Process -FilePath "flutter" `
    -ArgumentList "run", "-d", $Device, "--$Mode" `
    -WorkingDirectory (Join-Path $PSScriptRoot "..") `
    -RedirectStandardOutput $LogFile `
    -RedirectStandardError (Join-Path $OutputDir "flutter_stderr.log") `
    -PassThru `
    -NoNewWindow

# 保存 PID
$process.Id | Out-File -FilePath $PidFile -Encoding utf8

Write-Host "[mem_debug] Flutter PID: $($process.Id)" -ForegroundColor Green
Write-Host "[mem_debug] 等待 VM Service URL ..." -ForegroundColor Yellow

# 轮询日志文件，提取 VM Service URL（最多等待 120 秒）
$timeout = 120
$elapsed = 0
$vmUrl = $null

while ($elapsed -lt $timeout) {
    Start-Sleep -Seconds 2
    $elapsed += 2

    if (Test-Path $LogFile) {
        $content = Get-Content $LogFile -Raw -ErrorAction SilentlyContinue
        if ($content) {
            # 匹配多种可能的 URL 格式
            $match = [regex]::Match($content, '(https?://127\.0\.0\.1:\d+/[^\s/]+/)')
            if ($match.Success) {
                $vmUrl = $match.Value
                break
            }
            # 备用匹配
            $match2 = [regex]::Match($content, 'VM Service .+?(https?://[^\s]+)')
            if ($match2.Success) {
                $vmUrl = $match2.Groups[1].Value
                break
            }
        }
    }

    # 检查进程是否已退出
    if ($process.HasExited) {
        Write-Host "[mem_debug] Flutter 进程已退出 (ExitCode: $($process.ExitCode))" -ForegroundColor Red
        Write-Host "[mem_debug] 查看错误日志: $(Join-Path $OutputDir 'flutter_stderr.log')" -ForegroundColor Red
        exit 1
    }

    Write-Host "  等待中... ($elapsed s / $timeout s)" -ForegroundColor DarkGray
}

if ($vmUrl) {
    $vmUrl | Out-File -FilePath $UrlFile -Encoding utf8 -NoNewline
    Write-Host ""
    Write-Host "====================================" -ForegroundColor Green
    Write-Host " VM Service URL: $vmUrl" -ForegroundColor Green
    Write-Host " 已保存到: $UrlFile" -ForegroundColor Green
    Write-Host "====================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "[mem_debug] 现在可以运行内存分析脚本:" -ForegroundColor Cyan
    Write-Host "  .\scripts\mem_debug_analyze.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "[mem_debug] 停止应用:" -ForegroundColor Cyan
    Write-Host "  .\scripts\mem_debug_stop.ps1" -ForegroundColor White
} else {
    Write-Host "[mem_debug] 超时：未能获取 VM Service URL" -ForegroundColor Red
    Write-Host "[mem_debug] 请手动查看日志: $LogFile" -ForegroundColor Yellow
    exit 1
}
