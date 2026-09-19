# Lightweight Windows World Clock Widget

## Product goal

Build a compact Windows desktop widget that keeps global coworkers' local times visible without requiring a browser, web server, account, or installer. The widget should feel like a heads-up display: quiet, glanceable, movable, and easy to dismiss or collapse.

## Implementation choice

The widget uses Windows Presentation Foundation (WPF) through the Windows PowerShell runtime already included with Windows. This keeps the application dependency-free and avoids bundling a browser engine or requiring the .NET SDK.

The deliverable consists of:

- A small launcher that starts the widget without showing a console window
- A WPF application script containing the desktop behavior
- A JSON configuration file for coworkers, working hours, display settings, and colors
- Local preferences stored under the current user's local application-data folder

## Core experience

The expanded widget displays:

- The viewer's current local time
- Coworker name and location
- Current time in each coworker's timezone
- A short timezone label
- Yesterday or tomorrow when the coworker's calendar day differs
- Available, early, after-hours, or weekend status

The widget can be dragged from its header, collapsed into a narrow time strip, kept above other windows, reloaded after configuration changes, or hidden to the Windows notification area. Closing the window keeps the clock running; the tray menu provides explicit Open and Exit actions.

## Configuration

All commonly changed values live in `config/widget.json`:

- Coworker names, locations, timezone IDs, and accent colors
- Global or per-person work hours and work days
- 12-hour or 24-hour formatting
- Whether day offsets and status text are shown
- Widget width and screen-edge spacing
- Colors, corner radius, typography, and opacity
- Whether the widget stays above other windows

Timezone IDs use Windows timezone names such as `Pacific Standard Time`, `GMT Standard Time`, and `India Standard Time`. Windows handles daylight-saving transitions automatically.

## Desktop behavior

- The widget opens near the upper-right corner on first launch.
- Its last position and collapsed state are restored on later launches.
- The widget does not occupy a taskbar slot.
- Closing the window hides it to a custom globe-and-clock tray icon instead of stopping it.
- Double-clicking the tray icon restores the widget; its menu provides Open, Reload, and Exit actions.
- A synchronized Run at sign-in option in both context menus controls startup for the current Windows user.
- A native settings window manages display preferences, default hours, coworkers, timezone selection, colors, and per-person working-hour overrides without requiring JSON editing.
- Right-clicking opens configuration, reload, always-on-top, reset-position, and exit actions.
- Pressing `Ctrl+R` reloads configuration.
- Pressing `Ctrl+,` opens the configuration file.
- Pressing `Escape` collapses the coworker list.

## Accessibility and resilience

- Controls have automation names and keyboard focus states.
- Status is communicated through both text and color.
- Main text remains at least 14 pixels.
- Invalid configuration displays an actionable native error instead of silently failing.
- Unknown timezones are reported by validation and shown as unavailable at runtime.
- Updates occur only once per clock interval rather than continuously.

## Project structure

```text
world-clock/
├── config/
│   └── widget.json
├── assets/
│   ├── world-clock.ico
│   └── world-clock.png
├── docs/
│   └── world-clock-widget-plan.md
├── src/
│   └── WorldClock.Widget.ps1
├── Start World Clock.cmd
└── README.md
```

## Definition of done

- The widget launches directly on Windows without a browser.
- Adding or changing a coworker requires editing only the JSON configuration.
- The widget displays accurate DST-aware times for valid Windows timezone IDs.
- Working-hours status and date offsets update automatically.
- Position, collapsed state, and always-on-top preference persist between launches.
- The widget remains active in the notification area until Exit is chosen from its tray menu.
- The widget is usable by mouse and keyboard at common Windows scaling levels.
- Configuration validation can be run without opening the interface.
