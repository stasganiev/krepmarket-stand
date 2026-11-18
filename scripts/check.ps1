<#
.SYNOPSIS
  Загружает изменения в базу и выполняет синтакс-контроль модулей.
.DESCRIPTION
  1. Загрузка: по умолчанию только измененные модули (как load.ps1 -Changed), -Full - полная.
  2. Синтакс-контроль: тонкий клиент, сервер, внешнее соединение.
  3. Отчет: logs\check.txt - по строке на ошибку в формате
       src/cf/<путь к модулю>.bsl:<строка>:<колонка>: <текст ошибки> [<контексты>]
     под ней - строка кода, где <<?>> отмечает место ошибки.
     Сырой лог платформы - logs\check.log.
  Коды выхода: 0 - ошибок нет; 1 - есть синтаксические ошибки; 2 - сбой загрузки или запуска.
.EXAMPLE
  .\scripts\check.ps1
  .\scripts\check.ps1 -Full
#>
param(
    [switch]$Full,
    [switch]$NoLoad,
    [string]$IbPath,
    [string]$SrcPath
)
. "$PSScriptRoot\_common.ps1"

$cfg = Get-StandConfig -IbPath $IbPath -SrcPath $SrcPath
Assert-Infobase $cfg

# --- 1. Загрузка -----------------------------------------------------------
if (-not $NoLoad) {
    $loadArgs = @{ IbPath = $cfg.IbPath; SrcPath = $cfg.SrcPath }
    if (-not $Full) { $loadArgs['Changed'] = $true }
    & "$PSScriptRoot\load.ps1" @loadArgs
    if ($LASTEXITCODE -ne 0) { exit 2 }
}

# --- 2. Синтакс-контроль ---------------------------------------------------
Write-Step 'Синтакс-контроль модулей (тонкий клиент, сервер, внешнее соединение)'
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-Designer -Config $cfg -LogName 'check.log' -Arguments @(
    '/L', 'ru', '/VL', 'ru',
    '/CheckModules', '-ThinClient', '-Server', '-ExternalConnection')
$elapsed = [int]$sw.Elapsed.TotalSeconds

# --- 3. Разбор лога --------------------------------------------------------
# Строка ошибки платформы: {ОбщийМодуль.Имя.Модуль(96,95)}: Текст ошибки
# следующая строка:        <код с <<?>>> (Проверка: Сервер)
$typeFolders = @{
    'ОбщийМодуль' = 'CommonModules'; 'ОбщаяФорма' = 'CommonForms'; 'ОбщаяКоманда' = 'CommonCommands'
    'Справочник' = 'Catalogs'; 'Документ' = 'Documents'; 'Обработка' = 'DataProcessors'; 'Отчет' = 'Reports'
    'РегистрСведений' = 'InformationRegisters'; 'РегистрНакопления' = 'AccumulationRegisters'
    'РегистрБухгалтерии' = 'AccountingRegisters'; 'РегистрРасчета' = 'CalculationRegisters'
    'Перечисление' = 'Enums'; 'Константа' = 'Constants'; 'ЖурналДокументов' = 'DocumentJournals'
    'ПланВидовХарактеристик' = 'ChartsOfCharacteristicTypes'; 'ПланСчетов' = 'ChartsOfAccounts'
    'ПланВидовРасчета' = 'ChartsOfCalculationTypes'; 'ПланОбмена' = 'ExchangePlans'
    'БизнесПроцесс' = 'BusinessProcesses'; 'Задача' = 'Tasks'; 'HTTPСервис' = 'HTTPServices'
    'WebСервис' = 'WebServices'; 'ХранилищеНастроек' = 'SettingsStorages'
}
$moduleFiles = @{
    'Модуль' = 'Module.bsl'; 'МодульОбъекта' = 'ObjectModule.bsl'; 'МодульМенеджера' = 'ManagerModule.bsl'
    'МодульНабораЗаписей' = 'RecordSetModule.bsl'; 'МодульМенеджераЗначения' = 'ValueManagerModule.bsl'
    'МодульКоманды' = 'CommandModule.bsl'
}
$configModules = @{
    'МодульУправляемогоПриложения' = 'Ext\ManagedApplicationModule.bsl'; 'МодульСеанса' = 'Ext\SessionModule.bsl'
    'МодульВнешнегоСоединения' = 'Ext\ExternalConnectionModule.bsl'; 'МодульОбычногоПриложения' = 'Ext\OrdinaryApplicationModule.bsl'
}

function Convert-ToFile([string]$meta) {
    $p = $meta.Split('.')
    $rel = $null
    if ($p[0] -eq 'Конфигурация' -and $configModules.ContainsKey($p[1])) { $rel = $configModules[$p[1]] }
    elseif ($typeFolders.ContainsKey($p[0])) {
        $folder = "$($typeFolders[$p[0]])\$($p[1])"
        if ($p[0] -in 'ОбщаяФорма') { $rel = "$folder\Ext\Form\Module.bsl" }
        elseif ($p.Count -ge 4 -and $p[2] -eq 'Форма') { $rel = "$folder\Forms\$($p[3])\Ext\Form\Module.bsl" }
        elseif ($p.Count -ge 4 -and $p[2] -eq 'Команда') { $rel = "$folder\Commands\$($p[3])\Ext\CommandModule.bsl" }
        elseif ($moduleFiles.ContainsKey($p[-1])) { $rel = "$folder\Ext\$($moduleFiles[$p[-1]])" }
    }
    if ($rel -and (Test-Path -LiteralPath (Join-Path $cfg.SrcPath $rel))) {
        $repoRel = (Join-Path $cfg.SrcPath $rel).Substring($script:RepoRoot.Length).TrimStart('\')
        return $repoRel.Replace('\', '/')
    }
    return $meta   # не смогли сопоставить - оставляем имя метаданных как есть
}

$errors = [ordered]@{}
$logLines = $r.Log -split "`r?`n"
for ($i = 0; $i -lt $logLines.Count; $i++) {
    if ($logLines[$i] -match '^\{(.+)\((\d+),(\d+)\)\}:\s*(.*)$') {
        $file = Convert-ToFile $Matches[1]
        $key = "${file}:$($Matches[2]):$($Matches[3]): $($Matches[4])"
        $code = ''; $ctx = ''
        if ($i + 1 -lt $logLines.Count -and $logLines[$i + 1] -notmatch '^\{' -and $logLines[$i + 1] -match '^\s*(.*?)\s*\((?:Проверка|Verification):\s*(.+)\)\s*$') {
            $code = $Matches[1].Trim(); $ctx = $Matches[2]; $i++
        }
        if (-not $errors.Contains($key)) { $errors[$key] = @{ Code = $code; Ctx = New-Object System.Collections.ArrayList } }
        if ($ctx -and -not $errors[$key].Ctx.Contains($ctx)) { [void]$errors[$key].Ctx.Add($ctx) }
    }
}

$report = Join-Path $cfg.Logs 'check.txt'
if ($errors.Count -eq 0 -and $r.ExitCode -eq 0) {
    'OK: синтаксических ошибок не обнаружено' | Set-Content $report -Encoding UTF8
    Write-Host "Синтаксических ошибок нет ($elapsed с)." -ForegroundColor Green
    exit 0
}
if ($errors.Count -eq 0) {
    Write-Host $r.Log
    Write-Host "Синтакс-контроль завершился с кодом $($r.ExitCode), но ошибок в логе не найдено. Лог: $($r.LogPath)" -ForegroundColor Red
    exit 2
}

$out = foreach ($k in $errors.Keys) {
    "$k [$($errors[$k].Ctx -join ', ')]"
    if ($errors[$k].Code) { "    $($errors[$k].Code)" }
}
$out | Set-Content $report -Encoding UTF8
$out | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host "Найдено ошибок: $($errors.Count) ($elapsed с). Отчет: logs\check.txt" -ForegroundColor Red
exit 1
