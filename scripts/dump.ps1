<#
.SYNOPSIS
  Выгружает конфигурацию из базы в файлы src\cf (иерархический формат).
.DESCRIPTION
  Полная выгрузка: сначала во временную папку, и только после успеха она заменяет src\cf.
  Удаленные в базе объекты не остаются в репозитории.
  Если в src\cf есть незакоммиченные изменения, скрипт остановится: выгрузка их перезапишет.
  Чтобы все равно выгрузить - -Force.
  Выгружай только этим скриптом, не из меню Конфигуратора: скрипт всегда работает
  на русском языке (/L ru), иначе часть макетов выгружается с английскими строками
  и в Git появляются ложные изменения.
.EXAMPLE
  .\scripts\dump.ps1
#>
param([string]$IbPath, [string]$SrcPath, [switch]$Force)
. "$PSScriptRoot\_common.ps1"

$cfg = Get-StandConfig -IbPath $IbPath -SrcPath $SrcPath
Assert-Infobase $cfg

if (-not $Force -and (Test-Path $cfg.SrcPath)) {
    $srcRel = $cfg.SrcPath.Substring($script:RepoRoot.Length).TrimStart('\').Replace('\', '/')
    $dirty = git -C $script:RepoRoot status --porcelain -- $srcRel
    if ($dirty) {
        Write-Host "В $srcRel есть незакоммиченные изменения ($(@($dirty).Count) файл(ов))." -ForegroundColor Yellow
        Write-Host 'Выгрузка перезапишет их содержимым базы. Если правки уже загружены в базу (load/check) или не нужны - запусти с -Force.' -ForegroundColor Yellow
        Write-Host 'Если правки не загружены - сначала .\scripts\load.ps1 -Changed' -ForegroundColor Yellow
        exit 2
    }
}

$tmp = "$($cfg.SrcPath).dump-tmp"
if (Test-Path $tmp) { cmd /c rd /s /q "\\?\$tmp" | Out-Null }
New-Item -ItemType Directory -Force $tmp | Out-Null

Write-Step 'Выгружаю конфигурацию в файлы'
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-Designer -Config $cfg -LogName 'dump.log' -Arguments @(
    '/L', 'ru', '/VL', 'ru',
    '/DumpConfigToFiles', (Quote $tmp), '-Format', 'Hierarchical')

if ($r.ExitCode -ne 0 -or -not (Test-Path (Join-Path $tmp 'Configuration.xml'))) {
    cmd /c rd /s /q "\\?\$tmp" | Out-Null
    Write-Host $r.Log
    Write-Host "Выгрузка не удалась (код $($r.ExitCode)), src\cf не тронут. Лог: $($r.LogPath)" -ForegroundColor Red
    exit 2
}

# Префикс \\?\ - в выгрузке БСП встречаются пути длиннее 260 символов.
if (Test-Path $cfg.SrcPath) { cmd /c rd /s /q "\\?\$($cfg.SrcPath)" | Out-Null }
Move-Item -LiteralPath $tmp -Destination $cfg.SrcPath

Write-Host "Готово за $([int]$sw.Elapsed.TotalSeconds) с. Дальше: git status" -ForegroundColor Green
exit 0
