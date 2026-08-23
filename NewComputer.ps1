# ==========================================
# 0. AUTO-ELEVATE TO ADMINISTRATOR
# ==========================================
# This ensures the script always runs as Admin, especially when resuming after reboot
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ==========================================
# INITIALIZATION & STATE CHECK
# ==========================================
# We use a flag file to remember if we already completed Phase 1
$FlagFile = "C:\IT_Setup_Phase2_Flag.txt"
$CurrentScript = $PSCommandPath

if (-not (Test-Path $FlagFile)) {
    
    Write-Host "=== PHASE 1: SYSTEM SETUP & INSTALLATIONS ===" -ForegroundColor Cyan

    # 1. Power Plan Configuration
    Write-Host "Configuring Power Plan: Disabling Sleep when plugged in..." -ForegroundColor Cyan
    powercfg /change standby-timeout-ac 0

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

    # 3. Remove Pre-installed Office & OneNote (Bloatware)
    Write-Host "Removing pre-installed Office apps, OneNote, and related language packs..." -ForegroundColor Cyan
    $AppxToRemove = @("*MicrosoftOfficeHub*", "*OneNote*", "*Office.Desktop*")
    
    foreach ($App in $AppxToRemove) {
        Get-AppxPackage -Name $App -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $App } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }

    # 4. Software Installation (Winget)
    Write-Host "Installing Google Chrome..." -ForegroundColor Cyan
    winget install --id Google.Chrome --exact --silent --accept-package-agreements --accept-source-agreements
    
    Write-Host "Installing Adobe Acrobat Reader..." -ForegroundColor Cyan
    winget install --id Adobe.Acrobat.Reader.64-bit --exact --silent --accept-package-agreements --accept-source-agreements
    
    Write-Host "Installing Microsoft 365 Apps..." -ForegroundColor Cyan
    winget install --id Microsoft.Office --exact --silent --accept-package-agreements --accept-source-agreements

    # 5. Create Desktop Shortcuts for Office
    Write-Host "Creating Office Desktop Shortcuts..." -ForegroundColor Cyan
    $WshShell = New-Object -ComObject WScript.Shell
    $DesktopPath = [Environment]::GetFolderPath('Desktop')
    $OfficePath = "C:\Program Files\Microsoft Office\root\Office16"

    $Apps = @(
        @{ Name = "Word"; Exe = "WINWORD.EXE" },
        @{ Name = "Excel"; Exe = "EXCEL.EXE" },
        @{ Name = "PowerPoint"; Exe = "POWERPNT.EXE" },
        @{ Name = "Outlook"; Exe = "OUTLOOK.EXE" }
    )

    foreach ($App in $Apps) {
        $TargetPath = Join-Path $OfficePath $App.Exe
        if (Test-Path $TargetPath) {
            $Shortcut = $WshShell.CreateShortcut( (Join-Path $DesktopPath "$($App.Name).lnk") )
            $Shortcut.TargetPath = $TargetPath
            $Shortcut.Save()
        } else {
            Write-Host "Warning: Could not find $($App.Exe)" -ForegroundColor Yellow
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
    
    Write-Host "=== PHASE 2: DOMAIN JOIN ===" -ForegroundColor Cyan
    
    # Prompt user for Domain Join type
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

    # Cleanup: Remove the flag file 
    Remove-Item -Path $FlagFile -Force
    
    # Optional: Delete the script itself to leave the computer clean
    if (Test-Path "C:\Setup.ps1") {
        Remove-Item -Path "C:\Setup.ps1" -Force
    }

    Write-Host "Setup is completely finished! You can close this window." -ForegroundColor Green
    Start-Sleep -Seconds 10
}