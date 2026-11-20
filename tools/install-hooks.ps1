<#
.SYNOPSIS
  Ставит Git-хуки автора курса: защита публичного репозитория и резервная копия ветки etalon.
.DESCRIPTION
  pre-push    - не дает отправить ветку etalon, теги lesson-* и (без publish-etalon.ps1) etalon-*,
                а также письма и транскрипт проекта (fixtures/letters, fixtures/analysis).
  post-commit - после коммита в etalon обновляет etalon.bundle в папке -BackupDir.
  Участникам курса хуки не нужны.
.EXAMPLE
  .\tools\install-hooks.ps1 -BackupDir C:\AI_dev\work_AI_arsenal_1C\work\edition_2\stand\etalon_backup
#>
param([string]$BackupDir)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$hooks = Join-Path $repo '.git\hooks'
foreach ($h in 'pre-push', 'post-commit') {
    $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "git-hooks\$h")) -replace "`r`n", "`n"
    [IO.File]::WriteAllText((Join-Path $hooks $h), $text, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Установлен хук $h"
}
if ($BackupDir) {
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    git -C $repo config km.etalonBackup ($BackupDir -replace '\\', '/')
    Write-Host "Резервная копия etalon: $BackupDir\etalon.bundle"
}
