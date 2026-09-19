# World Clock Widget User Guide

## What it does

World Clock Widget is a small Windows desktop clock for seeing the current local time and likely working status of global coworkers. It stays above other windows by default, can collapse to a compact header, and continues running in the Windows notification area when its window is closed.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1, which is included with Windows

No installation, browser, account, or additional runtime is required.

## Starting and stopping

Double-click `Start World Clock.cmd` to start the widget.

- Drag the header to move it.
- Select `_` to collapse or restore the coworker list.
- Select `X` to hide the window while leaving the widget running.
- Double-click the tray icon to restore the window.
- Right-click the tray icon and select **Exit** to stop the widget completely.

Windows may initially place the tray icon behind the taskbar's hidden-icons arrow (`^`). Drag the globe-and-clock icon from that panel to the visible notification area if desired.

## Settings

Open Settings in any of these ways:

- Right-click the widget and select **Settings…**
- Right-click the tray icon and select **Settings…**
- Press `Ctrl+,` while the widget is focused

The General tab controls the title, time format, seconds, day offsets, availability text, and default working hours.

The Coworkers tab lets you:

- Add or remove coworkers
- Set names and locations
- Select a Windows timezone
- Choose a short timezone label
- Set an accent color
- Override the default working hours for an individual

Settings are validated before saving. Successful changes appear in the widget immediately.

## Status indicators

- Green: within configured working hours
- Amber: before configured working hours
- Gray: after hours or weekend

Status is also displayed as text so color is not the only indicator.

## Run at sign-in

Right-click the widget or tray icon and enable **Run at sign-in**. The option creates a startup entry for the current Windows user only. Disable the option from either menu to remove the entry.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl+,` | Open Settings |
| `Ctrl+R` | Reload configuration from disk |
| `Escape` | Collapse the coworker list |
| `Alt+F4` | Hide the widget to the tray |

## Stored data

The application stores its portable configuration in `config/widget.json`.

Window position, collapsed state, and always-on-top preference are stored per user at:

```text
%LOCALAPPDATA%\WorldClockWidget\preferences.json
```

No data is sent over the network.

## Troubleshooting

### The tray icon is missing

Open the taskbar's hidden-icons panel using `^`. Windows commonly places new notification icons there. The widget process remains active after its window is hidden.

### The widget is off-screen

Right-click the tray icon, open the widget, then right-click the widget and select **Reset position**. Deleting the preferences file also resets its position.

### A timezone is rejected

Use the searchable timezone picker in Settings. The widget uses Windows timezone IDs and automatically accounts for daylight-saving changes.

### Configuration does not load

Run validation from the project directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\WorldClock.Widget.ps1 -ValidateOnly
```

The command reports invalid JSON, timezone, color, or working-hour values.

## Removing the widget

Disable **Run at sign-in**, exit the widget from its tray menu, and delete the project folder. Optionally delete `%LOCALAPPDATA%\WorldClockWidget` to remove saved window preferences.

