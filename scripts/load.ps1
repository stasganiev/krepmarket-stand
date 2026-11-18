<#
.SYNOPSIS
  Загружает src\cf в базу и обновляет конфигурацию базы данных.
.DESCRIPTION
  Режимы:
    (по умолчанию) полная загрузка всей конфигурации;
    -Changed       только измененные модули (.bsl) из git status - несколько секунд.
                   Если изменились XML, появились или удалены файлы - автоматически полная загрузка;
    -Files a,b     только перечисленные файлы (пути относительно src\cf).
  -Changed опирается на то, что база совпадает с последним коммитом.
  После git checkout / pull запускай полную загрузку.
.EXAMPLE
  .\scripts\load.ps1
  .\scripts\load.ps1 -Changed
#>
param(
    [switch]$Changed,
    [string[]]$Files,
    [string]$IbPath,
    [string]$SrcPath
)
. "$PSScriptRoot\_common.ps1"

$cfg = Get-StandConfig -IbPath $IbPath -SrcPath $SrcPath
Assert-Infobase $cfg

function Get-ChangedModules($cfg) {
    # Возвращает список .bsl относительно src\cf или $null, если нужна полная загрузка.
    $prev = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try {
        $srcRel = (Resolve-Path $cfg.SrcPath).Path.Substring($script:RepoRoot.Length).TrimStart('\').Replace('\', '/')
        $lines = git -C $script:RepoRoot -c core.quotepath=false status --porcelain --untracked-files=all -- $srcRel
    } finally { [Console]::OutputEncoding = $prev }

    $result = @()
    foreach ($l in $lines) {
        if (-not $l) { continue }
        $status = $l.Substring(0, 2)
        $path = $l.Substring(3).Trim('"')
        if ($status.Trim() -ne 'M' -or -not $path.EndsWith('.bsl')) {
            Write-Host "  структурное изменение: $l -> полная загрузка" -ForegroundColor Yellow
            return $null
        }
        $result += $path.Substring($srcRel.Length).TrimStart('/').Replace('/', '\')
    }
    , $result
}

if ($Changed) {
    $list = Get-ChangedModules $cfg
    if ($null -eq $list) { $Files = $null }
    elseif ($list.Count -eq 0) {
        Write-Host 'Изменений в src\cf нет - загружать нечего.' -ForegroundColor Green
        exit 0
    }
    else { $Files = $list }
}

$args2 = @('/L', 'ru', '/VL', 'ru', '/LoadConfigFromFiles', (Quote $cfg.SrcPath))
if ($Files) {
    Write-Step "Частичная загрузка: $($Files.Count) файл(ов)"
    $Files | ForEach-Object { Write-Host "  $_" }
    $args2 += @('-files', (Quote ($Files -join ',')), '-Format', 'Hierarchical')
} else {
    Write-Step 'Полная загрузка конфигурации'
}
$args2 += '/UpdateDBCfg'

$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-Designer -Config $cfg -LogName 'load.log' -Arguments $args2
if ($r.ExitCode -ne 0) {
    Write-Host $r.Log
    Write-Host "Загрузка не удалась (код $($r.ExitCode)). Лог: $($r.LogPath)" -ForegroundColor Red
    exit 2
}
Write-Host "Загружено и применено за $([int]$sw.Elapsed.TotalSeconds) с." -ForegroundColor Green
exit 0
