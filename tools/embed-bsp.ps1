<#
.SYNOPSIS
  Собирает «КрепМаркет v0» с нуля: пустая база + БСП по файлу настроек, без ручных шагов.
.DESCRIPTION
  Повторяет ручной маршрут внедрения БСП (документация БСП, «Быстрое начало разработки с нуля»):
    1. пустая файловая база;
    2. «Сравнить, объединить с конфигурацией из файла» по tools\bsp_merge_settings.xml;
    3. снятие с поддержки (иначе частичная загрузка модулей агентом невозможна);
    4. свойства конфигурации: имя, синоним, версия, авторские права, режим совместимости как у БСП;
    5. общий модуль ОбновлениеИнформационнойБазыКрепМаркет + регистрация в ПодсистемыКонфигурацииПереопределяемый;
    6. загрузка, обновление конфигурации БД, синтакс-контроль.
  Зачем: пересобрать стенд на новой сборке БСП (к следующему потоку) или довнедрить подсистему -
  поменяй файл настроек и запусти скрипт. Торговое ядро и все, что сверху, переносится отдельно
  (сравнение/объединение со старой конфигурацией).
  Результат - база по пути -IbPath. В src\cf скрипт не пишет: выгрузи сам через scripts\dump.ps1 -IbPath ...
.EXAMPLE
  .\tools\embed-bsp.ps1 -IbPath C:\bases\krepmarket-bsp
#>
param(
    [Parameter(Mandatory)] [string]$IbPath,
    [string]$LibraryCf,
    [string]$Settings,
    [string]$Version = '1.0.1.1',
    [string]$CompatibilityMode = 'Version8_3_24',
    [switch]$Force
)
. "$PSScriptRoot\..\scripts\_common.ps1"

$cfg = Get-StandConfig -IbPath $IbPath
if (-not $Settings) { $Settings = Join-Path $PSScriptRoot 'bsp_merge_settings.xml' }

if (-not $LibraryCf) {
    $tmpl = Join-Path $env:APPDATA '1C\1cv8\tmplts\1c\SSL'
    $LibraryCf = Get-ChildItem $tmpl -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^3_1_12_\d+$' } |
        Sort-Object { [int]($_.Name.Split('_')[-1]) } -Descending |
        ForEach-Object { Join-Path $_.FullName '1Cv8.cf' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $LibraryCf) { throw "Не найдена поставка БСП 3.1.12 в $tmpl. Укажи -LibraryCf <путь к 1Cv8.cf>." }
}
Write-Host "Библиотека: $LibraryCf"
Write-Host "Настройки:  $Settings"

# --- 1. Пустая база --------------------------------------------------------
if (Test-Path (Join-Path $IbPath '1Cv8.1CD')) {
    if (-not $Force) { Write-Host "База уже есть: $IbPath. Добавь -Force, чтобы пересоздать." -ForegroundColor Yellow; exit 2 }
    Remove-Item -Recurse -Force $IbPath
}
Write-Step "Создаю пустую базу $IbPath"
New-Item -ItemType Directory -Force $IbPath | Out-Null
$p = Start-Process -FilePath $cfg.V8 -Wait -PassThru -NoNewWindow -ArgumentList @(
    'CREATEINFOBASE', ("File=""$IbPath"";Locale=ru_RU"), '/L', 'ru', '/Out', (Quote (Join-Path $cfg.Logs 'embed-create.log')))
if ($p.ExitCode -ne 0) { Write-Host 'Не удалось создать базу.' -ForegroundColor Red; exit 2 }

function Step($name, $log, [string[]]$a) {
    Write-Step $name
    $r = Invoke-Designer -Config $cfg -LogName $log -Arguments (@('/L', 'ru', '/VL', 'ru') + $a)
    if ($r.ExitCode -ne 0) { Write-Host $r.Log; Write-Host "Шаг «$name» не удался. Лог: $($r.LogPath)" -ForegroundColor Red; exit 2 }
}

# --- 2-3. Объединение и снятие с поддержки --------------------------------
Step 'Объединяю с БСП по файлу настроек' 'embed-merge.log' @(
    '/MergeCfg', (Quote $LibraryCf), '-Settings', (Quote $Settings), '-EnableSupport', '-ClearUnresolvedRefs', '-force')
Step 'Снимаю конфигурацию с поддержки' 'embed-support.log' @('/ManageCfgSupport', '-disableSupport', '-force')

# --- 4-5. Правка выгрузки --------------------------------------------------
$work = Join-Path $cfg.Logs 'embed-src'
if (Test-Path $work) { cmd /c rd /s /q "\\?\$work" | Out-Null }
Step 'Выгружаю во временную папку' 'embed-dump.log' @('/DumpConfigToFiles', (Quote $work), '-Format', 'Hierarchical')

$utf8 = New-Object Text.UTF8Encoding($true)
function Edit-File($path, [scriptblock]$fn) {
    $t = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $n = & $fn $t
    if ($n -eq $t) { throw "Правка не применилась: $path" }
    [IO.File]::WriteAllText($path, $n, $utf8)
}
function LocalString($s) { "<v8:item><v8:lang>ru</v8:lang><v8:content>$s</v8:content></v8:item>" }

$module = 'ОбновлениеИнформационнойБазыКрепМаркет'
Write-Step 'Свойства конфигурации и модуль обновления'
Edit-File (Join-Path $work 'Configuration.xml') {
    param($t)
    $t = $t -replace '(<Properties>\s*<Name>)[^<]*(</Name>)', '${1}КрепМаркет${2}'
    $t = $t -replace '(<Properties>\s*<Name>КрепМаркет</Name>\s*)<Synonym/>', ('${1}<Synonym>' + (LocalString 'КрепМаркет') + '</Synonym>')
    $t = $t -replace '<Version/>', "<Version>$Version</Version>"
    $t = $t -replace '<Copyright/>', ('<Copyright>' + (LocalString 'Библиотека стандартных подсистем © ООО &quot;1С-Софт&quot;, лицензия CC BY 4.0') + '</Copyright>')
    $t = $t -replace '<CompatibilityMode>[^<]*</CompatibilityMode>', "<CompatibilityMode>$CompatibilityMode</CompatibilityMode>"
    $t = $t -replace '(\t*)<CommonModule>ОбновлениеИнформационнойБазыБСП</CommonModule>', ('$0' + "`r`n" + '${1}' + "<CommonModule>$module</CommonModule>")
    $t
}

$srcXml = Join-Path $work 'CommonModules\ОбновлениеИнформационнойБазыБСП.xml'
$dstXml = Join-Path $work "CommonModules\$module.xml"
$x = [IO.File]::ReadAllText($srcXml, [Text.Encoding]::UTF8)
$x = $x -replace 'CommonModule uuid="[^"]+"', "CommonModule uuid=""$([guid]::NewGuid())"""
$x = $x -replace '<Name>ОбновлениеИнформационнойБазыБСП</Name>', "<Name>$module</Name>"
$x = $x -replace 'Обновление информационной базы БСП', 'Обновление информационной базы КрепМаркет'
[IO.File]::WriteAllText($dstXml, $x, $utf8)

$bsl = @"
#Область ПрограммныйИнтерфейс

// Описание конфигурации КрепМаркет для подсистемы «Обновление версии ИБ» БСП.
Процедура ПриДобавленииПодсистемы(Описание) Экспорт
	Описание.Имя = "КрепМаркет";
	Описание.Версия = "$Version";
	// Требуется библиотека стандартных подсистем.
	Описание.ТребуемыеПодсистемы.Добавить("СтандартныеПодсистемы");
КонецПроцедуры

Процедура ПриДобавленииОбработчиковОбновления(Обработчики) Экспорт
КонецПроцедуры

Процедура ПередОбновлениемИнформационнойБазы() Экспорт
КонецПроцедуры

Процедура ПослеОбновленияИнформационнойБазы(Знач ПредыдущаяВерсия, Знач ТекущаяВерсия,
		Знач ВыполненныеОбработчики, ВыводитьОписаниеОбновлений, МонопольныйРежим) Экспорт
КонецПроцедуры

Процедура ПриПодготовкеМакетаОписанияОбновлений(Знач Макет) Экспорт
КонецПроцедуры

Процедура ПриДобавленииОбработчиковПереходаСДругойПрограммы(Обработчики) Экспорт
КонецПроцедуры

Процедура ПриОпределенииРежимаОбновленияДанных(РежимОбновленияДанных, СтандартнаяОбработка) Экспорт
КонецПроцедуры

Процедура ПриЗавершенииПереходаСДругойПрограммы(Знач ПредыдущееИмяКонфигурации, Знач ПредыдущаяВерсияКонфигурации, Параметры) Экспорт
КонецПроцедуры

#КонецОбласти
"@
$modDir = Join-Path $work "CommonModules\$module\Ext"
New-Item -ItemType Directory -Force $modDir | Out-Null
[IO.File]::WriteAllText((Join-Path $modDir 'Module.bsl'), ($bsl -replace "`r?`n", "`r`n"), $utf8)

# Макет «Что нового в версии» (требование подсистемы «Обновление версии ИБ») - берем из src\cf стенда.
$tmplName = 'ОписаниеИзмененийСистемы'
$tmplSrc = Join-Path $script:RepoRoot "src\cf\CommonTemplates"
if (Test-Path (Join-Path $tmplSrc "$tmplName.xml")) {
    Copy-Item (Join-Path $tmplSrc "$tmplName.xml") (Join-Path $work 'CommonTemplates') -Force
    Copy-Item (Join-Path $tmplSrc $tmplName) (Join-Path $work 'CommonTemplates') -Recurse -Force
    Edit-File (Join-Path $work 'Configuration.xml') {
        param($t)
        ([regex]'(\t*)(<CommonTemplate>[^<]+</CommonTemplate>)').Replace($t, ('${1}' + "<CommonTemplate>$tmplName</CommonTemplate>`r`n" + '${1}${2}'), 1)
    }
} else {
    Write-Warning "Нет src\cf\CommonTemplates\$tmplName.xml - макет не добавлен, отчет ПроверкаВнедренияБСП напомнит о нем."
}

Edit-File (Join-Path $work 'CommonModules\ПодсистемыКонфигурацииПереопределяемый\Ext\Module.bsl') {
    param($t)
    $t -replace '(Процедура ПриДобавленииПодсистем\(МодулиПодсистем\) Экспорт\r?\n)', ('${1}' + "`tМодулиПодсистем.Добавить(""$module"");`r`n")
}

# --- 6. Загрузка и проверка ------------------------------------------------
Step 'Загружаю конфигурацию и обновляю БД' 'embed-load.log' @('/LoadConfigFromFiles', (Quote $work), '/UpdateDBCfg')
& "$PSScriptRoot\..\scripts\check.ps1" -IbPath $IbPath -NoLoad
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmd /c rd /s /q "\\?\$work" | Out-Null
Write-Host ''
Write-Host "Готово: $IbPath - БСП внедрена, конфигурация КрепМаркет $Version." -ForegroundColor Green
Write-Host 'Дальше: открыть базу в 1С:Предприятии (начальное заполнение БСП) и выгрузить: .\scripts\dump.ps1 -IbPath ...'
exit 0
