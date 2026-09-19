# World Clock Widget Developer Guide

## Architecture

The application is a dependency-free Windows desktop utility built with WPF and Windows PowerShell 5.1.

| Component | Responsibility |
| --- | --- |
| `Start World Clock.cmd` | Starts Windows PowerShell invisibly in STA mode |
| `src/WorldClock.Widget.ps1` | Application lifecycle, main window, clocks, tray icon, persistence, and startup integration |
| `src/Settings.Dialog.ps1` | Native settings window, editing, validation, and configuration saving |
| `config/widget.json` | Portable user configuration |
| `assets/world-clock.ico` | Multi-resolution Windows tray icon |
| `assets/world-clock.png` | High-resolution source artwork |

## Application lifecycle

The application creates a WPF `Application` with explicit shutdown mode. Selecting `X` or pressing `Alt+F4` hides the main window but leaves the application event loop and notification icon active. Only the Exit commands set the exit flag, close the main window, dispose the icon, and shut down the application.

The tray menu and widget context menu provide equivalent access to common actions. The Run at sign-in controls stay synchronized and manage this current-user registry value:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run\WorldClockWidget
```

## Time handling

`TimeZoneInfo.FindSystemTimeZoneById` resolves configured Windows timezone IDs. `ConvertTimeFromUtc` derives each coworker's local time, allowing Windows to handle daylight-saving transitions.

Availability uses the configured local time, weekday list, and start/end values. Overnight schedules are supported when the start time is later than the end time.

## Configuration schema

The root JSON object contains:

- `display`: title, clock format, visibility options, sizing, and update interval
- `workingHours`: default start, end, and working weekdays
- `theme`: WPF-compatible colors, font family, and corner radius
- `people`: coworker records

Each coworker requires:

- `id`: unique stable identifier
- `name`
- `location`
- `timeZoneId`: Windows timezone identifier
- `timeZoneLabel`: short display label
- `color`: `#RRGGBB` or `#AARRGGBB`

A coworker may contain a `workingHours` object to override the defaults.

## Validation

Run the non-UI validator with Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\WorldClock.Widget.ps1 -ValidateOnly
```

It validates required sections, unique coworker IDs, colors, working-hour values, and Windows timezone IDs.

For a syntax-only check:

```powershell
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    "$PWD\src\WorldClock.Widget.ps1",
    [ref]$tokens,
    [ref]$errors
)
$errors
```

Run the same check for `src/Settings.Dialog.ps1`.

## Making changes

- Keep the application compatible with Windows PowerShell 5.1.
- Use WPF for the widget and settings interface.
- Use Windows Forms only for `NotifyIcon` and its tray menu.
- Preserve the explicit application loop so hiding the main window does not terminate the tray process.
- Keep editable content in `config/widget.json` rather than hard-coding coworkers.
- Validate configuration before rebuilding rows in the live widget.

## Release checklist

1. Parse both PowerShell files and resolve syntax errors.
2. Run `-ValidateOnly` against the sample configuration.
3. Launch through `Start World Clock.cmd`.
4. Verify time updates and working-hour states.
5. Open Settings, modify a value, save, and confirm immediate refresh.
6. Hide with `X` and confirm the process and tray icon remain active.
7. Restore by double-clicking the tray icon.
8. Toggle Run at sign-in on and off and verify the menu state remains synchronized.
9. Exit from the tray and confirm the process stops.

