# USB Descriptor Failed Device Fix

A Windows startup tool that automatically detects USB devices with "Device Descriptor Request Failed" errors (Code 43), prompts you to uninstall them, and then puts the PC to sleep and wakes it back up.

## Background

The Alienware M16 R4 has a persistent issue where the keyboard randomly stops working after a restart due to a race condition in the way it loads up USB drivers. I was able to figure out a fix which involves uninstalling the failing USB driver and then putting the device to sleep and waking it up. This program is a way for me to automate and run that process in the background so I won't have to think about it.

Reference: [Alienware M15 R4 Keyboard Driver Issue](https://www.reddit.com/r/Alienware/comments/17nqy5y/alienware_m15_r4_keyboard_driver_issue_solution/)

## Problem

When USB devices fail to initialize properly, Windows shows:
- "Windows has stopped this device because it has reported problems. (Code 43)"
- "A request for the USB device descriptor failed."

## Solution

This script runs on startup/login, detects the problematic device, and offers to fix it automatically.

## Features

- Automatic detection of USB descriptor failed device

- GUI prompt for user confirmation

- Uninstall problematic device

- Put PC to sleep and auto-wake after 10 seconds

- Runs as scheduled task on startup and login

  

## Files

| File | Purpose |
|------|---------|
| `UsbDescriptorFix.ps1` | Main script |
| `Install-UsbFixStartup.ps1` | Install as startup task |
| `Uninstall-UsbFixStartup.ps1` | Remove startup task |

## Installation

1. Right-click `Install-UsbFixStartup.ps1`
2. Select "Run with PowerShell"
3. Approve the UAC prompt

The script will now run automatically on Windows startup and when you log in.

## Manual Usage

To run manually at any time:

1. Right-click `UsbDescriptorFix.ps1`
2. Select "Run with PowerShell"
3. Approve the UAC prompt

## Uninstallation

To remove the automatic startup task:

1. Right-click `Uninstall-UsbFixStartup.ps1`
2. Select "Run with PowerShell"
3. Approve the UAC prompt

Or run in PowerShell as Admin:
```powershell
Unregister-ScheduledTask -TaskName 'UsbDescriptorFix_Startup' -Confirm:$false
```

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Administrator privileges (auto-elevates)

## How It Works

1. On startup/login, the script scans for USB devices with:
   - Status: Error
   - InstanceId starting with `USB\`
   - "Device Descriptor Request Failed" in name
   - Problem code 43 (Code 43)

2. If devices are found, a dialog appears showing:
   - Number of affected devices
   - Device names

3. When you click "Uninstall && Sleep":
   - Devices are uninstalled using PowerShell PnP cmdlets
   - A scheduled wake task is created
   - PC enters sleep mode
   - PC wakes after 10 seconds
   - Wake task is automatically cleaned up

## Troubleshooting

**Script doesn't detect devices:**
- Make sure you're running as Administrator
- Check Device Manager to confirm the device shows with "Error" status

**Script closes immediately:**
- Run from PowerShell console to see error messages
- Check log file at: `%TEMP%\UsbDescriptorFix_Log.txt`

**Uninstall fails:**
- Some USB devices may be protected
- Try using Device Manager manually: Right-click device → Uninstall device

## Logs

Debug logs are written to:
- `%TEMP%\UsbDescriptorFix_Log.txt` - Uninstall attempt logs
- `%TEMP%\UsbDescriptorFix_Debug.txt` - Script execution debug info

## License

Free to use and modify.
