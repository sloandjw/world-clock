# World Clock Widget

A lightweight, always-on-top Windows desktop clock for global teams. It uses WPF and the Windows PowerShell runtime that ships with Windows, so there is nothing to install.

## Start the widget

Double-click **Start World Clock.cmd**.

Drag the header to reposition the widget. Use the header buttons to collapse or close it. Right-click anywhere on the widget for configuration, reload, always-on-top, reset-position, and exit actions.

## Customize it

Edit `config/widget.json`, save it, and choose **Reload configuration** from the widget's right-click menu. You can also press `Ctrl+R` to reload or `Ctrl+,` to open the file in Notepad.

Each coworker needs a unique ID, name, location, Windows timezone ID, short label, and color. You can find Windows timezone IDs with:

```powershell
[TimeZoneInfo]::GetSystemTimeZones() | Select-Object Id, DisplayName
```

The top-level `workingHours` value is the default. Add a `workingHours` object to a person to override it for that coworker.

Colors accept WPF hex values. Use `#AARRGGBB` when you want to control opacity or `#RRGGBB` for a fully opaque color.

## Validate configuration

From Windows PowerShell, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\src\WorldClock.Widget.ps1 -ValidateOnly
```

Validation checks required settings, coworker IDs, work-hour values, colors, and timezone IDs without opening the widget.

## Keyboard controls

- `Ctrl+R`: reload configuration
- `Ctrl+,`: open configuration in Notepad
- `Escape`: collapse the coworker list
- `Alt+F4`: close the widget

## Preferences

Window position, collapsed state, and always-on-top preference are stored in:

```text
%LOCALAPPDATA%\WorldClockWidget\preferences.json
```

Delete that file or choose **Reset position** to return the widget to the upper-right corner of the primary screen.

## Run when you sign in

Press `Win+R`, enter `shell:startup`, and place a shortcut to **Start World Clock.cmd** in that folder.

## Project documentation

The implementation plan is in `docs/world-clock-widget-plan.md`.

