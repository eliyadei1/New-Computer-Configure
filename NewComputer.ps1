# ==========================================
# 0. AUTO-ELEVATE TO ADMINISTRATOR
# ==========================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ==========================================
# INITIALIZATION & STATE CHECK
# ==========================================
$FlagFile = "C:\IT_Setup_Phase2_Flag.txt"
$CurrentScript = $PSCommandPath

if (-not (Test-Path $FlagFile)) {
    
    Write-Host "=== PHASE 1: SYSTEM SETUP & INSTALLATIONS ===" -ForegroundColor Cyan

    # 1. Power Plan Configuration
    Write-Host "Configuring Power Plan (Screen and Sleep settings)..." -ForegroundColor Cyan
    powercfg /change standby-timeout-ac 0    
    powercfg /change monitor-timeout-ac 15   
    powercfg /change standby-timeout-dc 30   
    powercfg /change monitor-timeout-dc 15   

    # 2. Timezone and Language
    Write-Host "Setting Timezone to Israel..." -ForegroundColor Cyan
    Set-TimeZone -Id "Israel Standard Time"

    Write-Host "Configuring Languages (Hebrew, en-IL locale)..." -ForegroundColor Cyan
    $LangList = New-WinUserLanguageList "en-US"
    $LangList.Add("he-IL")
    Set-WinUserLanguageList $LangList -Force
    Set-Culture "en-IL"
    Set-WinSystemLocale "en-IL"
    Set-WinHomeLocation -GeoId 117

    # 3. Universal Tweaks (Context Menu, Privacy, Taskbar Declutter)
    Write-Host "Applying Universal System Tweaks..." -ForegroundColor Cyan
    # Restore Windows 10 Classic Context Menu
    $ContextMenuPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if (-not (Test-Path $ContextMenuPath)) { New-Item -Path $ContextMenuPath -Force | Out-Null }
    Set-ItemProperty -Path $ContextMenuPath -Name "(Default)" -Value ""
    
    # Disable Telemetry / Data Collection
    $TelemetryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (-not (Test-Path $TelemetryPath)) { New-Item -Path $TelemetryPath -Force | Out-Null }
    Set-ItemProperty -Path $TelemetryPath -Name "AllowTelemetry" -Value 0 -Type DWord
    
    # Remove Chat and Widgets from Taskbar
    $TaskbarPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $TaskbarPath -Name "TaskbarMn" -Value 0 -Type DWord -Force # Chat
    Set-ItemProperty -Path $TaskbarPath -Name "TaskbarDa" -Value 0 -Type DWord -Force # Widgets

    # 4. Remove Pre-installed Office & OneNote (Bloatware)
    Write-Host "Removing pre-installed Office apps and OneNote..." -ForegroundColor Cyan
    $AppxToRemove = @("*MicrosoftOfficeHub*", "*OneNote*", "*Office.Desktop*")
    foreach ($App in $AppxToRemove) {
        Get-AppxPackage -Name $App -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $App } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }

    # 5. OFFLINE MODE CHECK & INSTALLATIONS
    Write-Host "Checking internet connection..." -ForegroundColor Cyan
    $IsOnline = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue
    
    if (-not $IsOnline) {
        Write-Host "OFFLINE MODE DETECTED: No internet connection." -ForegroundColor Yellow
        Write-Host "Skipping software downloads (Chrome, Adobe, Office, VPN). Local tweaks applied successfully." -ForegroundColor Yellow
    }
    else {
        # Prompt for VPN if online
        $InstallVPN = Read-Host "Do you want to install Fortinet FortiClient VPN? (Y/N)"
        
        $AppsToInstall = @(
            "Google.Chrome",
            "Adobe.Acrobat.Reader.64-bit",
            "Microsoft.Office"
        )
        if ($InstallVPN -match "^[Yy]$") {
            $AppsToInstall += "Fortinet.FortiClientVPN"
        }

        Write-Host "Starting parallel background installations via Winget..." -ForegroundColor Cyan
        $Jobs = @()
        foreach ($AppId in $AppsToInstall) {
            $Jobs += Start-Job -ScriptBlock {
                param($id)
                winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
            } -ArgumentList $AppId
            Start-Sleep -Seconds 2 # Short delay to prevent simultaneous database locking
        }
        
        Write-Host "Waiting for installations to complete (this may take a while)..." -ForegroundColor Cyan
        Wait-Job -Job $Jobs | Out-Null
        Receive-Job -Job $Jobs | Out-Null
        Remove-Job -Job $Jobs
        Write-Host "All installations finished." -ForegroundColor Green

        # Create Desktop Shortcuts for Office
        Write-Host "Creating Office Desktop Shortcuts..." -ForegroundColor Cyan
        $WshShell = New-Object -ComObject WScript.Shell
        $DesktopPath = [Environment]::GetFolderPath('Desktop')
        $OfficePath = "C:\Program Files\Microsoft Office\root\Office16"
        $OfficeApps = @(
            @{ Name = "Word"; Exe = "WINWORD.EXE" },
            @{ Name = "Excel"; Exe = "EXCEL.EXE" },
            @{ Name = "PowerPoint"; Exe = "POWERPNT.EXE" },
            @{ Name = "Outlook"; Exe = "OUTLOOK.EXE" }
        )
        foreach ($App in $OfficeApps) {
            $TargetPath = Join-Path $OfficePath $App.Exe
            if (Test-Path $TargetPath) {
                $Shortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "$($App.Name).lnk"))
                $Shortcut.TargetPath = $TargetPath
                $Shortcut.Save()
            }
        }
    }

    # 6. Rename Computer
    Write-Host ""
    $NewName = Read-Host "Enter the new COMPUTER NAME (Leave blank to skip)"
    if (-not [string]::IsNullOrWhiteSpace($NewName)) {
        Rename-Computer -NewName $NewName
        Write-Host "Computer renamed successfully." -ForegroundColor Green
    }

    # 7. Prepare RunOnce for Phase 2
    Write-Host "Configuring script to resume automatically after reboot..." -ForegroundColor Cyan
    $RunOnceCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$CurrentScript`""
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -Name "ITSetupPhase2" -Value $RunOnceCommand

    # Create flag file for Phase 2 and Restart
    New-Item -Path $FlagFile -ItemType File -Force | Out-Null
    Write-Host "Phase 1 Complete! Restarting computer in 10 seconds..." -ForegroundColor Red
    Start-Sleep -Seconds 10
    Restart-Computer
}
else {
    
    Write-Host "=== PHASE 2: DOMAIN PREPARATION & JOIN ===" -ForegroundColor Cyan
    
    # Force Time Sync before Domain Join to prevent Kerberos auth errors
    Write-Host "Forcing Time Synchronization with internet servers..." -ForegroundColor Cyan
    Start-Service -Name W32Time -ErrorAction SilentlyContinue
    w32tm /resync /force | Out-Null
    
    # Prompt user for Domain Join type
    Write-Host ""
    Write-Host "Do you want to join a domain?"
    Write-Host "1 - Entra ID (Azure AD)"
    Write-Host "2 - Local Active Directory"
    Write-Host "3 - Skip"
    $Choice = Read-Host "Select an option (1, 2, or 3)"

    switch ($Choice) {
        '1' {
            Write-Host "Opening 'Access work or school' settings..." -ForegroundColor Cyan
            Start-Process "ms-settings:workplace"
        }
        '2' {
            Write-Host "Opening 'System Properties' for Local Domain Join..." -ForegroundColor Cyan
            Start-Process "sysdm.cpl"
        }
        '3' {
            Write-Host "Skipping domain join." -ForegroundColor Yellow
        }
        default {
            Write-Host "Invalid choice. Skipping domain join." -ForegroundColor Yellow
        }
    }

    # Cleanup
    Remove-Item -Path $FlagFile -Force
    if (Test-Path "C:\Setup.ps1") {
        Remove-Item -Path "C:\Setup.ps1" -Force
    }

    Write-Host "Setup is completely finished! You can close this window." -ForegroundColor Green
    Start-Sleep -Seconds 10
}
