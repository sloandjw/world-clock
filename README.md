# World Clock Widget

A lightweight, always-on-top Windows desktop clock for global teams. It uses WPF and the Windows PowerShell runtime that ships with Windows, so there is nothing to install.

## Start the widget

Double-click **Start World Clock.cmd**.

Drag the header to reposition the widget. The `_` button collapses the coworker list, while `X` hides the window and keeps the clock running in the Windows notification area. Double-click the globe-and-clock tray icon to reopen it, or right-click the icon for Open, Settings, Reload configuration, Run at sign-in, and Exit actions.

Windows may initially place a new tray icon under the taskbar's hidden-icons arrow (`^`). Open that panel and drag the globe-and-clock icon onto the visible notification area if you want it to remain visible.

## Customize it

Right-click the widget or tray icon and choose **Settings**, or press `Ctrl+,`. The native settings window edits display preferences, default working hours, and the coworker list. Add or remove coworkers, select Windows timezones, set short labels and colors, and optionally provide individual working hours. Saving validates the entries and refreshes the widget immediately.

Advanced users can still edit `config/widget.json` directly and press `Ctrl+R` to reload it.

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
- `Ctrl+,`: open the settings window
- `Escape`: collapse the coworker list
- `Alt+F4`: hide the widget in the system tray

To stop the widget completely, right-click its tray icon and choose **Exit**.

## Preferences

Window position, collapsed state, and always-on-top preference are stored in:

```text
%LOCALAPPDATA%\WorldClockWidget\preferences.json
```

Delete that file or choose **Reset position** to return the widget to the upper-right corner of the primary screen.

## Run when you sign in

Right-click either the widget or its tray icon and enable **Run at sign-in**. Disable the same option to remove the startup entry. This setting applies only to your Windows account.

## Project documentation

- [User guide](docs/user-guide.md)
- [Developer guide](docs/developer-guide.md)
- [Implementation plan](docs/world-clock-widget-plan.md)
