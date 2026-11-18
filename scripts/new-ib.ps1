<#
.SYNOPSIS
  Создает пустую файловую базу и загружает в нее конфигурацию из src\cf.
.DESCRIPTION
  По умолчанию база создается в папке .ib репозитория (в Git не попадает).
  Другой путь - параметр -IbPath или поле "ib" в stand.local.json.
  После создания один раз открой базу в 1С:Предприятии: БСП выполнит начальное заполнение.
.EXAMPLE
  .\scripts\new-ib.ps1
  .\scripts\new-ib.ps1 -IbPath D:\bases\krepmarket -Force
#>
param([string]$IbPath, [string]$SrcPath, [switch]$Force)
. "$PSScriptRoot\_common.ps1"

$cfg = Get-StandConfig -IbPath $IbPath -SrcPath $SrcPath

if (Test-Path (Join-Path $cfg.IbPath '1Cv8.1CD')) {
    if (-not $Force) {
        Write-Host "База уже есть: $($cfg.IbPath). Чтобы пересоздать, добавь -Force (база будет удалена)." -ForegroundColor Yellow
        exit 2
    }
    Write-Step "Удаляю старую базу $($cfg.IbPath)"
    Remove-Item -Recurse -Force $cfg.IbPath
}
if (-not (Test-Path (Join-Path $cfg.SrcPath 'Configuration.xml'))) {
    Write-Host "Нет выгрузки конфигурации: $($cfg.SrcPath)\Configuration.xml" -ForegroundColor Red
    exit 2
}

Write-Step "Создаю пустую базу $($cfg.IbPath)"
New-Item -ItemType Directory -Force $cfg.IbPath | Out-Null
$log = Join-Path $cfg.Logs 'create.log'
$p = Start-Process -FilePath $cfg.V8 -Wait -PassThru -NoNewWindow -ArgumentList @(
    'CREATEINFOBASE', ("File=""$($cfg.IbPath)"";Locale=ru_RU"), '/L', 'ru', '/Out', (Quote $log))
if ($p.ExitCode -ne 0) {
    Get-Content $log -Encoding UTF8 | Write-Host
    Write-Host 'Не удалось создать базу.' -ForegroundColor Red
    exit 2
}

& "$PSScriptRoot\load.ps1" -IbPath $cfg.IbPath -SrcPath $cfg.SrcPath
if ($LASTEXITCODE -ne 0) { exit 2 }

Write-Host ''
Write-Host 'База готова. Открой ее один раз в 1С:Предприятии - БСП выполнит начальное заполнение.' -ForegroundColor Green
Write-Host "Путь для списка баз: $($cfg.IbPath)"
exit 0
