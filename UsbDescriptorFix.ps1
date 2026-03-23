# USB Descriptor Failed Device Handler
# Run this at startup to detect and fix problematic USB devices

# Self-elevate if not running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # Relaunch as administrator
    Write-Host "Administrator privileges required. Elevating..." -ForegroundColor Yellow
    $psiArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $process = Start-Process powershell -ArgumentList $psiArgs -Verb RunAs -PassThru
    $process.WaitForExit()
    exit $process.ExitCode
}

# Confirm admin rights
Write-Host "============================================" -ForegroundColor Green
Write-Host "Running as Administrator: $isAdmin" -ForegroundColor Green
Write-Host "Current User: $env:USERNAME" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

# Log to file
"=== Script started at $(Get-Date) ===" | Out-File "$env:TEMP\UsbDescriptorFix_Debug.txt"
"Admin: $isAdmin, User: $env:USERNAME" | Out-File "$env:TEMP\UsbDescriptorFix_Debug.txt" -Append

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

function Get-UsbDescriptorFailedDevices {
    # Method 1: Look for "Device Descriptor Request Failed" in FriendlyName
    $descriptorByName = Get-PnpDevice | Where-Object {
        $_.Status -eq 'Error' -and
        $_.FriendlyName -match 'Device Descriptor Request Failed'
    }

    # Method 2: Look for any Error status USB devices (InstanceId starts with USB\)
    $descriptorById = Get-PnpDevice | Where-Object {
        $_.Status -eq 'Error' -and
        $_.InstanceId -like 'USB*'
    }

    # Method 3: Check for Code 43 (DEVPKEY_Device_ProblemCode = 43)
    $problemDevices = Get-PnpDevice | Where-Object {
        $_.Status -eq 'Error' -and
        (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue).Data -eq 43
    }

    # Combine and deduplicate - force array output
    $allDevices = @(@($descriptorByName) + @($descriptorById) + @($problemDevices))
    $result = @($allDevices | Sort-Object -Property InstanceId -Unique)
    return ,$result  # Force return as array
}

function Uninstall-PnpDevice {
    param(
        [string]$InstanceId
    )

    Write-Host "  Attempting to uninstall: $InstanceId" -ForegroundColor Cyan

    try {
        # Method 1: Try using Remove-PnpDevice (PowerShell native)
        try {
            $device = Get-PnpDevice | Where-Object { $_.InstanceId -eq $InstanceId }
            if ($device) {
                Write-Host "    Found device: $($device.FriendlyName)" -ForegroundColor Gray
                Remove-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
                Write-Host "  Successfully uninstalled device (Remove-PnpDevice)." -ForegroundColor Green
                return $true
            }
        } catch {
            Write-Host "    Remove-PnpDevice failed: $_" -ForegroundColor DarkYellow
        }

        # Method 2: Try using pnputil
        try {
            $escapedId = $InstanceId -replace '\\', '\\'
            $result = & pnputil /remove-device $InstanceId 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Successfully uninstalled device (pnputil)." -ForegroundColor Green
                return $true
            } else {
                Write-Host "    pnputil output: $result" -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "    pnputil failed: $_" -ForegroundColor DarkYellow
        }

        # Method 3: Try using CIM/WMI to call the device's Remove method
        try {
            $cimDevice = Get-CimInstance Win32_PnPEntity | Where-Object { $_.DeviceID -eq $InstanceId }
            if ($cimDevice) {
                $cimDevice | Invoke-CimMethod -MethodName "Disable" -Arguments $null
                Start-Sleep -Milliseconds 500
                $cimDevice | Invoke-CimMethod -MethodName "Remove" -Arguments $null
                Write-Host "  Successfully removed device (CIM)." -ForegroundColor Green
                return $true
            }
        } catch {
            Write-Host "    CIM method failed: $_" -ForegroundColor DarkYellow
        }

        Write-Host "  All uninstall methods failed." -ForegroundColor Red
        return $false

    } catch {
        Write-Host "  Error uninstalling device: $_" -ForegroundColor Red
        Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
        return $false
    }
}

function Set-SleepAndWake {
    param(
        [int]$SleepSeconds = 10
    )

    # Create a scheduled task to wake the PC
    $wakeTime = (Get-Date).AddSeconds($SleepSeconds)
    $taskName = "UsbDescriptorFix_WakeUp"
    $taskTrigger = New-ScheduledTaskTrigger -Once -At $wakeTime
    $taskAction = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c exit"
    $taskSettings = New-ScheduledTaskSettingsSet -WakeToRun

    # Register the task with wake capability
    Register-ScheduledTask -TaskName $taskName `
                          -Action $taskAction `
                          -Trigger $taskTrigger `
                          -Settings $taskSettings `
                          -Force `
                          -ErrorAction SilentlyContinue | Out-Null

    # Put PC to sleep
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $false, $false)

    # Clean up the wake task after sleep
    Start-Sleep -Seconds 2
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Show-PromptDialog {
    param(
        [array]$Devices
    )

    # Use a hash table to store the dialog result
    $dialogResult = @{ Confirmed = $false }

    # Build device list XML
    $deviceListXml = ""
    foreach ($dev in $Devices) {
        $deviceListXml += "        <TextBlock Text='• $($dev.FriendlyName)' Margin='10,2,0,2' TextWrapping='Wrap'/>`n"
    }

    # Create the WPF window
    [xml]$xaml = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Title="USB Device Error Detected"
            Height="300" Width="500"
            WindowStartupLocation="CenterScreen"
            ResizeMode="NoResize"
            Topmost="True">
        <Grid Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0"
                       Text="USB Descriptor Failed Device Detected"
                       FontSize="18"
                       FontWeight="Bold"
                       Foreground="#DC3545"
                       Margin="0,0,0,15"/>

            <TextBlock Grid.Row="1"
                       Text="One or more USB devices have failed to initialize properly. This may cause system issues."
                       TextWrapping="Wrap"
                       Margin="0,0,0,15"/>

            <Border Grid.Row="2"
                    Background="#F8F9FA"
                    BorderBrush="#DEE2E6"
                    BorderThickness="1"
                    CornerRadius="5"
                    Padding="10"
                    Margin="0,0,0,15">
                <StackPanel>
                    <TextBlock Text="Affected Device(s):" FontWeight="Bold" Margin="0,0,0,5"/>
$deviceListXml                </StackPanel>
            </Border>

            <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Name="btnUninstallSleep"
                        Content="Uninstall &amp;&amp; Sleep"
                        Width="140" Height="35"
                        Margin="0,0,10,0"
                        Background="#DC3545"
                        Foreground="White"/>
                <Button Name="btnIgnore"
                        Content="Ignore"
                        Width="100" Height="35"/>
            </StackPanel>
        </Grid>
    </Window>
"@

    $reader = (New-Object System.Xml.XmlNodeReader $xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $btnUninstallSleep = $window.FindName("btnUninstallSleep")
    $btnIgnore = $window.FindName("btnIgnore")

    # Use Module scope to capture the result
    $btnUninstallSleep.add_Click({
        $dialogResult.Confirmed = $true
        $window.Close()
    }.GetNewClosure())

    $btnIgnore.add_Click({
        $dialogResult.Confirmed = $false
        $window.Close()
    }.GetNewClosure())

    $window.ShowDialog() | Out-Null
    return $dialogResult.Confirmed
}

function Show-ConsolePrompt {
    param(
        [array]$Devices
    )

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "USB Descriptor Failed Device Detected" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "One or more USB devices have failed to initialize properly." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Affected Device(s):" -ForegroundColor Cyan
    foreach ($dev in $Devices) {
        Write-Host "  - $($dev.FriendlyName)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "InstanceId: $($Devices[0].InstanceId)" -ForegroundColor DarkGray
    Write-Host ""

    $response = Read-Host "Uninstall device and sleep? (Y/N)"
    return $response -eq 'Y' -or $response -eq 'y'
}

function Test-IsGuiAvailable {
    # Check if we're in an interactive session with a desktop
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return [System.Windows.Forms.Screen]::AllScreens.Count -gt 0
    } catch {
        return $false
    }
}

# Main execution
$errorDevices = Get-UsbDescriptorFailedDevices

if ($errorDevices.Count -gt 0) {
    # Check if GUI is available, otherwise use console
    if (Test-IsGuiAvailable) {
        Write-Host "Showing GUI dialog..." -ForegroundColor Cyan
        $userConfirmed = Show-PromptDialog -Devices $errorDevices
        Write-Host "Dialog result: $userConfirmed" -ForegroundColor Cyan
    } else {
        $userConfirmed = Show-ConsolePrompt -Devices $errorDevices
    }

    Write-Host "User confirmed: $userConfirmed" -ForegroundColor Yellow

    if ($userConfirmed) {
        # Start a log file
        $logFile = "$env:TEMP\UsbDescriptorFix_Log.txt"
        "=== USB Descriptor Fix Log $(Get-Date) ===" | Out-File $logFile

        $output = "Starting uninstall process for $($errorDevices.Count) device(s)..."
        Write-Host $output
        $output | Out-File $logFile -Append

        $successCount = 0
        foreach ($device in $errorDevices) {
            $output = "Device: $($device.FriendlyName)"
            Write-Host $output
            $output | Out-File $logFile -Append

            $output = "InstanceId: $($device.InstanceId)"
            Write-Host $output
            $output | Out-File $logFile -Append

            try {
                if (Uninstall-PnpDevice -InstanceId $device.InstanceId) {
                    $successCount++
                    $output = "  SUCCESS!"
                    Write-Host $output -ForegroundColor Green
                } else {
                    $output = "  FAILED!"
                    Write-Host $output -ForegroundColor Red
                }
                $output | Out-File $logFile -Append
            } catch {
                $output = "  ERROR: $_"
                Write-Host $output -ForegroundColor Red
                $output | Out-File $logFile -Append
            }
        }

        $output = "Uninstall complete: $successCount / $($errorDevices.Count) succeeded"
        Write-Host $output
        $output | Out-File $logFile -Append

        # Show result in a message box
        if ($successCount -gt 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Successfully uninstalled $successCount device(s). PC will now sleep and wake in 10 seconds.",
                "USB Fix - Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )

            # Give a moment for the uninstall to complete
            Start-Sleep -Seconds 2

            # Put PC to sleep and schedule wake-up
            Set-SleepAndWake -SleepSeconds 10
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to uninstall any devices. Check log file: $logFile",
                "USB Fix - Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    }

    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor Gray
    Write-Host "Log file: $logFile" -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} else {
    Write-Host "No USB descriptor failed devices detected. Exiting."
}
