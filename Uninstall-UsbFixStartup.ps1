# Helper script to uninstall the USB Descriptor Fix startup task

$TaskName = "UsbDescriptorFix_Startup"

# Check if task exists
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($task) {
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Success! 'UsbDescriptorFix' startup task has been removed." -ForegroundColor Green
        Write-Host ""
        Write-Host "The script will no longer run automatically on startup or logon."
    } catch {
        Write-Error "Failed to remove scheduled task: $_"
        exit 1
    }
} else {
    Write-Host "No startup task found. 'UsbDescriptorFix' was not installed." -ForegroundColor Yellow
}
