# Windows Endpoint Automated Provisioning Script

This PowerShell script automates the initial setup and provisioning of new Windows workstations. It is designed to minimize IT manual intervention by dividing the setup process into two automated phases, with an automatic resume mechanism after the required system reboot.

## Features

**Phase 1: System Configuration & Installations**
* **Power Management:** Disables the "Sleep" state when the device is plugged in to prevent disconnections during remote setups.
* **Regional Settings:** Automatically configures Timezone (Israel Standard Time), Keyboard Languages (English, Hebrew), and sets the System Locale to `en-IL`.
* **Debloat:** Removes pre-installed (UWP) Office bloatware and OneNote from the current system image.
* **Software Deployment:** Uses `winget` to silently download and install official, up-to-date versions of:
  * Google Chrome
  * Adobe Acrobat Reader (64-bit)
  * Microsoft 365 Apps (Office)
* **Desktop Shortcuts:** Automatically generates clean desktop shortcuts for Word, Excel, PowerPoint, and Outlook.
* **System Rename & Auto-Resume:** Prompts for a new standard computer name, creates a `RunOnce` registry key for Phase 2, and triggers a system restart.

**Phase 2: Domain Join (Auto-runs after reboot)**
* **UAC Auto-Elevation:** Automatically ensures the script runs with Administrator privileges upon resuming.
* **Domain Integration:** Prompts the administrator to join the computer to either:
  1. Entra ID (Azure AD)
  2. Local Active Directory
* **Self-Cleanup:** Automatically deletes the setup flag files and removes itself from the system to leave a clean environment.

## Usage
Run the following one-liner in an elevated PowerShell (Run as Administrator) to execute the script directly from GitHub without needing a USB drive:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-WebRequest -Uri "[https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/NewComputer.ps1](https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/NewComputer.ps1)" -OutFile "C:\Setup.ps1"; C:\Setup.ps1
