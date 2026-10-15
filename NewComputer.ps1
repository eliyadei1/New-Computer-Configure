#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Resume)

# Dot-source to load functions for tests; system changes occur only in Invoke-Setup.
function Read-Choice {
    param([string]$Prompt, [string[]]$Allowed, [string]$Default)
    while ($true) {
        $answer = (Read-Host "$Prompt [$Default]").Trim()
        if (-not $answer) { $answer = $Default }
        if ($Allowed -contains $answer) { return $answer.ToUpperInvariant() }
        Write-Host "Choose one of: $($Allowed -join ', ')" -ForegroundColor Yellow
    }
}

function Test-ComputerName {
    param([string]$Name)
    # Conservative Windows/NetBIOS-compatible names, including domain workstations.
    return ($Name.Length -le 15 -and $Name -match '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$' -and $Name -match '[A-Za-z]')
}

function Get-SetupPlan {
    Write-Host "`nNEW COMPUTER SETUP" -ForegroundColor Cyan
    Write-Host 'Changes to language, taskbar and shortcuts apply to the account running setup.'
    Write-Host 'Use the intended account with administrator rights. No passwords are saved.'
    $language = Read-Choice 'Display language: 1 Hebrew, 2 English (Israel)' @('1', '2') '2'
    do {
        $name = (Read-Host 'Computer name (blank keeps the current name)').Trim()
        $valid = (-not $name) -or (Test-ComputerName $name)
        if (-not $valid) { Write-Host 'Use 1-15 letters, digits or internal hyphens, with at least one letter.' -ForegroundColor Yellow }
    } until ($valid)
    $apps = @()
    foreach ($app in @('Google.Chrome', 'Adobe.Acrobat.Reader.64-bit', 'Microsoft.Office')) {
        if ((Read-Choice "Install $app? Y/N" @('Y', 'N') 'Y') -eq 'Y') { $apps += $app }
    }
    if ((Read-Choice 'Install Fortinet.FortiClientVPN? Y/N' @('Y', 'N') 'N') -eq 'Y') { $apps += 'Fortinet.FortiClientVPN' }
    $join = Read-Choice 'Organization: 1 Entra ID, 2 local Active Directory, 3 skip' @('1', '2', '3') '3'
    $classic = $false
    $taskbar = $false
    $officeHub = $false
    if ((Read-Choice 'Show advanced options? Y/N' @('Y', 'N') 'N') -eq 'Y') {
        $classic = (Read-Choice 'Request classic right-click menu? Y/N' @('Y', 'N') 'N') -eq 'Y'
        $taskbar = (Read-Choice 'Hide taskbar Chat and Widgets? Y/N' @('Y', 'N') 'N') -eq 'Y'
        $officeHub = (Read-Choice 'Remove MicrosoftOfficeHub for this user only? Y/N' @('Y', 'N') 'N') -eq 'Y'
    }
    return [pscustomobject]@{
        Language = @{'1' = 'he-IL'; '2' = 'en-US'}[$language]
        ComputerName = $name; Apps = @($apps); Join = $join
        ClassicMenu = $classic; HideTaskbar = $taskbar; RemoveOfficeHub = $officeHub
    }
}

function Show-SetupPlan {
    param($Plan)
    Write-Host "`nPlanned changes" -ForegroundColor Cyan
    Write-Host 'Power: AC sleep never / screen 15 min; battery sleep 30 min / screen 15 min.'
    Write-Host "Region: Israel; display language: $($Plan.Language); keyboards: Hebrew + English."
    Write-Host "Computer name: $($Plan.ComputerName) (blank = unchanged)"
    Write-Host "Applications: $($Plan.Apps -join ', ')"
    Write-Host "Organization choice: $($Plan.Join) (1 Entra ID, 2 AD, 3 skip)"
    Write-Host "Classic menu: $($Plan.ClassicMenu); hide Chat/Widgets: $($Plan.HideTaskbar); remove OfficeHub: $($Plan.RemoveOfficeHub)"
    Write-Host 'Installing apps accepts their package/source agreements. Office licensing is separate.'
    Write-Host 'Restart is offered explicitly. Organization enrollment remains a guided manual step.'
}

function Save-SetupState {
    # Replace atomically so interrupted writes do not destroy the previous checkpoint.
    $temporary = "$script:StatePath.tmp"
    $script:State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8 -ErrorAction Stop
    if (Test-Path -LiteralPath $script:StatePath) {
        [IO.File]::Replace($temporary, $script:StatePath, "$script:StatePath.bak")
    } else {
        [IO.File]::Move($temporary, $script:StatePath)
    }
}

function Read-SetupState {
    param([string]$Path)
    $loaded = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($loaded.Version -ne 1) { throw 'Unsupported setup state. Preserve the state/logs and resolve it before continuing.' }
    $steps = @{}
    foreach ($property in $loaded.Steps.PSObject.Properties) { $steps[$property.Name] = $property.Value }
    return @{
        Version = 1; UserSid = $loaded.UserSid; Plan = $loaded.Plan; Steps = $steps
        RebootFrom = $loaded.RebootFrom; Complete = $loaded.Complete
    }
}

function Invoke-SetupStep {
    param([string]$Id, [scriptblock]$Action)
    if ($script:State.Steps.ContainsKey($Id) -and $script:State.Steps[$Id].Status -eq 'Succeeded') { return }
    Write-Host "`n> $Id" -ForegroundColor Cyan
    # Checkpoint before the action: a crash leaves a retryable step.
    $script:State.Steps[$Id] = @{ Status = 'Running'; Detail = '' }
    Save-SetupState
    try {
        & $Action | Out-Host
        $script:State.Steps[$Id] = @{ Status = 'Succeeded'; Detail = '' }
    } catch {
        $script:State.Steps[$Id] = @{ Status = 'Failed'; Detail = $_.Exception.Message }
        Write-Warning "$Id failed: $($_.Exception.Message)"
    }
    Save-SetupState
}

function Invoke-NativeCommand {
    param([string]$FilePath, [string[]]$Arguments)
    # Exit code must be captured in the same scope as the native invocation.
    # Windows PowerShell 5.1 can surface stderr as error records; capture it for diagnostics.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    $output | Out-Host
    return [pscustomobject]@{ ExitCode = $code; Output = ($output -join "`n") }
}

function Invoke-CheckedCommand {
    param([string]$FilePath, [string[]]$Arguments)
    $result = Invoke-NativeCommand $FilePath $Arguments
    if ($result.ExitCode -ne 0) { throw "$FilePath exited with code $($result.ExitCode). See the session log." }
}

function Install-SetupApp {
    param([string]$Id)
    $winget = Get-Command winget.exe -ErrorAction Stop
    $common = @('--id', $Id, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
    $existing = Invoke-NativeCommand $winget.Source (@('list') + $common)
    if ($existing.ExitCode -eq 0) {
        Write-Host "$Id is already installed."
        return
    }
    $installed = Invoke-NativeCommand $winget.Source (@('install') + $common + @('--silent', '--accept-package-agreements', '--no-upgrade'))
    if ($installed.ExitCode -ne 0) {
        throw "$Id installation failed (code $($installed.ExitCode)). Check network, App Installer and the session log, then rerun setup."
    }
    $verified = Invoke-NativeCommand $winget.Source (@('list') + $common)
    if ($verified.ExitCode -ne 0) { throw "$Id could not be verified after installation. Restart if requested by the installer, then retry." }
}

function Set-SetupLanguage {
    param([string]$Language)
    $installed = "HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages\$Language"
    if (-not (Test-Path -LiteralPath $installed)) {
        throw "Install the $Language display language in Settings > Time & language > Language & region, then retry."
    }
    $languages = New-WinUserLanguageList $Language
    if ($Language -eq 'he-IL') { $languages.Add('en-US') } else { $languages.Add('he-IL') }
    Set-WinUserLanguageList $languages -Force -ErrorAction Stop
    Set-WinUILanguageOverride -Language $Language -ErrorAction Stop
    $culture = if ($Language -eq 'he-IL') { 'he-IL' } else { 'en-IL' }
    Set-Culture $culture -ErrorAction Stop
    Set-WinSystemLocale 'he-IL' -ErrorAction Stop
}

function Set-SetupTweaks {
    param($Plan)
    if ($Plan.ClassicMenu) {
        $path = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
        New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        Set-Item -LiteralPath $path -Value '' -ErrorAction Stop
    }
    if ($Plan.HideTaskbar) {
        $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        foreach ($name in @('TaskbarMn', 'TaskbarDa')) {
            New-ItemProperty -Path $path -Name $name -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        }
    }
    if ($Plan.RemoveOfficeHub) {
        Get-AppxPackage -Name 'Microsoft.MicrosoftOfficeHub' -ErrorAction Stop |
            Remove-AppxPackage -ErrorAction Stop
    }
}

function New-OfficeShortcuts {
    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Select-Object -Unique
    foreach ($app in @(
        @{ Name = 'Word'; Exe = 'WINWORD.EXE' }, @{ Name = 'Excel'; Exe = 'EXCEL.EXE' },
        @{ Name = 'PowerPoint'; Exe = 'POWERPNT.EXE' }, @{ Name = 'Outlook'; Exe = 'OUTLOOK.EXE' }
    )) {
        foreach ($root in $roots) {
            $target = Join-Path $root "Microsoft Office\root\Office16\$($app.Exe)"
            if (Test-Path -LiteralPath $target) {
                $shortcut = $shell.CreateShortcut((Join-Path $desktop "$($app.Name).lnk"))
                $shortcut.TargetPath = $target
                $shortcut.Save()
                break
            }
        }
    }
}

function Test-OrganizationJoined {
    param([string]$Choice)
    if ($Choice -eq '3') { return $true }
    if ($Choice -eq '2') { return [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain }
    $result = Invoke-NativeCommand "$env:SystemRoot\System32\dsregcmd.exe" @('/status')
    if ($result.ExitCode -ne 0) { throw 'Unable to read Entra device join status.' }
    return [bool]($result.Output -match '(?m)^\s*AzureAdJoined\s*:\s*YES\s*$')
}

function Register-SetupResume {
    param([string]$ScriptPath, [string]$UserSid)
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Resume"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserSid
    $principal = New-ScheduledTaskPrincipal -UserId $UserSid -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 8)
    Register-ScheduledTask -TaskName 'NewComputerConfigure-Resume' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
}

function Show-SetupResults {
    Write-Host "`nResults" -ForegroundColor Cyan
    $script:State.Steps.GetEnumerator() | Sort-Object Name | ForEach-Object {
        Write-Host "$($_.Key): $($_.Value.Status) $($_.Value.Detail)"
    }
    Write-Host "Logs and state: $script:SetupRoot"
}

function Invoke-Setup {
    $ErrorActionPreference = 'Stop'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) {
        throw 'Run setup using 64-bit Windows PowerShell on Windows 10/11.'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # Require explicit same-account elevation; alternate credentials would target another profile.
        throw 'Open 64-bit Windows PowerShell as Administrator using the account to configure, then run this file again.'
    }
    $script:SetupRoot = Join-Path $env:ProgramData 'NewComputerConfigure'
    $script:StatePath = Join-Path $script:SetupRoot 'state.json'
    $canonicalScript = Join-Path $script:SetupRoot 'NewComputer.ps1'
    $mutex = New-Object Threading.Mutex($false, 'Global\NewComputerConfigure')
    $locked = $false
    $transcribing = $false
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Another setup session is already running.' }
        # Do not silently mix the old two-phase script with the new checkpoint format.
        if (Test-Path -LiteralPath 'C:\IT_Setup_Phase2_Flag.txt') {
            throw 'Legacy setup is pending. Finish/review that session before using this version; no legacy files were removed.'
        }
        if (Test-Path -LiteralPath $script:StatePath) {
            $script:State = Read-SetupState $script:StatePath
            if ($script:State.UserSid -ne $identity.User.Value) { throw 'Resume setup using the same account that started it.' }
        } else {
            if ($Resume) { throw 'No saved setup was found. Run without -Resume to create a plan.' }
            $plan = Get-SetupPlan
            Show-SetupPlan $plan
            if ((Read-Choice 'Apply this plan? Y/N' @('Y', 'N') 'N') -ne 'Y') { return }
            New-Item -Path $script:SetupRoot -ItemType Directory -Force | Out-Null
            # Only administrators/SYSTEM may modify code that the elevated resume task runs.
            $acl = New-Object Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
                $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                    (New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl',
                    'ContainerInherit,ObjectInherit', 'None', 'Allow')
                $acl.AddAccessRule($rule)
            }
            Set-Acl -LiteralPath $script:SetupRoot -AclObject $acl
            $script:State = @{
                Version = 1; UserSid = $identity.User.Value; Plan = $plan; Steps = @{}
                RebootFrom = $null; Complete = $false
            }
            Save-SetupState
        }
        if ($script:State.Complete) {
            Show-SetupResults
            Write-Host 'This saved setup is already complete. No changes applied.' -ForegroundColor Green
            return
        }
        if (-not [string]::Equals($PSCommandPath, $canonicalScript, [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $PSCommandPath -Destination $canonicalScript -Force
        }
        Register-SetupResume $canonicalScript $script:State.UserSid
        Write-Host "Resume manually at any time: & '$canonicalScript' -Resume"
        Start-Transcript -Path (Join-Path $script:SetupRoot ("session-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))) | Out-Null
        $transcribing = $true
        $plan = $script:State.Plan
        Invoke-SetupStep 'Power' {
            foreach ($setting in @(
                @('standby-timeout-ac', '0'), @('monitor-timeout-ac', '15'),
                @('standby-timeout-dc', '30'), @('monitor-timeout-dc', '15')
            )) { Invoke-CheckedCommand 'powercfg.exe' (@('/change') + $setting) }
        }
        Invoke-SetupStep 'Region' {
            Set-TimeZone -Id 'Israel Standard Time' -ErrorAction Stop
            Set-WinHomeLocation -GeoId 117 -ErrorAction Stop
        }
        Invoke-SetupStep 'Language' {
            Set-SetupLanguage $plan.Language
            $script:State.RebootFrom = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
        }
        Invoke-SetupStep 'Optional tweaks' { Set-SetupTweaks $plan }
        foreach ($appId in $plan.Apps) {
            # Sequential installers avoid competing MSI operations; each package gets its own checkpoint.
            Invoke-SetupStep "App: $appId" { Install-SetupApp $appId }
        }
        if ($plan.Apps -contains 'Microsoft.Office' -and $script:State.Steps['App: Microsoft.Office'].Status -eq 'Succeeded') {
            Invoke-SetupStep 'Office shortcuts' { New-OfficeShortcuts }
        }
        Invoke-SetupStep 'Computer name' {
            if ($plan.ComputerName -and $env:COMPUTERNAME -ine $plan.ComputerName) {
                Rename-Computer -NewName $plan.ComputerName -Force -ErrorAction Stop
                $script:State.RebootFrom = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
            }
        }
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
        if ($script:State.RebootFrom -eq $boot) {
            Show-SetupResults
            Write-Host 'A restart is needed before the final organization check. Save your work first.' -ForegroundColor Yellow
            if ((Read-Choice 'Restart now? Y/N' @('Y', 'N') 'N') -eq 'Y') { Restart-Computer -ErrorAction Stop }
            return
        }
        # An active name check catches canceled or unsuccessful rename operations after restart.
        if ($plan.ComputerName -and $env:COMPUTERNAME -ine $plan.ComputerName) {
            $script:State.Steps['Computer name'] = @{ Status = 'Failed'; Detail = 'Requested name is not active. Rerun to retry.' }
            Save-SetupState
        }
        Invoke-SetupStep 'Organization' {
            if (-not (Test-OrganizationJoined $plan.Join)) {
                if ($plan.Join -eq '1') { Start-Process 'ms-settings:workplace' -ErrorAction Stop }
                else { Start-Process 'sysdm.cpl' -ErrorAction Stop }
                Write-Host 'Complete the device join in the opened window. Work-account registration alone is not Entra device join.'
                Read-Host 'Press Enter to check again (or restart and resume if Windows requests it)' | Out-Null
                if (-not (Test-OrganizationJoined $plan.Join)) {
                    throw 'Device join is still pending. Complete the join/restart and rerun setup.'
                }
            }
        }
        $pending = @($script:State.Steps.Values | Where-Object { $_.Status -ne 'Succeeded' })
        if ($pending.Count -eq 0) {
            # Remove only our own task, retaining script/state/logs for review and safe repeated runs.
            Unregister-ScheduledTask -TaskName 'NewComputerConfigure-Resume' -Confirm:$false -ErrorAction Stop
            $script:State.Complete = $true
            Save-SetupState
            Write-Host "`nSelected setup tasks completed. Organization choice 3 means intentionally skipped." -ForegroundColor Green
        } else {
            Write-Warning 'Setup is incomplete. Correct the failed steps and rerun; successful steps will be skipped.'
        }
        Show-SetupResults
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-Setup } catch { Write-Error $_; exit 1 }
}
