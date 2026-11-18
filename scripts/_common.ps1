# Общие функции скриптов стенда «КрепМаркет».
# Подключается в начале каждого скрипта: . "$PSScriptRoot\_common.ps1"
#
# Настройки берутся по приоритету:
#   1. параметры скрипта (-IbPath, -SrcPath);
#   2. файл stand.local.json в корне репозитория (в Git не попадает, образец - stand.local.example.json);
#   3. переменные окружения KM_V8, KM_IB, KM_USER, KM_PASSWORD;
#   4. значения по умолчанию: самая свежая платформа 8.3.27 из Program Files, база в папке .ib репозитория.

$ErrorActionPreference = 'Stop'
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-StandConfig {
    param([string]$IbPath, [string]$SrcPath)

    $local = @{}
    $localFile = Join-Path $script:RepoRoot 'stand.local.json'
    if (Test-Path $localFile) {
        $json = Get-Content $localFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $local[$p.Name] = $p.Value }
    }

    $v8 = $local['v8']
    if (-not $v8) { $v8 = $env:KM_V8 }
    if (-not $v8) { $v8 = Find-Platform }

    $ib = $IbPath
    if (-not $ib) { $ib = $local['ib'] }
    if (-not $ib) { $ib = $env:KM_IB }
    if (-not $ib) { $ib = Join-Path $script:RepoRoot '.ib' }

    $src = $SrcPath
    if (-not $src) { $src = Join-Path $script:RepoRoot 'src\cf' }

    $user = $local['user'];         if (-not $user) { $user = $env:KM_USER }
    $pass = $local['password'];     if (-not $pass) { $pass = $env:KM_PASSWORD }

    $logs = Join-Path $script:RepoRoot 'logs'
    New-Item -ItemType Directory -Force $logs | Out-Null

    [pscustomobject]@{
        V8       = $v8
        IbPath   = $ib
        SrcPath  = $src
        User     = $user
        Password = $pass
        Logs     = $logs
    }
}

function Find-Platform {
    # Ищем 1cv8.exe версии 8.3.27.* (версия стенда). Если ее нет - берем самую свежую 8.3.*.
    $roots = @("$env:ProgramFiles\1cv8", "${env:ProgramFiles(x86)}\1cv8") | Where-Object { $_ -and (Test-Path $_) }
    $candidates = foreach ($r in $roots) {
        Get-ChildItem $r -Directory | Where-Object { $_.Name -match '^8\.3\.\d+\.\d+$' -and (Test-Path (Join-Path $_.FullName 'bin\1cv8.exe')) }
    }
    if (-not $candidates) {
        throw 'Не найдена платформа 1С 8.3 в Program Files. Укажи путь к 1cv8.exe в stand.local.json (поле "v8") или в переменной KM_V8.'
    }
    $sorted = $candidates | Sort-Object { [version]$_.Name } -Descending
    $preferred = $sorted | Where-Object { $_.Name -like '8.3.27.*' } | Select-Object -First 1
    if (-not $preferred) {
        $preferred = $sorted | Select-Object -First 1
        Write-Warning "Платформа 8.3.27 не найдена, использую $($preferred.Name). Стенд курса рассчитан на 8.3.27."
    }
    Join-Path $preferred.FullName 'bin\1cv8.exe'
}

function Invoke-Designer {
    # Запускает Конфигуратор в пакетном режиме. Возвращает код выхода и текст лога.
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)] [string[]]$Arguments,
        [Parameter(Mandatory)] [string]$LogName
    )
    $log = Join-Path $Config.Logs $LogName
    if (Test-Path $log) { Remove-Item $log -Force }

    $all = @('DESIGNER', '/F', (Quote $Config.IbPath), '/DisableStartupDialogs', '/DisableStartupMessages')
    if ($Config.User)     { $all += @('/N', (Quote $Config.User)) }
    if ($Config.Password) { $all += @('/P', (Quote $Config.Password)) }
    $all += $Arguments
    $all += @('/Out', (Quote $log))

    $p = Start-Process -FilePath $Config.V8 -ArgumentList $all -Wait -PassThru -NoNewWindow
    $text = ''
    if (Test-Path $log) { $text = Get-Content $log -Raw -Encoding UTF8 }

    if ($text -match 'Error locking infobase|Ошибка блокировки информационной базы|already be in use|уже используется') {
        Write-Host ''
        Write-Host 'База занята: открыт Конфигуратор или 1С:Предприятие на этой базе.' -ForegroundColor Red
        Write-Host "Закрой их и запусти скрипт снова. База: $($Config.IbPath)" -ForegroundColor Red
        exit 2
    }
    [pscustomobject]@{ ExitCode = $p.ExitCode; Log = $text; LogPath = $log }
}

function Quote([string]$s) { '"' + $s + '"' }

function Assert-Infobase($Config) {
    if (-not (Test-Path (Join-Path $Config.IbPath '1Cv8.1CD'))) {
        Write-Host "Не найдена база: $($Config.IbPath)" -ForegroundColor Red
        Write-Host 'Создай ее: .\scripts\new-ib.ps1  или укажи путь в stand.local.json (поле "ib").' -ForegroundColor Red
        exit 2
    }
}

function Write-Step([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
