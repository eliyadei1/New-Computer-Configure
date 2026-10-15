# Changes in this revision

- Replaced the two-phase flag with atomic JSON checkpoints and saved results per action.
- Added plan preview, validated input, individual software selection and opt-in advanced tweaks.
- Replaced parallel installers with sequential WinGet installs, checked native exit codes and package verification.
- Removed ping-based download skipping. Missing WinGet/network and failed installs remain retryable failures.
- Replaced disposable RunOnce with an interactive logon task for the original administrator account and a stable protected script copy.
- Made restarts explicit and deferred completion until restart/name verification when required.
- Verified AD/Entra device membership instead of reporting success after opening a settings window.
- Stopped deleting arbitrary setup files, OneNote and Office packages for all users.
- Removed the blanket telemetry policy change and its unsupported promise of disabling all collection.
- Kept logs and state for diagnosis; removed only this tool's resume task on completion.
- Added 32-bit Office path support for shortcuts and checks for the selected display language pack.
- Documented prerequisites, user-profile scope, recovery, legacy migration and integration-test limits.
- Added 36 regression assertions and a GitHub Actions workflow for Windows PowerShell 5.1 and PowerShell 7.

Local validation: all 36 assertions passed under both runtimes. No real provisioning operations
were executed. Full Windows VM validation remains necessary for installers, UAC, scheduled-logon
resume, language/profile changes and organization enrollment.

