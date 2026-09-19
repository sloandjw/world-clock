[CmdletBinding()]
param([switch]$ValidateOnly)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:ScriptPath = $PSCommandPath
$script:ConfigPath = Join-Path $script:ProjectRoot 'config\widget.json'
$script:PreferenceDirectory = Join-Path $env:LOCALAPPDATA 'WorldClockWidget'
$script:PreferencePath = Join-Path $script:PreferenceDirectory 'preferences.json'
$script:IconPath = Join-Path $script:ProjectRoot 'assets\world-clock.ico'
$script:StartupRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:StartupValueName = 'WorldClockWidget'
$script:Rows = @()
$script:IsCollapsed = $false
$script:IsExiting = $false
$script:TrayIcon = $null
$script:WpfApplication = $null
$script:Config = $null
$script:Preferences = $null

. (Join-Path $PSScriptRoot 'Settings.Dialog.ps1')

function Convert-ToBrush {
    param([Parameter(Mandatory)][string]$Color)
    try { return [Windows.Media.BrushConverter]::new().ConvertFromString($Color) }
    catch { throw "Invalid theme color '$Color'. Use #RRGGBB or #AARRGGBB." }
}

function Read-WidgetConfig {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        throw "Configuration file not found: $($script:ConfigPath)"
    }
    try { $config = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json }
    catch { throw "The configuration file is not valid JSON. $($_.Exception.Message)" }

    if (-not $config.display -or -not $config.theme -or -not $config.workingHours -or -not $config.people) {
        throw 'Configuration must contain display, theme, workingHours, and people sections.'
    }
    if ($config.people.Count -lt 1) { throw 'Configure at least one coworker in the people array.' }

    $seenIds = @{}
    foreach ($person in $config.people) {
        foreach ($property in @('id', 'name', 'location', 'timeZoneId', 'timeZoneLabel', 'color')) {
            if ([string]::IsNullOrWhiteSpace([string]$person.$property)) {
                throw "Every coworker must have a non-empty $property value."
            }
        }
        if ($seenIds.ContainsKey([string]$person.id)) {
            throw "Coworker ID '$($person.id)' is duplicated. IDs must be unique."
        }
        $seenIds[[string]$person.id] = $true
        [void](Convert-ToBrush -Color ([string]$person.color))
        try { [void][TimeZoneInfo]::FindSystemTimeZoneById([string]$person.timeZoneId) }
        catch { throw "Unknown Windows timezone '$($person.timeZoneId)' for $($person.name)." }
    }

    foreach ($name in @('background', 'surface', 'surfaceHover', 'text', 'muted', 'subtle', 'border', 'available', 'unavailable', 'warning')) {
        [void](Convert-ToBrush -Color ([string]$config.theme.$name))
    }

    $personHourSets = @($config.people | Where-Object {
        $null -ne $_.PSObject.Properties['workingHours']
    } | ForEach-Object { $_.workingHours })
    $hourSets = @($config.workingHours) + $personHourSets
    foreach ($hours in $hourSets) {
        $start = [TimeSpan]::Zero
        $end = [TimeSpan]::Zero
        if (-not [TimeSpan]::TryParse([string]$hours.start, [ref]$start) -or -not [TimeSpan]::TryParse([string]$hours.end, [ref]$end)) {
            throw "Working hours must use a value such as '09:00' or '17:30'."
        }
        if ($start -eq $end) { throw 'Working-hours start and end times cannot be the same.' }
    }
    return $config
}

function Read-Preferences {
    if (-not (Test-Path -LiteralPath $script:PreferencePath)) { return [pscustomobject]@{} }
    try { return Get-Content -LiteralPath $script:PreferencePath -Raw | ConvertFrom-Json }
    catch { return [pscustomobject]@{} }
}

function Save-Preferences {
    if (-not $script:Window) { return }
    if (-not (Test-Path -LiteralPath $script:PreferenceDirectory)) {
        [void](New-Item -ItemType Directory -Path $script:PreferenceDirectory -Force)
    }
    [ordered]@{
        left = [Math]::Round($script:Window.Left, 1)
        top = [Math]::Round($script:Window.Top, 1)
        collapsed = $script:IsCollapsed
        topmost = $script:Window.Topmost
    } | ConvertTo-Json | Set-Content -LiteralPath $script:PreferencePath -Encoding UTF8
}

function Get-EffectiveWorkingHours {
    param($Person)
    if ($null -ne $Person.PSObject.Properties['workingHours']) { return $Person.workingHours }
    return $script:Config.workingHours
}

function Get-WorkStatus {
    param([datetime]$LocalTime, $Hours)
    $workDays = @($Hours.workDays | ForEach-Object { [int]$_ })
    if ($workDays -notcontains [int]$LocalTime.DayOfWeek) {
        return [pscustomobject]@{ Text = 'Weekend'; Kind = 'Unavailable' }
    }
    $start = [TimeSpan]::Parse([string]$Hours.start)
    $end = [TimeSpan]::Parse([string]$Hours.end)
    $current = $LocalTime.TimeOfDay
    $isAvailable = if ($start -lt $end) {
        $current -ge $start -and $current -lt $end
    } else {
        $current -ge $start -or $current -lt $end
    }
    if ($isAvailable) { return [pscustomobject]@{ Text = 'Available'; Kind = 'Available' } }
    if ($current -lt $start) { return [pscustomobject]@{ Text = 'Early'; Kind = 'Warning' } }
    return [pscustomobject]@{ Text = 'After hours'; Kind = 'Unavailable' }
}

function Get-DayLabel {
    param([datetime]$LocalTime)
    $delta = ($LocalTime.Date - [datetime]::Now.Date).Days
    switch ($delta) {
        -1 { return 'Yesterday' }
        0 { return '' }
        1 { return 'Tomorrow' }
        default {
            if ($delta -gt 0) { return "+$delta days" }
            return "$([Math]::Abs($delta)) days ago"
        }
    }
}

function New-TextBlock {
    param([string]$Text = '', [double]$Size = 14, [string]$Weight = 'Normal', $Brush = $null)
    $block = [Windows.Controls.TextBlock]::new()
    $block.Text = $Text
    $block.FontSize = $Size
    $block.FontWeight = [Windows.FontWeights]::$Weight
    $block.VerticalAlignment = 'Center'
    if ($Brush) { $block.Foreground = $Brush }
    return $block
}

function New-CoworkerRow {
    param($Person)
    $theme = $script:Config.theme
    $border = [Windows.Controls.Border]::new()
    $border.Background = Convert-ToBrush ([string]$theme.surface)
    $border.BorderBrush = Convert-ToBrush ([string]$theme.border)
    $border.BorderThickness = [Windows.Thickness]::new(1)
    $border.CornerRadius = [Windows.CornerRadius]::new(11)
    $border.Padding = [Windows.Thickness]::new(12, 10, 12, 10)
    $border.Margin = [Windows.Thickness]::new(0, 0, 0, 8)

    $grid = [Windows.Controls.Grid]::new()
    $grid.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())
    $timeColumn = [Windows.Controls.ColumnDefinition]::new()
    $timeColumn.Width = [Windows.GridLength]::new(118)
    $grid.ColumnDefinitions.Add($timeColumn)

    $identityGrid = [Windows.Controls.Grid]::new()
    $dotColumn = [Windows.Controls.ColumnDefinition]::new()
    $dotColumn.Width = [Windows.GridLength]::new(20)
    $identityGrid.ColumnDefinitions.Add($dotColumn)
    $identityGrid.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())

    $dot = [Windows.Shapes.Ellipse]::new()
    $dot.Width = 9
    $dot.Height = 9
    $dot.Fill = Convert-ToBrush ([string]$theme.unavailable)
    $dot.VerticalAlignment = 'Center'
    $dot.HorizontalAlignment = 'Left'
    [Windows.Controls.Grid]::SetColumn($dot, 0)
    $identityGrid.Children.Add($dot) | Out-Null

    $identityStack = [Windows.Controls.StackPanel]::new()
    $nameBlock = New-TextBlock -Text ([string]$Person.name) -Size 14.5 -Weight 'SemiBold' -Brush (Convert-ToBrush ([string]$theme.text))
    $locationBlock = New-TextBlock -Text ([string]$Person.location) -Size 12.5 -Brush (Convert-ToBrush ([string]$theme.muted))
    $locationBlock.Margin = [Windows.Thickness]::new(0, 2, 0, 0)
    $identityStack.Children.Add($nameBlock) | Out-Null
    $identityStack.Children.Add($locationBlock) | Out-Null
    [Windows.Controls.Grid]::SetColumn($identityStack, 1)
    $identityGrid.Children.Add($identityStack) | Out-Null
    $grid.Children.Add($identityGrid) | Out-Null

    $timeStack = [Windows.Controls.StackPanel]::new()
    $timeStack.HorizontalAlignment = 'Right'
    $timeLine = [Windows.Controls.StackPanel]::new()
    $timeLine.HorizontalAlignment = 'Right'
    $timeLine.Orientation = 'Horizontal'
    $timeBlock = New-TextBlock -Size 16 -Weight 'SemiBold' -Brush (Convert-ToBrush ([string]$theme.text))
    $zoneBlock = New-TextBlock -Text ([string]$Person.timeZoneLabel) -Size 11.5 -Weight 'SemiBold' -Brush (Convert-ToBrush ([string]$Person.color))
    $zoneBlock.Margin = [Windows.Thickness]::new(6, 2, 0, 0)
    $timeLine.Children.Add($timeBlock) | Out-Null
    $timeLine.Children.Add($zoneBlock) | Out-Null
    $metaBlock = New-TextBlock -Size 12 -Brush (Convert-ToBrush ([string]$theme.muted))
    $metaBlock.HorizontalAlignment = 'Right'
    $metaBlock.Margin = [Windows.Thickness]::new(0, 2, 0, 0)
    $timeStack.Children.Add($timeLine) | Out-Null
    $timeStack.Children.Add($metaBlock) | Out-Null
    [Windows.Controls.Grid]::SetColumn($timeStack, 1)
    $grid.Children.Add($timeStack) | Out-Null

    $border.Child = $grid
    $border.Add_MouseEnter({ $this.Background = Convert-ToBrush ([string]$script:Config.theme.surfaceHover) })
    $border.Add_MouseLeave({ $this.Background = Convert-ToBrush ([string]$script:Config.theme.surface) })
    return [pscustomobject]@{ Person = $Person; Container = $border; Dot = $dot; Time = $timeBlock; Meta = $metaBlock }
}

function Update-Clocks {
    $now = [datetime]::Now
    $timeFormat = if ($script:Config.display.use24HourTime) { 'HH:mm' } else { 'h:mm tt' }
    if ($script:Config.display.showSeconds) {
        $timeFormat = if ($script:Config.display.use24HourTime) { 'HH:mm:ss' } else { 'h:mm:ss tt' }
    }
    $script:LocalTimeText.Text = $now.ToString($timeFormat)
    foreach ($row in $script:Rows) {
        try {
            $zone = [TimeZoneInfo]::FindSystemTimeZoneById([string]$row.Person.timeZoneId)
            $localTime = [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $zone)
            $status = Get-WorkStatus -LocalTime $localTime -Hours (Get-EffectiveWorkingHours $row.Person)
            $dayLabel = Get-DayLabel $localTime
            $row.Time.Text = $localTime.ToString($timeFormat)
            $parts = @()
            if ($script:Config.display.showStatus) { $parts += $status.Text }
            if ($script:Config.display.showDayOffset -and $dayLabel) { $parts += $dayLabel }
            $row.Meta.Text = $parts -join ' - '
            switch ($status.Kind) {
                'Available' { $row.Dot.Fill = Convert-ToBrush ([string]$script:Config.theme.available) }
                'Warning' { $row.Dot.Fill = Convert-ToBrush ([string]$script:Config.theme.warning) }
                default { $row.Dot.Fill = Convert-ToBrush ([string]$script:Config.theme.unavailable) }
            }
            $row.Container.ToolTip = "$($row.Person.name) - $($row.Person.location) - $($status.Text)"
        }
        catch {
            $row.Time.Text = '--:--'
            $row.Meta.Text = 'Timezone unavailable'
            $row.Dot.Fill = Convert-ToBrush ([string]$script:Config.theme.unavailable)
        }
    }
}

function Set-CollapsedState {
    param([bool]$Collapsed)
    $script:IsCollapsed = $Collapsed
    $script:RowsHost.Visibility = if ($Collapsed) { 'Collapsed' } else { 'Visible' }
    $script:Footer.Visibility = if ($Collapsed) { 'Collapsed' } else { 'Visible' }
    $script:CollapseButton.ToolTip = if ($Collapsed) { 'Restore coworker list' } else { 'Minimize coworker list' }
}

function Show-Widget {
    $script:Window.Show()
    $script:Window.WindowState = [Windows.WindowState]::Normal
    $script:Window.Activate() | Out-Null
    $script:Window.Topmost = $script:Window.Topmost
}

function Hide-Widget {
    Save-Preferences
    $script:Window.Hide()
}

function Exit-Widget {
    $script:IsExiting = $true
    $script:Window.Close()
    if ($script:WpfApplication) {
        $script:WpfApplication.Shutdown()
    }
}

function Get-StartupCommand {
    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    return ('"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "{1}"' -f $powerShellPath, $script:ScriptPath)
}

function Test-StartupEnabled {
    try {
        $value = Get-ItemPropertyValue -LiteralPath $script:StartupRegistryPath -Name $script:StartupValueName -ErrorAction Stop
        return -not [string]::IsNullOrWhiteSpace([string]$value)
    }
    catch { return $false }
}

function Set-StartupEnabled {
    param([bool]$Enabled)
    try {
        if ($Enabled) {
            if (-not (Test-Path -LiteralPath $script:StartupRegistryPath)) {
                [void](New-Item -Path $script:StartupRegistryPath -Force)
            }
            [void](New-ItemProperty -LiteralPath $script:StartupRegistryPath -Name $script:StartupValueName -Value (Get-StartupCommand) -PropertyType String -Force)
        } else {
            Remove-ItemProperty -LiteralPath $script:StartupRegistryPath -Name $script:StartupValueName -ErrorAction SilentlyContinue
        }
        $isEnabled = Test-StartupEnabled
        if ($script:StartupMenuItem) { $script:StartupMenuItem.IsChecked = $isEnabled }
        if ($script:TrayStartupMenuItem) { $script:TrayStartupMenuItem.Checked = $isEnabled }
    }
    catch {
        [Windows.MessageBox]::Show("Windows could not update the startup setting. $($_.Exception.Message)", 'World Clock startup', 'OK', 'Error') | Out-Null
        $isEnabled = Test-StartupEnabled
        if ($script:StartupMenuItem) { $script:StartupMenuItem.IsChecked = $isEnabled }
        if ($script:TrayStartupMenuItem) { $script:TrayStartupMenuItem.Checked = $isEnabled }
    }
}

function Reset-WindowPosition {
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $margin = [double]$script:Config.display.screenEdgeMargin
    $script:Window.Left = $workArea.Right - $script:Window.ActualWidth - $margin
    $script:Window.Top = $workArea.Top + $margin
}

function Open-Configuration {
    Show-ConfigurationDialog
}

function Load-Rows {
    $script:RowsHost.Children.Clear()
    $script:Rows = @()
    foreach ($person in $script:Config.people) {
        $row = New-CoworkerRow -Person $person
        $script:Rows += $row
        $script:RowsHost.Children.Add($row.Container) | Out-Null
    }
}

function Reload-Configuration {
    try {
        $script:Config = Read-WidgetConfig
        $script:TitleText.Text = ([string]$script:Config.display.title).ToUpperInvariant()
        $script:Window.Width = [double]$script:Config.display.width
        $script:RootBorder.Background = Convert-ToBrush ([string]$script:Config.theme.background)
        $script:RootBorder.BorderBrush = Convert-ToBrush ([string]$script:Config.theme.border)
        $script:RootBorder.CornerRadius = [Windows.CornerRadius]::new([double]$script:Config.theme.cornerRadius)
        Load-Rows
        Update-Clocks
    }
    catch { [Windows.MessageBox]::Show($_.Exception.Message, 'World Clock configuration', 'OK', 'Error') | Out-Null }
}

try { $script:Config = Read-WidgetConfig }
catch {
    if ($ValidateOnly) { Write-Error $_.Exception.Message; exit 1 }
    [Windows.MessageBox]::Show($_.Exception.Message, 'World Clock configuration', 'OK', 'Error') | Out-Null
    exit 1
}

if ($ValidateOnly) {
    Write-Host "Configuration valid: $($script:Config.people.Count) coworkers, $($script:Config.display.title)"
    foreach ($person in $script:Config.people) { Write-Host "  $($person.name): $($person.timeZoneId)" }
    exit 0
}

$script:Preferences = Read-Preferences
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="World Clock" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="NoResize" SizeToContent="Height"
        ShowInTaskbar="False" Topmost="True" SnapsToDevicePixels="True">
    <Border x:Name="RootBorder" Padding="12" BorderThickness="1" CornerRadius="16">
        <Border.Effect>
            <DropShadowEffect Color="#B0000000" BlurRadius="26" ShadowDepth="8" Opacity="0.55" />
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
            </Grid.RowDefinitions>
            <Grid x:Name="Header" Grid.Row="0" Margin="4,1,2,12" Cursor="SizeAll">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Vertical" VerticalAlignment="Center">
                    <TextBlock x:Name="TitleText" FontSize="12" FontWeight="SemiBold" />
                    <TextBlock x:Name="LocalTimeText" FontSize="22" FontWeight="SemiBold" Margin="0,2,0,0" />
                </StackPanel>
                <Button x:Name="CollapseButton" Grid.Column="1" Width="32" Height="32" Margin="0,0,4,0"
                        FontSize="15" ToolTip="Minimize coworker list"
                        AutomationProperties.Name="Minimize coworker list">
                    <TextBlock Text="_" FontFamily="Segoe UI" FontSize="16" Margin="0,-8,0,0" />
                </Button>
                <Button x:Name="CloseButton" Grid.Column="2" Width="32" Height="32" FontSize="14"
                        ToolTip="Hide world clock in the system tray"
                        AutomationProperties.Name="Hide world clock in the system tray">
                    <TextBlock Text="X" FontFamily="Segoe UI" FontSize="13" />
                </Button>
            </Grid>
            <StackPanel x:Name="RowsHost" Grid.Row="1" />
            <Grid x:Name="Footer" Grid.Row="2" Margin="4,3,4,1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="FooterHint" Text="Right-click to customize" FontSize="11.5" VerticalAlignment="Center" />
                <TextBlock x:Name="LiveText" Grid.Column="1" Text="LIVE" FontSize="10.5" FontWeight="Bold" VerticalAlignment="Center" />
            </Grid>
        </Grid>
    </Border>
</Window>
'@

$script:Window = [Windows.Markup.XamlReader]::Parse($xaml)
$script:RootBorder = $script:Window.FindName('RootBorder')
$script:Header = $script:Window.FindName('Header')
$script:TitleText = $script:Window.FindName('TitleText')
$script:LocalTimeText = $script:Window.FindName('LocalTimeText')
$script:CollapseButton = $script:Window.FindName('CollapseButton')
$script:CloseButton = $script:Window.FindName('CloseButton')
$script:RowsHost = $script:Window.FindName('RowsHost')
$script:Footer = $script:Window.FindName('Footer')
$script:FooterHint = $script:Window.FindName('FooterHint')
$script:LiveText = $script:Window.FindName('LiveText')

$theme = $script:Config.theme
$script:Window.Width = [double]$script:Config.display.width
$script:Window.Topmost = [bool]$script:Config.display.topmost
$script:RootBorder.Background = Convert-ToBrush ([string]$theme.background)
$script:RootBorder.BorderBrush = Convert-ToBrush ([string]$theme.border)
$script:RootBorder.CornerRadius = [Windows.CornerRadius]::new([double]$theme.cornerRadius)
$script:Window.FontFamily = [Windows.Media.FontFamily]::new([string]$theme.fontFamily)
$script:Window.Foreground = Convert-ToBrush ([string]$theme.text)
$script:TitleText.Foreground = Convert-ToBrush ([string]$theme.muted)
$script:LocalTimeText.Foreground = Convert-ToBrush ([string]$theme.text)
$script:FooterHint.Foreground = Convert-ToBrush ([string]$theme.subtle)
$script:LiveText.Foreground = Convert-ToBrush ([string]$theme.available)
$script:TitleText.Text = ([string]$script:Config.display.title).ToUpperInvariant()

foreach ($button in @($script:CollapseButton, $script:CloseButton)) {
    $button.Background = [Windows.Media.Brushes]::Transparent
    $button.Foreground = Convert-ToBrush ([string]$theme.muted)
    $button.BorderThickness = [Windows.Thickness]::new(0)
    $button.Cursor = 'Hand'
}

Load-Rows
Update-Clocks

$script:Header.Add_MouseLeftButtonDown({
    if ($_.ButtonState -eq [Windows.Input.MouseButtonState]::Pressed) { $script:Window.DragMove() }
})
$script:CollapseButton.Add_Click({ Set-CollapsedState (-not $script:IsCollapsed) })
$script:CloseButton.Add_Click({ Hide-Widget })

$contextMenu = [Windows.Controls.ContextMenu]::new()
$openConfigItem = [Windows.Controls.MenuItem]::new()
$openConfigItem.Header = 'Settings...'
$openConfigItem.InputGestureText = 'Ctrl+,'
$openConfigItem.Add_Click({ Open-Configuration })
$contextMenu.Items.Add($openConfigItem) | Out-Null
$reloadItem = [Windows.Controls.MenuItem]::new()
$reloadItem.Header = 'Reload configuration'
$reloadItem.InputGestureText = 'Ctrl+R'
$reloadItem.Add_Click({ Reload-Configuration })
$contextMenu.Items.Add($reloadItem) | Out-Null
$contextMenu.Items.Add([Windows.Controls.Separator]::new()) | Out-Null
$topmostItem = [Windows.Controls.MenuItem]::new()
$topmostItem.Header = 'Always on top'
$topmostItem.IsCheckable = $true
$topmostItem.IsChecked = $script:Window.Topmost
$topmostItem.Add_Click({ $script:Window.Topmost = $this.IsChecked })
$contextMenu.Items.Add($topmostItem) | Out-Null

$script:StartupMenuItem = [Windows.Controls.MenuItem]::new()
$script:StartupMenuItem.Header = 'Run at sign-in'
$script:StartupMenuItem.IsCheckable = $true
$script:StartupMenuItem.IsChecked = Test-StartupEnabled
$script:StartupMenuItem.Add_Click({ Set-StartupEnabled ([bool]$this.IsChecked) })
$contextMenu.Items.Add($script:StartupMenuItem) | Out-Null

$resetItem = [Windows.Controls.MenuItem]::new()
$resetItem.Header = 'Reset position'
$resetItem.Add_Click({ Reset-WindowPosition })
$contextMenu.Items.Add($resetItem) | Out-Null
$contextMenu.Items.Add([Windows.Controls.Separator]::new()) | Out-Null
$exitItem = [Windows.Controls.MenuItem]::new()
$exitItem.Header = 'Exit'
$exitItem.Add_Click({ Exit-Widget })
$contextMenu.Items.Add($exitItem) | Out-Null
$script:RootBorder.ContextMenu = $contextMenu

$script:TrayIconImage = [System.Drawing.Icon]::new($script:IconPath)
$script:TrayIcon = [System.Windows.Forms.NotifyIcon]::new()
$script:TrayIcon.Icon = $script:TrayIconImage
$script:TrayIcon.Text = 'Global team world clock'
$script:TrayIcon.Visible = $true

$trayMenu = [System.Windows.Forms.ContextMenuStrip]::new()
$trayOpenItem = [System.Windows.Forms.ToolStripMenuItem]::new('Open World Clock')
$trayOpenItem.Font = [System.Drawing.Font]::new($trayOpenItem.Font, [System.Drawing.FontStyle]::Bold)
$trayOpenItem.Add_Click({ Show-Widget })
[void]$trayMenu.Items.Add($trayOpenItem)

$traySettingsItem = [System.Windows.Forms.ToolStripMenuItem]::new('Settings...')
$traySettingsItem.Add_Click({ Show-Widget; Show-ConfigurationDialog })
[void]$trayMenu.Items.Add($traySettingsItem)

$trayReloadItem = [System.Windows.Forms.ToolStripMenuItem]::new('Reload configuration')
$trayReloadItem.Add_Click({ Reload-Configuration })
[void]$trayMenu.Items.Add($trayReloadItem)

$script:TrayStartupMenuItem = [System.Windows.Forms.ToolStripMenuItem]::new('Run at sign-in')
$script:TrayStartupMenuItem.CheckOnClick = $true
$script:TrayStartupMenuItem.Checked = Test-StartupEnabled
$script:TrayStartupMenuItem.Add_Click({ Set-StartupEnabled ([bool]$this.Checked) })
[void]$trayMenu.Items.Add($script:TrayStartupMenuItem)

[void]$trayMenu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())

$trayExitItem = [System.Windows.Forms.ToolStripMenuItem]::new('Exit')
$trayExitItem.Add_Click({ Exit-Widget })
[void]$trayMenu.Items.Add($trayExitItem)

$script:TrayIcon.ContextMenuStrip = $trayMenu
$script:TrayIcon.Add_DoubleClick({ Show-Widget })

$script:Window.Add_KeyDown({
    if ($_.Key -eq 'Escape') { Set-CollapsedState $true; $_.Handled = $true }
    elseif (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -and $_.Key -eq 'R') {
        Reload-Configuration; $_.Handled = $true
    }
    elseif (([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -and $_.Key -eq 'OemComma') {
        Open-Configuration; $_.Handled = $true
    }
})

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromSeconds([Math]::Max(1, [int]$script:Config.display.updateIntervalSeconds))
$timer.Add_Tick({ Update-Clocks })
$timer.Start()

$script:Window.Add_ContentRendered({
    $propertyNames = @($script:Preferences.PSObject.Properties | ForEach-Object { $_.Name })
    if ($propertyNames -contains 'left' -and $propertyNames -contains 'top') {
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $storedLeft = [double]$script:Preferences.left
        $storedTop = [double]$script:Preferences.top
        if ($storedLeft -lt $workArea.Right -and $storedLeft + $script:Window.ActualWidth -gt $workArea.Left -and
            $storedTop -lt $workArea.Bottom -and $storedTop + $script:Window.ActualHeight -gt $workArea.Top) {
            $script:Window.Left = $storedLeft
            $script:Window.Top = $storedTop
        } else { Reset-WindowPosition }
    } else { Reset-WindowPosition }
    if ($propertyNames -contains 'topmost') {
        $script:Window.Topmost = [bool]$script:Preferences.topmost
        $topmostItem.IsChecked = $script:Window.Topmost
    }
    if ($propertyNames -contains 'collapsed') { Set-CollapsedState ([bool]$script:Preferences.collapsed) }
})

$script:Window.Add_Closing({
    param($sender, $eventArgs)
    if (-not $script:IsExiting) {
        $eventArgs.Cancel = $true
        Hide-Widget
    }
})

$script:Window.Add_Closed({
    $timer.Stop()
    Save-Preferences
    $script:TrayIcon.Visible = $false
    $script:TrayIcon.Dispose()
    $script:TrayIconImage.Dispose()
})

$script:WpfApplication = [System.Windows.Application]::new()
$script:WpfApplication.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
[void]$script:WpfApplication.Run($script:Window)
