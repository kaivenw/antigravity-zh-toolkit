<#
.SYNOPSIS
    Antigravity 中文汉化 / 可恢复管理器（Windows）

.DESCRIPTION
    ag-zh.ps1 status        查看汉化状态、备份校验
    ag-zh.ps1 install       安装/刷新汉化（首次自动做整包备份）
    ag-zh.ps1 backup-full   单独创建整包备份
    ag-zh.ps1 restore       还原英文原版（只替换 app.asar）
    ag-zh.ps1 restore-full  整包回滚到备份状态
    ag-zh.ps1 help          显示帮助

    建议通过同目录下的 ag-zh.cmd 调用（它会处理执行策略与编码）。
    环境变量：AGZH_ASAR、AGZH_BACKUP_ROOT、AGZH_PYTHON、AGZH_FULL_BAK。

.NOTES
    Windows 无需代码签名步骤；修改 app.asar 不影响 Antigravity.exe 的 Authenticode 签名。
    所有修改操作都要求 Antigravity 已完全退出；restore-full 把当前应用改名保留而非删除。
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'install', 'backup-full', 'restore', 'restore-full', 'help')]
    [string]$Action = 'help',
    [string]$Asar,
    [string]$BackupRoot,
    [string]$Python
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $Asar)       { $Asar = $env:AGZH_ASAR }
if (-not $BackupRoot) { $BackupRoot = if ($env:AGZH_BACKUP_ROOT) { $env:AGZH_BACKUP_ROOT } else { Join-Path $env:USERPROFILE '.antigravity-zh-backup' } }
if (-not $Python)     { $Python = if ($env:AGZH_PYTHON) { $env:AGZH_PYTHON } else { 'python' } }

$Repo       = $PSScriptRoot
$Installer  = Join-Path $Repo 'install.py'
$Manifest   = Join-Path $BackupRoot 'manifest.json'
$ExtDict    = Join-Path $env:USERPROFILE '.antigravity-zh\zh-CN.json'

function Write-Step([string]$Text) { Write-Host $Text }
function Get-Sha256([string]$Path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

function Invoke-Py {
    param([string[]]$PyArgs)
    $exe = $Python
    $prefix = @()
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            $exe = 'py'
            $prefix = @('-3')
        }
        else {
            throw '未找到 Python 3，请安装并加入 PATH： https://www.python.org/downloads/'
        }
    }
    $all = $prefix + $PyArgs
    $out = & $exe @all 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Python 执行失败，退出码 $LASTEXITCODE" }
    return $out
}

function Get-Info {
    if (-not (Test-Path -LiteralPath $Installer)) { throw "仓库文件不完整，缺少 $Installer" }
    if ($Asar) { $env:AGZH_ASAR = $Asar }
    $raw = Invoke-Py @($Installer, '--info')
    if (-not $raw.Trim()) { throw 'install.py --info 没有返回内容' }
    try { $info = $raw | ConvertFrom-Json } catch { throw "无法解析状态 JSON：$($_.Exception.Message)`n$raw" }
    if (-not $info.exists) { throw "找不到 app.asar：$($info.asar)" }
    return $info
}

function Get-Rel([object]$Info) {
    return $Info.asar.Substring($Info.app_root.Length).TrimStart([char[]]@('\', '/'))
}

function Assert-Idle {
    $procs = @(Get-Process -Name 'Antigravity' -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 0) {
        throw 'Antigravity 正在运行，请先完全退出（托盘图标右键退出 / 任务管理器结束）再执行本操作。'
    }
}

function Copy-Tree {
    param([string]$Src, [string]$Dst)
    # robocopy 退出码 0-7 均为成功，>=8 才是失败
    $null = & robocopy $Src $Dst /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>$null
    if ($LASTEXITCODE -ge 8) { throw "robocopy 失败，退出码 $LASTEXITCODE" }
}

function Get-ManifestField([string]$Name) {
    if (-not (Test-Path -LiteralPath $Manifest)) { return '' }
    try { $m = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return '' }
    $p = $m.PSObject.Properties[$Name]
    if ($p) { return [string]$p.Value }
    return ''
}

function Write-Manifest {
    param([object]$Info, [string]$Backup, [string]$Official, [string]$Bsha)
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    }
    $data = [ordered]@{
        schema               = 1
        created_at           = (Get-Date).ToString('o')
        platform             = 'win32'
        version              = $Info.version
        app_root             = $Info.app_root
        asar                 = $Info.asar
        full_app_backup      = $Backup
        backup_asar_sha256   = $Bsha
        official_asar_sha256 = $Official
        patch_source         = 'https://github.com/zhonghugo/antigravity-zh (MIT)'
        tools                = @('ag-zh (macOS/Linux)', 'ag-zh.ps1 (Windows)')
        commands             = @('status', 'backup-full', 'install', 'restore', 'restore-full')
        notes                = @(
            'install 会在修改前自动创建整包备份',
            'restore 只替换 app.asar；restore-full 整包回滚',
            '官方升级后重跑 install；整包备份按版本分别保存'
        )
    }
    $json = $data | ConvertTo-Json -Depth 5
    # 无 BOM 的 UTF-8，方便 Python / 其他平台读取
    [System.IO.File]::WriteAllText($Manifest, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Step "[OK] 备份清单已更新: $Manifest"
}

function Get-BackupDir([string]$Version) {
    return (Join-Path $BackupRoot "Antigravity-$Version")
}

function Get-FullBackupPath {
    if ($env:AGZH_FULL_BAK) { return $env:AGZH_FULL_BAK }
    return (Get-ManifestField 'full_app_backup')
}

function Ensure-FullBackup {
    param([object]$Info)
    $rel = Get-Rel $Info
    $backup = Get-FullBackupPath
    if ($backup -and (Test-Path -LiteralPath (Join-Path $backup $rel)) -and
        ((Get-ManifestField 'version') -eq $Info.version -or $env:AGZH_FULL_BAK)) {
        Write-Step "[*] 复用整包备份: $backup"
        return $backup
    }
    $dest = Get-BackupDir $Info.version
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    }
    if (Test-Path -LiteralPath $dest) {
        Write-Step "[*] 已存在同版本备份，直接复用: $dest"
    }
    else {
        Write-Step '[*] 首次汉化，正在创建整包备份（robocopy，可能几百 MB）...'
        Copy-Tree -Src $Info.app_root -Dst $dest
    }
    $backupAsar = Join-Path $dest $rel
    if (-not (Test-Path -LiteralPath $backupAsar)) { throw "整包备份缺少 $rel，已中止汉化以保证可恢复。" }
    $bsha = Get-Sha256 $backupAsar
    $official = if ($Info.backup_exists) { [string]$Info.backup_sha256 } else { [string]$Info.sha256 }
    Write-Manifest -Info $Info -Backup $dest -Official $official -Bsha $bsha
    Write-Step "[OK] 整包备份就绪: $dest"
    return $dest
}

function Ensure-OfficialBackup {
    param([object]$Info)
    $bak = $Info.asar + '.bak'
    if (Test-Path -LiteralPath $bak) { return }
    $rel = Get-Rel $Info
    $backup = Get-FullBackupPath
    if (-not $backup) { $backup = Get-BackupDir $Info.version }
    $src = Join-Path $backup $rel
    if (-not (Test-Path -LiteralPath $src)) { throw '官方原版备份缺失且整包备份不可用，无法保证可恢复。' }
    $expected = Get-ManifestField 'official_asar_sha256'
    if ($expected -and ((Get-Sha256 $src) -ne $expected)) {
        throw '整包备份中的 asar 不是官方原版，拒绝用它生成 .bak。'
    }
    Copy-Item -LiteralPath $src -Destination $bak -Force
    Write-Step '[OK] 已从整包备份补齐官方原版 app.asar.bak'
}

function Invoke-Installer {
    param([object]$Info, [string[]]$Extra)
    $env:AGZH_ASAR = $Info.asar
    $out = Invoke-Py (@($Installer) + $Extra)
    if ($out.Trim()) { Write-Host $out.TrimEnd() }
}

function Show-Status {
    param([object]$Info)
    Write-Step '== Antigravity 汉化状态 =='
    Write-Step "平台           : Windows / $($Info.platform)"
    Write-Step "版本           : $($Info.version)"
    Write-Step "应用根目录     : $($Info.app_root)"
    Write-Step "app.asar       : $($Info.asar)"
    Write-Step ''
    Write-Step "当前 app.asar  : $($Info.sha256)"
    $bak = $Info.asar + '.bak'
    if (Test-Path -LiteralPath $bak) {
        $b = Get-Sha256 $bak
        Write-Step "官方原版 .bak  : $b"
        if ($b -eq $Info.sha256) { Write-Step '界面模式       : 英文原版（未汉化）' }
        else { Write-Step '界面模式       : 中文汉化版' }
    }
    else { Write-Step '官方原版 .bak  : 缺失（install 会自动补齐）' }
    Write-Step "引擎注入检测   : $($Info.localized)"
    Write-Step "词典词条       : $($Info.dictionary_entries)"
    Write-Step ''
    $backup = Get-FullBackupPath
    $rel = Get-Rel $Info
    if ($backup -and (Test-Path -LiteralPath (Join-Path $backup $rel))) {
        Write-Step "整包备份       : $backup  [备份版本 $(Get-ManifestField 'version')]"
        Write-Step "备份 asar 校验 : $(Get-Sha256 (Join-Path $backup $rel))"
    }
    else { Write-Step '整包备份       : 缺失（运行 ag-zh.cmd install 会自动创建）' }
    Write-Step ''
    if (Test-Path -LiteralPath $ExtDict) { Write-Step "热重载词典     : $ExtDict（编辑后自动生效）" }
    Write-Step ''
    Write-Step '可用命令: ag-zh.cmd status | install | backup-full | restore | restore-full | help'
}

function Invoke-Install {
    param([object]$Info)
    Assert-Idle
    Ensure-FullBackup -Info $Info | Out-Null
    Ensure-OfficialBackup -Info $Info
    Write-Step '[*] 安装 / 刷新中文汉化 ...'
    Invoke-Installer -Info $Info -Extra @()
    Write-Step '[OK] 完成。启动 Antigravity 查看中文界面。'
    Write-Step '[i]  随时可用 ag-zh.cmd restore 或 ag-zh.cmd restore-full 恢复。'
}

function Invoke-Restore {
    param([object]$Info)
    Assert-Idle
    Ensure-OfficialBackup -Info $Info
    Write-Step '[*] 还原官方原版 app.asar ...'
    Invoke-Installer -Info $Info -Extra @('--restore')
    $a = Get-Sha256 $Info.asar
    $b = Get-Sha256 ($Info.asar + '.bak')
    if ($a -ne $b) { throw "还原后校验失败（$a != $b）" }
    Write-Step '[OK] 已回到英文原版，SHA256 校验通过。'
}

function Invoke-RestoreFull {
    param([object]$Info)
    Assert-Idle
    $backup = Get-FullBackupPath
    $rel = Get-Rel $Info
    if (-not $backup) { throw '没有找到整包备份，请先运行 ag-zh.cmd install 或 ag-zh.cmd backup-full。' }
    $backupAsar = Join-Path $backup $rel
    if (-not (Test-Path -LiteralPath $backupAsar)) {
        throw "整包备份不存在或不完整：$backupAsar"
    }
    $bsha = Get-Sha256 $backupAsar
    $curVer = [string]$Info.version
    $bakVer = Get-ManifestField 'version'
    if ($bakVer -and $bakVer -ne $curVer) {
        Write-Step "[!] 注意：当前版本 $curVer，备份版本 $bakVer；完整恢复会回退到 $bakVer。"
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $old = "$($Info.app_root).agzh-old-$stamp"
    Write-Step "[*] 保留当前应用到: $old"
    Move-Item -LiteralPath $Info.app_root -Destination $old
    try {
        Copy-Tree -Src $backup -Dst $Info.app_root
    }
    catch {
        Write-Step '[!] 恢复失败，正在回滚 ...'
        if (Test-Path -LiteralPath $Info.app_root) {
            Move-Item -LiteralPath $Info.app_root -Destination "$($Info.app_root).agzh-failed-$stamp"
        }
        Move-Item -LiteralPath $old -Destination $Info.app_root
        throw
    }
    if ((Get-Sha256 $Info.asar) -ne $bsha) { throw "恢复后校验未通过，请检查 $($Info.app_root) 与 $old" }
    Write-Step '[OK] 完整恢复成功，asar SHA256 校验通过。'
    Write-Step "[i]  当前版本已保留在: $old"
    Write-Step '     确认无误后可手动删除（建议移到回收站）'
}

function Show-Help {
    Write-Step 'ag-zh - Antigravity 中文汉化 / 可恢复管理器（Windows）'
    Write-Step ''
    Write-Step '  ag-zh.cmd status         查看汉化状态、备份校验'
    Write-Step '  ag-zh.cmd install        安装/刷新汉化（首次自动做整包备份）'
    Write-Step '  ag-zh.cmd backup-full    单独创建整包备份'
    Write-Step '  ag-zh.cmd restore        还原英文原版（只替换 app.asar）'
    Write-Step '  ag-zh.cmd restore-full   整包回滚到备份状态'
    Write-Step '  ag-zh.cmd help           显示帮助'
    Write-Step ''
    Write-Step '也可以直接: powershell -ExecutionPolicy Bypass -File .\ag-zh.ps1 status'
    Write-Step '环境变量: AGZH_ASAR / AGZH_BACKUP_ROOT / AGZH_PYTHON / AGZH_FULL_BAK'
}

try {
    switch ($Action) {
        'status'       { Show-Status -Info (Get-Info) }
        'install'      { Invoke-Install -Info (Get-Info) }
        'backup-full'  { Ensure-FullBackup -Info (Get-Info) | Out-Null }
        'restore'      { Invoke-Restore -Info (Get-Info) }
        'restore-full' { Invoke-RestoreFull -Info (Get-Info) }
        'help'         { Show-Help }
    }
}
catch {
    Write-Host "[ERR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
exit 0
