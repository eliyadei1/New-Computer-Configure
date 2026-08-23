# Windows Endpoint Automated Provisioning Script

This PowerShell script automates the initial setup and provisioning of new Windows workstations. It is designed to minimize IT manual intervention by dividing the setup process into two automated phases, utilizing an automatic resume mechanism after the required system reboot.

## Key Features

**Phase 1: System Configuration & Installations**
* **Advanced Power Management:** 
  * *Plugged in (AC):* Never sleep, turn off the screen after 15 minutes.
  * *On Battery (DC):* Sleep after 30 minutes, turn off the screen after 15 minutes.
* **Regional Settings:** Automatically configures Timezone (Israel Standard Time), Keyboard Languages (English, Hebrew), and sets the System Locale to `en-IL`.
* **Debloat:** Removes pre-installed (UWP) Office bloatware and OneNote from the current system image to prevent conflicts.
* **Software Deployment (Winget):** Silently downloads and installs official, up-to-date versions of:
  * Google Chrome
  * Adobe Acrobat Reader (64-bit)
  * Microsoft 365 Apps (Office)
* **Desktop Shortcuts:** Automatically generates clean desktop shortcuts for Word, Excel, PowerPoint, and Outlook.
* **System Rename:** Prompts for a new standard computer name and applies it.
* **State Memory & Auto-Resume:** Creates a flag file and a `RunOnce` registry key to ensure the script "remembers" where it stopped and automatically resumes after the restart.

**Phase 2: Domain Join (Auto-runs after reboot)**
* **UAC Auto-Elevation:** Automatically requests Administrator privileges upon resuming.
* **Domain Integration:** Prompts the administrator to join the computer to either:
  1. Entra ID (Azure AD)
  2. Local Active Directory
* **Self-Cleanup:** Automatically deletes the setup flag files and removes the script itself from the C: drive to leave a completely clean environment.

---

## How to Use (Step-by-Step Guide)

You do not need to download the file manually or use a USB drive. Just follow these steps on the new computer:

**1. Launch PowerShell**
Open the Start menu, type `PowerShell`, right-click on it, and select **Run as Administrator**.

**2. Fetch and Execute the Script**
Copy and paste the following one-liner into the PowerShell window and press Enter:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-WebRequest -Uri "[https://raw.githubusercontent.com/eliyadei1/New-Computer-Configure/main/NewComputer.ps1](https://raw.githubusercontent.com/eliyadei1/New-Computer-Configure/main/NewComputer.ps1)" -OutFile "C:\Setup.ps1"; C:\Setup.ps1
```

3. Phase 1 (Automated Setup)
Let the script run. It will automatically configure power settings, set regional languages, remove bloatware, and silently install Chrome, Adobe, and Office.
Once the installations are complete, the script will pause and prompt you to enter the new computer name.

4. Automatic Restart
Type the desired computer name and press Enter. The computer will rename itself and automatically initiate a restart within 10 seconds.

5. Phase 2 (Domain Join)
Log into Windows after the restart. The script will automatically pop up and prompt for UAC Admin approval (click Yes).
Since the script remembers its state, it skips the installations and directly asks you to choose the domain type:

Type 1 for Entra ID (Azure AD).

Type 2 for Local Active Directory.

Type 3 to skip.

6. Cleanup
The relevant Windows settings window will open based on your choice. The script will then automatically delete its temporary files, memory flags, and itself from the system, leaving the workstation completely ready for the end-user.
