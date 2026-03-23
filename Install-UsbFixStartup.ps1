# Helper script to install the USB Descriptor Fix as a startup task
# Run this once to set up the automatic startup functionality

# Self-elevate if not running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Administrator privileges required. Elevating..." -ForegroundColor Yellow
    $psiArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $process = Start-Process powershell -ArgumentList $psiArgs -Verb RunAs -PassThru
    $process.WaitForExit()
    exit $process.ExitCode
}

$ScriptPath = Join-Path $PSScriptRoot "UsbDescriptorFix.ps1"
$TaskName = "UsbDescriptorFix_Startup"
$TaskDescription = "Detects and removes USB descriptor failed devices on startup"

# Check if the main script exists
if (-not (Test-Path $ScriptPath)) {
    Write-Error "UsbDescriptorFix.ps1 not found at: $ScriptPath"
    exit 1
}

# Create the scheduled task action
$TaskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

# Create trigger - run at startup and at logon
$TaskTriggerStartup = New-ScheduledTaskTrigger -AtStartup
$TaskTriggerLogon = New-ScheduledTaskTrigger -AtLogon

# Settings - run with highest privileges
$TaskSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Register the task
try {
    # Remove existing task if it exists
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

    # Register new task with multiple triggers
    Register-ScheduledTask -TaskName $TaskName `
                          -Action $TaskAction `
                          -Trigger $TaskTriggerStartup `
                          -Settings $TaskSettings `
                          -Description $TaskDescription `
                          -RunLevel Highest `
                          -Force | Out-Null

    # Add the logon trigger as well
    $task = Get-ScheduledTask -TaskName $TaskName
    $task.Triggers += $TaskTriggerLogon
    $task | Set-ScheduledTask

    Write-Host "Success! 'UsbDescriptorFix' has been installed as a startup task." -ForegroundColor Green
    Write-Host ""
    Write-Host "The script will now:"
    Write-Host "  - Run automatically when Windows starts"
    Write-Host "  - Run automatically when you log in"
    Write-Host "  - Detect USB descriptor failed devices"
    Write-Host "  - Prompt you to uninstall and sleep/wake"
    Write-Host ""
    Write-Host "To uninstall this task, run: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"

} catch {
    Write-Error "Failed to create scheduled task: $_"
    exit 1
}
