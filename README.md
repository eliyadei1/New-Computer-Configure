# New Computer Configure

A small, interactive PowerShell assistant for preparing a Windows workstation in Israel.
Choose the setup once, review it, and run it. Every action has its own saved result;
rerunning retries unfinished actions and skips successful ones.

## Requirements

- Windows 10/11, 64-bit **Windows PowerShell 5.1**, running as Administrator.
- Run as the account whose language, keyboard, taskbar and desktop should be configured.
  Using another administrator's credentials configures that administrator's profile.
  This script does not provision future domain-user profiles.
- Current **App Installer / WinGet** for selected application installations. If unavailable,
  install/update App Installer, then rerun; local configuration can still proceed.
- The selected Windows display language must already be installed through Windows Settings.
  Missing language packs are reported as a failed, retryable step.
- Internet access to download selected applications; organization connectivity/VPN and a
  supported Windows edition for device join. Home editions do not support AD/Entra device join.
- Office activation, VPN configuration and organization permissions are separate requirements.

## Run

Download [NewComputer.ps1](https://github.com/eliyadei1/New-Computer-Configure/blob/main/NewComputer.ps1)
and review it. Open **64-bit Windows PowerShell as Administrator** in that folder:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\NewComputer.ps1
```

The wizard asks for:

1. Hebrew or English display language, with Hebrew/English keyboards and Israeli regional settings.
2. An optional computer name (1-15 characters, letters/digits/internal hyphens, at least one letter).
3. Individual applications: Chrome, Adobe Reader, Office and optional FortiClient VPN.
4. Entra ID, local Active Directory, or an explicit skip.
5. Optional advanced settings: classic context menu, hidden Chat/Widgets, and removal of
   MicrosoftOfficeHub **for the current user only**. These default to off.

The final preview includes all choices and the power settings: no AC sleep, screen off after
15 minutes; battery sleep after 30 minutes and screen off after 15 minutes.
Nothing is applied until you confirm the preview. Installing selected applications accepts
their package and source agreements. Settings may be overridden by organizational policy;
optional shell registry settings depend on the Windows build.

## Progress, restart and recovery

- Applications install **sequentially**. Each has an exit-code check and a subsequent
  `winget list` verification. Already installed applications are left alone, including their version.
- There is no ping-based internet gate. A download failure remains failed, with diagnostics;
  it is never silently converted into a completed offline setup.
- Configuration errors are retained alongside successful results. Fix the cause and rerun
  to retry only unfinished actions. Retrying an action interrupted mid-operation may repeat
  that action, so the operations are designed to tolerate repeated execution.
- After language/name changes, setup offers a restart with **No as the default**. Save your
  work before selecting Yes. The script does not force an automatic countdown restart.
- A scheduled task resumes at the **next sign-in of the same administrator account**, in an
  interactive window. It uses the account's existing interactive token; no password is stored.
  Signing in as another user does not resume the setup.
- The task runs a stable copy at `%ProgramData%\NewComputerConfigure\NewComputer.ps1`.
  The folder restricts modification to Administrators and SYSTEM. Do not place unrelated files there.
- To resume manually from an elevated Windows PowerShell window:

```powershell
& "$env:ProgramData\NewComputerConfigure\NewComputer.ps1" -Resume
```

The folder also contains `state.json` (atomically replaced checkpoints) and timestamped
`session-*.log` transcripts. Keep these when investigating a failure. They may contain
computer/user/application details; review before sharing. Credentials are entered only
through the native Windows join interface, not collected by this script.

The organization step opens Windows Settings or System Properties and then checks actual
device membership. Entra work-account registration alone is insufficient. A failed/pending
join stays unfinished across restarts. Verification checks membership type, not a specific
tenant/domain, licensing, Intune enrollment, compliance, or application usability.

Setup reports completion only when all selected steps have succeeded and the requested
name is active after restart. The resume task is then removed; logs, state and the script
are retained. A completed setup will display its saved results without applying changes again.
Package detection verifies registration, not that every application has been activated or launched.

## Changing a saved plan

The saved plan is fixed during recovery so choices do not change unexpectedly halfway through.
To intentionally create a new plan, first inspect the old results, close any running setup, and
remove only this tool's resume task if present:

```powershell
Get-ScheduledTask -TaskName 'NewComputerConfigure-Resume' -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false
```

Rename `%ProgramData%\NewComputerConfigure\state.json` to a backup filename, then rerun the
downloaded script **without** `-Resume`. Keep the backup and logs until the new setup is verified.
This resets tracking, not Windows settings or installed applications; there is no blanket rollback.
To stop automatic resume without resetting progress, remove the task using the same command.

## Migrating from the original script

Do not overlap the old and new flows. If `C:\IT_Setup_Phase2_Flag.txt` exists, this version
stops before changing the workstation. Review/finish the old setup first. If deliberately
abandoning it, inspect and remove its `ITSetupPhase2` RunOnce entry and flag yourself before
starting a new plan. No legacy files or arbitrary `C:\Setup.ps1` are deleted by this version.

## Validation

```powershell
.\tests\Run-Tests.ps1
```

The dependency-free suite parses the script and exercises input validation, state round trips,
failure recovery, interrupted steps, native exit handling, package install verification and
AD/Entra membership detection. External provisioning commands are mocked; tests do not install
software, change settings, register tasks or join a domain. GitHub Actions runs the checks
on Windows PowerShell 5.1 and PowerShell 7; provisioning itself targets Windows PowerShell 5.1.

Before organization-wide use, validate on a disposable Windows VM: missing WinGet, missing
language pack, interrupted download, installed applications, restart deferred/completed, task
resume with the original account, and your organization's AD/Entra join flow. Real installers,
UAC, logon tasks and Windows Settings require that integration check.

## Implementation references

- [WinGet install options](https://learn.microsoft.com/en-us/windows/package-manager/winget/install)
- [Interactive scheduled-task principals](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal)
- [Entra device join status with dsregcmd](https://learn.microsoft.com/en-us/entra/identity/devices/troubleshoot-device-dsregcmd)
