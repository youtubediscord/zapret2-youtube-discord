# ===== ОБХОД ПОЛИТИКИ ВЫПОЛНЕНИЯ =====
# Если скрипт запущен напрямую без -ExecutionPolicy Bypass, перезапуск с обходом
if ($MyInvocation.Line -notmatch 'Bypass' -and $ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage') {
    $currentPolicy = Get-ExecutionPolicy -Scope Process
    if ($currentPolicy -eq 'Restricted' -or $currentPolicy -eq 'AllSigned') {
        $scriptPath = $MyInvocation.MyCommand.Path
        if ($scriptPath) {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
            exit
        }
    }
}

$ErrorActionPreference = "Continue"
$hasErrors = $false

$rootDir = Split-Path $PSScriptRoot
$presetsDir = Join-Path $rootDir "presets"
$utilsDir = Join-Path $rootDir "utils"
$resultsDir = Join-Path $utilsDir "test-results"
$winws2Exe = Join-Path $rootDir "exe\winws2.exe"

if (-not (Test-Path $resultsDir)) { New-Item -ItemType Directory -Path $resultsDir | Out-Null }

# ===== ФУНКЦИИ =====

function Convert-Target {
    param([string]$Name, [string]$Value)
    if ($Value -like "PING:*") {
        $ping = $Value -replace '^PING:\s*', ''
        return (New-Object PSObject -Property @{ Name = $Name; Url = $null; PingTarget = $ping })
    } else {
        $host_ = $Value -replace "^https?://", "" -replace "/.*$", ""
        return (New-Object PSObject -Property @{ Name = $Name; Url = $Value; PingTarget = $host_ })
    }
}

function Stop-Winws2 {
    Get-Process -Name "winws2" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

function Start-Winws2 {
    param([string]$PresetPath)
    # Используем System.Diagnostics.Process напрямую вместо Start-Process
    # для обхода ошибки "The operation was canceled by the user"
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $winws2Exe
        $psi.Arguments = "@`"$PresetPath`""
        $psi.WorkingDirectory = $rootDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        Write-Host "  [!] Ошибка запуска через Process: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  [!] Пробую альтернативный метод..." -ForegroundColor Yellow
        try {
            # Fallback: cmd /c start
            $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"cd /d `"$rootDir`" && start /min `"`" `"$winws2Exe`" @`"$PresetPath`"`"" -PassThru -WindowStyle Hidden
        } catch {
            Write-Host "  [X] Не удалось запустить winws2: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    Start-Sleep -Seconds 4
    return $proc
}

function Test-Targets {
    param([array]$TargetList, [int]$TimeoutSec = 5, [int]$MaxParallel = 8)

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxParallel)
    $runspacePool.Open()

    $scriptBlock = {
        param($t, $timeout)
        $results = @()

        if ($t.Url) {
            $tests = @(
                @{ Label = "HTTP";   Args = @("--http1.1") },
                @{ Label = "TLS1.2"; Args = @("--tlsv1.2", "--tls-max", "1.2") },
                @{ Label = "TLS1.3"; Args = @("--tlsv1.3", "--tls-max", "1.3") }
            )

            $baseArgs = @("-I", "-s", "-m", $timeout, "-o", "NUL", "-w", "%{http_code}", "--show-error")
            foreach ($test in $tests) {
                try {
                    $curlArgs = $baseArgs + $test.Args
                    $stderr = $null
                    $output = & curl.exe @curlArgs $t.Url 2>&1 | ForEach-Object {
                        if ($_ -is [System.Management.Automation.ErrorRecord]) {
                            $stderr += $_.Exception.Message + " "
                        } else { $_ }
                    }
                    $httpCode = ($output | Out-String).Trim()
                    $exit = $LASTEXITCODE

                    $unsupported = (($exit -eq 35) -or ($stderr -match "not supported|unsupported protocol|schannel"))
                    if ($unsupported) {
                        $results += "$($test.Label):UNSUP"
                        continue
                    }
                    $sslErr = ($stderr -match "certificate|SSL|self.?signed")
                    if ($sslErr) {
                        $results += "$($test.Label):SSL  "
                        continue
                    }
                    if ($exit -eq 0) {
                        $results += "$($test.Label):OK   "
                    } else {
                        $results += "$($test.Label):FAIL "
                    }
                } catch {
                    $results += "$($test.Label):ERR  "
                }
            }
        }

        $pingResult = "n/a"
        if ($t.PingTarget) {
            try {
                $pings = Test-Connection -ComputerName $t.PingTarget -Count 2 -ErrorAction Stop
                $avg = ($pings | Measure-Object -Property ResponseTime -Average).Average
                $pingResult = "{0:N0}ms" -f $avg
            } catch {
                $pingResult = "Timeout"
            }
        }

        return (New-Object PSObject -Property @{
            Name = $t.Name; HttpTokens = $results; PingResult = $pingResult; IsUrl = [bool]$t.Url
        })
    }

    $runspaces = @()
    foreach ($target in $TargetList) {
        $ps = [powershell]::Create().AddScript($scriptBlock)
        [void]$ps.AddArgument($target)
        [void]$ps.AddArgument($TimeoutSec)
        $ps.RunspacePool = $runspacePool
        $runspaces += [PSCustomObject]@{ Powershell = $ps; Handle = $ps.BeginInvoke() }
    }

    $results = @()
    foreach ($rs in $runspaces) {
        try {
            $waitMs = ($TimeoutSec + 8) * 1000
            if ($rs.Handle -and $rs.Handle.AsyncWaitHandle) {
                [void]$rs.Handle.AsyncWaitHandle.WaitOne($waitMs)
            }
            $results += $rs.Powershell.EndInvoke($rs.Handle)
        } catch {
            $results += [PSCustomObject]@{ Name = 'UNKNOWN'; HttpTokens = @('ERR'); PingResult = 'Timeout'; IsUrl = $true }
        }
        $rs.Powershell.Dispose()
    }

    $runspacePool.Close()
    $runspacePool.Dispose()
    return $results
}

# ===== ПРОВЕРКИ =====

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Запустите от имени администратора" -ForegroundColor Red
    $hasErrors = $true
} else {
    Write-Host "[OK] Права администратора" -ForegroundColor Green
}

if (-not (Get-Command "curl.exe" -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] curl.exe не найден в PATH" -ForegroundColor Red
    $hasErrors = $true
} else {
    Write-Host "[OK] curl.exe найден" -ForegroundColor Green
}

if (-not (Test-Path $winws2Exe)) {
    Write-Host "[ERROR] winws2.exe не найден: $winws2Exe" -ForegroundColor Red
    $hasErrors = $true
} else {
    Write-Host "[OK] winws2.exe найден" -ForegroundColor Green
}

# Проверка конфликтов с сервисом
if (Get-Service -Name "zapret2" -ErrorAction SilentlyContinue) {
    $svc = Get-Service -Name "zapret2"
    if ($svc.Status -eq "Running") {
        Write-Host "[ERROR] Сервис 'zapret2' запущен. Удалите через service.bat (пункт 3)" -ForegroundColor Red
        $hasErrors = $true
    }
}

if ($hasErrors) {
    Write-Host "`nИсправьте ошибки и перезапустите." -ForegroundColor Yellow
    Write-Host "Нажмите любую клавишу..." -ForegroundColor Yellow
    [void][System.Console]::ReadKey($true)
    exit 1
}

# ===== ЗАГРУЗКА ЦЕЛЕЙ =====

$targetList = @()
$targetsFile = Join-Path $utilsDir "targets.txt"
$rawTargets = New-Object System.Collections.Specialized.OrderedDictionary

if (Test-Path $targetsFile) {
    Get-Content $targetsFile | ForEach-Object {
        if ($_ -match '^\s*(\w+)\s*=\s*"(.+)"\s*$') {
            if (-not $rawTargets.Contains($matches[1])) {
                $rawTargets.Add($matches[1], $matches[2])
            }
        }
    }
}

if ($rawTargets.Count -eq 0) {
    Write-Host "[INFO] targets.txt пуст, используются значения по умолчанию" -ForegroundColor Gray
    $rawTargets.Add("Discord", "https://discord.com")
    $rawTargets.Add("YouTube", "https://www.youtube.com")
    $rawTargets.Add("Google", "https://www.google.com")
    $rawTargets.Add("Cloudflare", "https://www.cloudflare.com")
    $rawTargets.Add("DNS_1111", "PING:1.1.1.1")
} else {
    Write-Host "[INFO] Загружено целей: $($rawTargets.Count)" -ForegroundColor Gray
}

foreach ($key in $rawTargets.Keys) {
    $targetList += Convert-Target -Name $key -Value $rawTargets[$key]
}

$maxNameLen = ($targetList | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
if (-not $maxNameLen -or $maxNameLen -lt 10) { $maxNameLen = 10 }

# ===== СБОР ПРЕСЕТОВ =====

$presetFiles = Get-ChildItem -Path $presetsDir -Filter "*.txt" | Where-Object { $_.Name -notlike "_*" } | Sort-Object { [Regex]::Replace($_.Name, '(\d+)', { $args[0].Value.PadLeft(8, '0') }) }

if ($presetFiles.Count -eq 0) {
    Write-Host "[ERROR] Пресеты не найдены в $presetsDir" -ForegroundColor Red
    [void][System.Console]::ReadKey($true)
    exit 1
}

# ===== ВЫБОР РЕЖИМА =====

Write-Host ""
Write-Host "Режим тестирования:" -ForegroundColor Cyan
Write-Host "  [1] Все пресеты ($($presetFiles.Count) шт.)" -ForegroundColor Gray
Write-Host "  [2] Выбрать конкретные" -ForegroundColor Gray
$modeChoice = Read-Host "Выбор (1/2)"

if ($modeChoice -eq '2') {
    Write-Host ""
    Write-Host "Доступные пресеты:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $presetFiles.Count; $i++) {
        Write-Host "  [$($i+1)] $($presetFiles[$i].BaseName)" -ForegroundColor Gray
    }
    $sel = Read-Host "Номера через запятую или диапазон (напр. 1,3,5-8). 0 = все"
    $sel = $sel.Trim()

    if ($sel -ne '0' -and $sel -ne '') {
        $indices = @()
        foreach ($part in ($sel -split '[,\s]+')) {
            if ($part -match '^(\d+)-(\d+)$') {
                $s = [int]$matches[1]; $e = [int]$matches[2]
                for ($j = $s; $j -le $e; $j++) { $indices += $j }
            } elseif ($part -match '^\d+$') {
                $indices += [int]$part
            }
        }
        $valid = $indices | Sort-Object -Unique | Where-Object { $_ -ge 1 -and $_ -le $presetFiles.Count }
        if ($valid.Count -gt 0) {
            $presetFiles = @($valid | ForEach-Object { $presetFiles[$_ - 1] })
        }
    }
}

# ===== ЗАПУСК ТЕСТОВ =====

$globalResults = @()
$savedWinws = $null
try {
    $savedWinws = Get-CimInstance Win32_Process -Filter "Name='winws2.exe'" -ErrorAction SilentlyContinue |
        Select-Object ProcessId, CommandLine, ExecutablePath
} catch {}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "         ТЕСТИРОВАНИЕ ПРЕСЕТОВ ZAPRET2" -ForegroundColor Cyan
Write-Host "         Пресетов: $($presetFiles.Count)  |  Целей: $($targetList.Count)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "[!] Тесты могут занять несколько минут. Ждите..." -ForegroundColor Yellow

try {
    $presetNum = 0
    foreach ($preset in $presetFiles) {
        $presetNum++
        Write-Host ""
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host "  [$presetNum/$($presetFiles.Count)] $($preset.BaseName)" -ForegroundColor Yellow
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan

        Stop-Winws2
        Start-Sleep -Milliseconds 500

        Write-Host "  > Запуск winws2..." -ForegroundColor DarkGray
        $proc = Start-Winws2 -PresetPath $preset.FullName

        # Проверка что запустился
        $running = Get-Process -Name "winws2" -ErrorAction SilentlyContinue
        if (-not $running) {
            Write-Host "  [X] winws2 не удалось запустить с этим пресетом" -ForegroundColor Red
            $globalResults += @{ Preset = $preset.BaseName; Results = @(); Failed = $true }
            continue
        }

        Write-Host "  > Тестирование целей..." -ForegroundColor DarkGray
        $testResults = Test-Targets -TargetList $targetList

        # Вывод результатов
        $lookup = @{}
        foreach ($res in $testResults) { $lookup[$res.Name] = $res }

        foreach ($target in $targetList) {
            $res = $lookup[$target.Name]
            if (-not $res) { continue }

            Write-Host "  $($target.Name.PadRight($maxNameLen))  " -NoNewline

            if ($res.IsUrl -and $res.HttpTokens) {
                foreach ($tok in $res.HttpTokens) {
                    $color = "Green"
                    if ($tok -match "UNSUP") { $color = "Yellow" }
                    elseif ($tok -match "SSL|FAIL|ERR") { $color = "Red" }
                    Write-Host " $tok" -NoNewline -ForegroundColor $color
                }
                Write-Host " | " -NoNewline -ForegroundColor DarkGray
            }

            $pingColor = if ($res.PingResult -eq "Timeout") { "Red" } else { "Cyan" }
            Write-Host "Ping: $($res.PingResult)" -ForegroundColor $pingColor
        }

        $globalResults += @{ Preset = $preset.BaseName; Results = $testResults; Failed = $false }

        Stop-Winws2
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }

    # ===== АНАЛИТИКА =====

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                      РЕЗУЛЬТАТЫ" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $analytics = @{}
    foreach ($res in $globalResults) {
        $name = $res.Preset
        $analytics[$name] = @{ OK = 0; FAIL = 0; UNSUP = 0; PingOK = 0; PingFail = 0; LaunchFail = $res.Failed }

        foreach ($tr in $res.Results) {
            if ($tr.IsUrl) {
                foreach ($tok in $tr.HttpTokens) {
                    if ($tok -match "OK") { $analytics[$name].OK++ }
                    elseif ($tok -match "UNSUP") { $analytics[$name].UNSUP++ }
                    else { $analytics[$name].FAIL++ }
                }
            }
            if ($tr.PingResult -ne "Timeout" -and $tr.PingResult -ne "n/a") {
                $analytics[$name].PingOK++
            } else {
                $analytics[$name].PingFail++
            }
        }
    }

    foreach ($name in $analytics.Keys) {
        $a = $analytics[$name]
        if ($a.LaunchFail) {
            Write-Host "  $name : " -NoNewline
            Write-Host "НЕ ЗАПУСТИЛСЯ" -ForegroundColor Red
        } else {
            $score = $a.OK
            $color = if ($score -gt 0) { "Green" } else { "Red" }
            Write-Host "  $name : " -NoNewline
            Write-Host "OK=$($a.OK) FAIL=$($a.FAIL) UNSUP=$($a.UNSUP) Ping=$($a.PingOK)/$($a.PingOK + $a.PingFail)" -ForegroundColor $color
        }
    }

    # Лучший пресет
    $bestPreset = $null
    $maxScore = 0
    foreach ($name in $analytics.Keys) {
        $a = $analytics[$name]
        if ($a.LaunchFail) { continue }
        $score = $a.OK * 10 + $a.PingOK
        if ($score -gt $maxScore) {
            $maxScore = $score
            $bestPreset = $name
        }
    }

    if ($bestPreset) {
        Write-Host ""
        Write-Host "  Лучший пресет: $bestPreset" -ForegroundColor Green
    }

    # Сохранение результатов
    $dateStr = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $resultFile = Join-Path $resultsDir "test_$dateStr.txt"
    $lines = @("Zapret2 Preset Test - $dateStr", "=" * 60, "")

    foreach ($res in $globalResults) {
        $lines += "Пресет: $($res.Preset)"
        if ($res.Failed) {
            $lines += "  РЕЗУЛЬТАТ: НЕ ЗАПУСТИЛСЯ"
        } else {
            foreach ($tr in $res.Results) {
                $http = ($tr.HttpTokens -join ' ').Trim()
                $lines += "  $($tr.Name): $http | Ping: $($tr.PingResult)"
            }
        }
        $lines += ""
    }

    $lines += "=== АНАЛИТИКА ==="
    foreach ($name in $analytics.Keys) {
        $a = $analytics[$name]
        if ($a.LaunchFail) {
            $lines += "$name : НЕ ЗАПУСТИЛСЯ"
        } else {
            $lines += "$name : OK=$($a.OK) FAIL=$($a.FAIL) UNSUP=$($a.UNSUP) Ping=$($a.PingOK)/$($a.PingOK + $a.PingFail)"
        }
    }
    if ($bestPreset) { $lines += "`nЛучший пресет: $bestPreset" }

    $lines | Out-File -FilePath $resultFile -Encoding UTF8
    Write-Host ""
    Write-Host "  Результаты сохранены: $resultFile" -ForegroundColor Green

} finally {
    Stop-Winws2

    # Восстановить ранее запущенные winws2
    if ($savedWinws -and $savedWinws.Count -gt 0) {
        Write-Host "[INFO] Восстанавливаю ранее запущенные winws2..." -ForegroundColor DarkGray
        foreach ($p in $savedWinws) {
            if (-not $p.ExecutablePath) { continue }
            $exe = $p.ExecutablePath
            $args_ = ""
            if ($p.CommandLine) {
                $quoted = '"' + $exe + '"'
                if ($p.CommandLine.StartsWith($quoted)) {
                    $args_ = $p.CommandLine.Substring($quoted.Length).Trim()
                } elseif ($p.CommandLine.StartsWith($exe)) {
                    $args_ = $p.CommandLine.Substring($exe.Length).Trim()
                }
            }
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $exe
                $psi.Arguments = $args_
                $psi.WorkingDirectory = (Split-Path $exe -Parent)
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                [System.Diagnostics.Process]::Start($psi) | Out-Null
            } catch {
                # Fallback
                Start-Process -FilePath $exe -ArgumentList $args_ -WorkingDirectory (Split-Path $exe -Parent) -WindowStyle Minimized -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
}

Write-Host ""
Write-Host "Нажмите любую клавишу..." -ForegroundColor Yellow
[void][System.Console]::ReadKey($true)
