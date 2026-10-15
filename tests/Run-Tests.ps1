#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'NewComputer.ps1'), [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
. (Join-Path $repo 'NewComputer.ps1')
$script:assertions = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:assertions++
}
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-True $threw $Message
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('NewComputerTests-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    foreach ($name in @('PC-001', 'A', '123A', 'ABCDEFGHIJKLMNO')) {
        Assert-True (Test-ComputerName $name) "valid name $name"
    }
    foreach ($name in @('', '123', '-PC', 'PC-', 'PC NAME', 'PC.example', 'ABCDEFGHIJKLMNOP', 'PC_01', 'PC;whoami')) {
        Assert-True (-not (Test-ComputerName $name)) "reject invalid name $name"
    }

    # Invalid inputs are reprompted, and an empty response chooses the default.
    $script:answers = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in @('invalid', '', 'y')) { $script:answers.Enqueue($answer) }
    function Read-Host { param($Prompt) return $script:answers.Dequeue() }
    Assert-True ((Read-Choice 'Choice' @('1', '2') '2') -eq '2') 'invalid input does not silently select a choice'
    Assert-True ((Read-Choice 'Choice' @('Y', 'N') 'N') -eq 'Y') 'lowercase choice is accepted'
    Remove-Item Function:\Read-Host

    $script:StatePath = Join-Path $scratch 'state.json'
    $script:State = @{
        Version = 1; UserSid = 'test'; Plan = [pscustomobject]@{ Apps = @('Google.Chrome'); Language = 'he-IL' }
        Steps = @{}; RebootFrom = $null; Complete = $false
    }
    $script:runs = 0
    Invoke-SetupStep 'download' { $script:runs++; throw 'network unavailable' }
    Assert-True ($script:State.Steps.download.Status -eq 'Failed') 'failed action stays retryable'
    $disk = Read-SetupState $script:StatePath
    Assert-True ($disk.Steps.download.Detail -eq 'network unavailable') 'failure reason persisted'
    $script:State = $disk
    Invoke-SetupStep 'download' { $script:runs++ }
    Invoke-SetupStep 'download' { throw 'must not run again' }
    Assert-True ($script:runs -eq 2) 'resume retries a failure exactly once and skips success'
    Assert-True ((Read-SetupState $script:StatePath).Steps.download.Status -eq 'Succeeded') 'success persisted atomically'
    Assert-True (-not (Test-Path "$script:StatePath.tmp")) 'no temporary state left after save'
    Invoke-SetupStep 'interrupted' {
        Assert-True ((Read-SetupState $script:StatePath).Steps.interrupted.Status -eq 'Running') 'checkpoint written before action'
        throw 'simulated interruption'
    }
    $script:State.Steps.interrupted.Status = 'Running'
    Invoke-SetupStep 'interrupted' { $script:runs++ }
    Assert-True ($script:State.Steps.interrupted.Status -eq 'Succeeded') 'interrupted steps are retried'
    $script:State.Version = 99
    Save-SetupState
    Assert-Throws { Read-SetupState $script:StatePath } 'unknown state schema rejected'

    # Safe real native process: tests exit capture without installing/configuring anything.
    $native = Invoke-NativeCommand "$env:SystemRoot\System32\cmd.exe" @('/d', '/c', 'exit 7')
    Assert-True ($native.ExitCode -eq 7) 'native nonzero exit captured'
    Assert-Throws { Invoke-CheckedCommand "$env:SystemRoot\System32\cmd.exe" @('/d', '/c', 'exit 7') } 'nonzero configuration command fails'

    # Mock only external boundaries. No winget/network/registry/task/domain operations occur.
    function Get-Command { param($Name) return [pscustomobject]@{ Source = 'mock-winget.exe' } }
    $script:codes = [Collections.Generic.Queue[int]]::new()
    $script:calls = @()
    function Invoke-NativeCommand {
        param($FilePath, $Arguments)
        $script:calls += ,@($Arguments)
        return [pscustomobject]@{ ExitCode = $script:codes.Dequeue(); Output = '' }
    }
    $script:codes.Enqueue(0)
    Install-SetupApp 'Google.Chrome'
    Assert-True ($script:calls.Count -eq 1) 'already installed package is not reinstalled'
    foreach ($code in @(1, 42)) { $script:codes.Enqueue($code) }
    Assert-Throws { Install-SetupApp 'Google.Chrome' } 'installer failure is not success'
    foreach ($code in @(1, 0, 1)) { $script:codes.Enqueue($code) }
    Assert-Throws { Install-SetupApp 'Google.Chrome' } 'successful exit with failed verification stays failed'
    foreach ($code in @(1, 0, 0)) { $script:codes.Enqueue($code) }
    Install-SetupApp 'Google.Chrome'
    $installCall = @($script:calls | Where-Object { $_[0] -eq 'install' })[-1]
    Assert-True ($installCall -contains '--silent' -and $installCall -contains '--disable-interactivity') 'installation is noninteractive'
    Assert-True ($installCall -contains '--source' -and $installCall -contains 'winget') 'explicit package source'
    Remove-Item Function:\Get-Command

    $script:joinedOutput = 'AzureAdJoined : NO'
    function Invoke-NativeCommand {
        param($FilePath, $Arguments)
        return [pscustomobject]@{ ExitCode = 0; Output = $script:joinedOutput }
    }
    Assert-True (-not (Test-OrganizationJoined '1')) 'unjoined Entra device not marked complete'
    $script:joinedOutput = "WorkplaceJoined : YES`r`n AzureAdJoined : NO"
    Assert-True (-not (Test-OrganizationJoined '1')) 'workplace registration does not count as device join'
    $script:joinedOutput = " AzureAdJoined : YES`r`n DomainJoined : NO"
    Assert-True (Test-OrganizationJoined '1') 'Entra device join detected'
    function Get-CimInstance { param($ClassName) return [pscustomobject]@{ PartOfDomain = $false } }
    Assert-True (-not (Test-OrganizationJoined '2')) 'workgroup device not counted as domain joined'
    function Get-CimInstance { param($ClassName) return [pscustomobject]@{ PartOfDomain = $true } }
    Assert-True (Test-OrganizationJoined '2') 'AD membership detected'
    Assert-True (Test-OrganizationJoined '3') 'explicit skip is honored'

    Write-Host "PASS: $script:assertions assertions; no provisioning operations executed." -ForegroundColor Green
} finally {
    # This is a fresh, explicitly allocated test directory only.
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
