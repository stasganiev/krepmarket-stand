<#
.SYNOPSIS
  Публикует эталон чекпоинта: отправляет тег etalon-kN в публичный репозиторий после дедлайна.
.DESCRIPTION
  Для автора курса. Ветка etalon в публичный репозиторий не уходит никогда; тег etalon-kN
  уходит вместе с историей коммитов до него - это и есть эталон чекпоинта.
  Скрипт проверяет: тег существует, дедлайн прошел, в истории нет данных проекта
  (fixtures/letters, fixtures/analysis). Затем обновляет резервную копию и отправляет тег.
.EXAMPLE
  .\tools\publish-etalon.ps1 k1
#>
param(
    [Parameter(Mandatory)] [ValidateSet('k1', 'k2', 'k3', 'k4', 'k5', 'k6')] [string]$Checkpoint,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tag = "etalon-$Checkpoint"

# Дедлайны Потока 3 (course_structure_v2.md, раздел 6), время МСК
$deadlines = @{
    k1 = '2026-12-13 23:59'; k2 = '2026-12-20 23:59'; k3 = '2026-12-27 23:59'
    k4 = '2027-01-03 23:59'; k5 = '2027-01-10 23:59'; k6 = '2027-01-15 18:00'
}

git -C $repo rev-parse -q --verify "refs/tags/$tag" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Тега $tag нет. Поставь его на нужный коммит ветки etalon: git tag $tag <коммит>" -ForegroundColor Red
    exit 2
}

$deadline = [datetime]::ParseExact($deadlines[$Checkpoint], 'yyyy-MM-dd HH:mm', $null)
$nowMsk = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([datetime]::UtcNow, 'Russian Standard Time')
if ($nowMsk -lt $deadline -and -not $Force) {
    Write-Host "Дедлайн $($Checkpoint.ToUpper()) - $($deadlines[$Checkpoint]) МСК, сейчас $($nowMsk.ToString('yyyy-MM-dd HH:mm')). Рано публиковать эталон." -ForegroundColor Red
    Write-Host 'Если точно нужно раньше - добавь -Force.' -ForegroundColor Yellow
    exit 2
}

$leaked = git -C $repo log --format= --name-only $tag -- fixtures/letters fixtures/analysis | Select-Object -First 1
if ($leaked) {
    Write-Host "В истории $tag есть данные проекта П-1 ($leaked). Публиковать нельзя - убери их из коммитов эталона." -ForegroundColor Red
    exit 2
}

# Резервная копия перед публикацией
$backup = git -C $repo config km.etalonBackup
if ($backup) {
    $tags = @(git -C $repo tag -l 'lesson-*' 'etalon-*')
    git -C $repo bundle create (Join-Path $backup 'etalon.bundle') etalon @tags '^main' 2>$null | Out-Null
}

Write-Host "Публикую $tag ($(git -C $repo log -1 --format='%h %s' $tag))" -ForegroundColor Cyan
$env:KM_PUBLISH = '1'
try { git -C $repo push origin "refs/tags/${tag}:refs/tags/$tag" } finally { Remove-Item Env:KM_PUBLISH }
if ($LASTEXITCODE -ne 0) { exit 2 }

Write-Host ''
Write-Host 'Готово. Текст для участников:' -ForegroundColor Green
Write-Host "  git fetch --tags"
Write-Host "  git diff start $tag --stat                 # что изменилось от старта до эталона"
Write-Host "  git worktree add ..\krepmarket-$tag $tag   # эталон отдельной папкой рядом со своей работой"
exit 0
