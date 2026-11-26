#!/usr/bin/env pwsh
# SPDX-License-Identifier: ISC
# Copyright (c) 2026 mtueih
#
# 根据 git 提交历史（Conventional Commits）与构建产物生成发布说明。
#
# 与上游只输出一行 "Full Changelog" 不同，这里会把提交按类型分组，附上
# 构建信息、产物大小与 SHA-256，方便用户直接判断是否需要升级。

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [string]$PreviousTag = "",
    [Parameter(Mandatory)][string]$Repository,
    [string[]]$Assets = @(),
    [string]$ZigVersion = "",
    [string]$Optimize = "ReleaseFast",
    [string]$Output = "RELEASE_NOTES.md"
)

$ErrorActionPreference = "Stop"

$typeOrder = @("feat", "fix", "perf", "refactor", "build", "ci", "test", "docs", "style", "chore", "other")
$typeTitles = @{
    feat     = "新功能"
    fix      = "修复"
    perf     = "性能"
    refactor = "重构"
    build    = "构建"
    ci       = "持续集成"
    test     = "测试"
    docs     = "文档"
    style    = "代码风格"
    chore    = "杂项"
    other    = "其他"
}

function Get-HumanSize([long]$Bytes) {
    if ($Bytes -ge 1MB) { return "{0:N2} MiB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1} KiB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# ── 收集提交 ────────────────────────────────────────────────────────────

$range = if ($PreviousTag) { "$PreviousTag..$Tag" } else { $Tag }
$log = git log --no-merges --pretty=format:'%h%x1f%an%x1f%s' $range
if ($LASTEXITCODE -ne 0) { throw "git log 失败：$range" }

$groups = [ordered]@{}
foreach ($type in $typeOrder) {
    $groups[$type] = [System.Collections.Generic.List[string]]::new()
}
$breaking = [System.Collections.Generic.List[string]]::new()
$commitCount = 0

foreach ($line in ($log -split "`n")) {
    if (-not $line.Trim()) { continue }
    $parts = $line.Split([char]0x1f)
    if ($parts.Count -lt 3) { continue }

    $short = $parts[0]
    $author = $parts[1]
    $subject = $parts[2]
    $commitCount += 1

    $type = "other"
    $description = $subject
    $isBreaking = $false

    $match = [regex]::Match($subject, '^(?<type>[A-Za-z]+)(?:\((?<scope>[^)]*)\))?(?<breaking>!)?:\s*(?<desc>.+)$')
    if ($match.Success) {
        $type = $match.Groups["type"].Value.ToLowerInvariant()
        if (-not $groups.Contains($type)) { $type = "other" }
        $description = $match.Groups["desc"].Value.Trim()
        if ($match.Groups["scope"].Success) {
            $description = "**$($match.Groups["scope"].Value)**：$description"
        }
        $isBreaking = $match.Groups["breaking"].Success
    }

    $entry = "- $description（commit $short，$author）"
    $groups[$type].Add($entry)

    if ($isBreaking) {
        $breaking.Add("- $description（commit $short，$author）")
    }
}

# ── 产物信息 ────────────────────────────────────────────────────────────

$assetRows = [System.Collections.Generic.List[string]]::new()
foreach ($asset in ($Assets -split ',' | Where-Object { $_ })) {
    if (-not (Test-Path -LiteralPath $asset)) { continue }
    $item = Get-Item -LiteralPath $asset
    $checksumPath = "$asset.sha256"
    if (Test-Path -LiteralPath $checksumPath) {
        $hash = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    }
    else {
        $hash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $assetRows.Add("| ``$($item.Name)`` | $(Get-HumanSize $item.Length) | ``$hash`` |")
}

# ── 组装 Markdown ───────────────────────────────────────────────────────

$version = $Tag -replace '^v', ''
$releaseDate = (git log -1 --format=%cs $Tag).Trim()
$lines = [System.Collections.Generic.List[string]]::new()

$lines.Add("# run_hidden $Tag")
$lines.Add("")
$lines.Add("Windows 下以隐藏窗口启动进程的轻量级工具（Zig 实现）。")
$lines.Add("")
$lines.Add("本版本于 $releaseDate 由 CD 自动构建并发布，包含 $commitCount 个提交。")
$lines.Add("")

if ($assetRows.Count -gt 0) {
    $lines.Add("## 下载")
    $lines.Add("")
    $lines.Add("| 文件 | 大小 | SHA-256 |")
    $lines.Add("| --- | --- | --- |")
    foreach ($row in $assetRows) { $lines.Add($row) }
    $lines.Add("")
    $lines.Add("校验方式：``Get-FileHash <文件> -Algorithm SHA256``，或直接比对同目录下的 ``.sha256`` 文件。")
    $lines.Add("")
}

$lines.Add("## 构建信息")
$lines.Add("")
$lines.Add("| 项目 | 值 |")
$lines.Add("| --- | --- |")
$lines.Add("| 版本 | ``$version`` |")
if ($ZigVersion) { $lines.Add("| Zig | ``$ZigVersion`` |") }
$lines.Add("| 优化模式 | ``$Optimize`` |")
$lines.Add("| 目标平台 | ``x86_64-windows`` |")
$lines.Add("| 构建 | ReleaseFast + strip（无调试信息） |")
$lines.Add("")

if ($breaking.Count -gt 0) {
    $lines.Add("## ⚠ 破坏性变更")
    $lines.Add("")
    foreach ($entry in $breaking) { $lines.Add($entry) }
    $lines.Add("")
}

$hasChanges = $false
foreach ($type in $typeOrder) {
    $entries = $groups[$type]
    if ($entries.Count -eq 0) { continue }
    $hasChanges = $true
    $lines.Add("## $($typeTitles[$type])")
    $lines.Add("")
    foreach ($entry in $entries) { $lines.Add($entry) }
    $lines.Add("")
}

if (-not $hasChanges) {
    $lines.Add("## 本版变更")
    $lines.Add("")
    $lines.Add("本版本没有可归类的提交。")
    $lines.Add("")
}

$lines.Add("## 安装与使用")
$lines.Add("")
$lines.Add("解压后把 ``bin`` 目录加入 ``PATH``，然后：")
$lines.Add("")
$lines.Add('```bat')
$lines.Add('run_hidden "C:\path\to\app.exe" "arg with space"')
$lines.Add('run_hidden_wait "C:\path\to\app.exe" --wait-for-exit')
$lines.Add('```')
$lines.Add("")
$lines.Add("``run_hidden`` 启动成功后立即返回，``run_hidden_wait`` 等待目标程序结束并透传其退出码。")
$lines.Add("")
$lines.Add("## 完整变更记录")
$lines.Add("")
if ($PreviousTag) {
    $lines.Add("https://github.com/$Repository/compare/$PreviousTag...$Tag")
}
else {
    $lines.Add("这是首个发布版本，暂无更早的标签可供比较。")
}
$lines.Add("")
$lines.Add("---")
$lines.Add("")
$lines.Add("本项目采用 [ISC 许可证](https://github.com/$Repository/blob/$Tag/LICENSE) 授权。")

$text = ($lines -join "`n") + "`n"
$outputPath = if ([System.IO.Path]::IsPathRooted($Output)) {
    $Output
}
else {
    Join-Path (Get-Location) $Output
}
[System.IO.File]::WriteAllText(
    $outputPath,
    $text,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "已生成发布说明：$outputPath"
