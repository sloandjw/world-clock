function Update-SettingsPersonFromFields {
    if ($script:SettingsSelectedIndex -lt 0 -or $script:SettingsSelectedIndex -ge $script:SettingsPeople.Count) { return }

    $person = $script:SettingsPeople[$script:SettingsSelectedIndex]
    $person.name = $script:SettingsNameBox.Text.Trim()
    $person.location = $script:SettingsLocationBox.Text.Trim()
    $person.timeZoneId = $script:SettingsTimeZoneBox.Text.Trim()
    $person.timeZoneLabel = $script:SettingsZoneLabelBox.Text.Trim()
    $person.color = $script:SettingsColorBox.Text.Trim()

    if ($script:SettingsCustomHoursBox.IsChecked) {
        $hours = [pscustomobject]@{
            start = $script:SettingsPersonStartBox.Text.Trim()
            end = $script:SettingsPersonEndBox.Text.Trim()
            workDays = @(1, 2, 3, 4, 5)
        }
        if ($null -eq $person.PSObject.Properties['workingHours']) {
            $person | Add-Member -NotePropertyName workingHours -NotePropertyValue $hours
        } else {
            $person.workingHours = $hours
        }
    } elseif ($null -ne $person.PSObject.Properties['workingHours']) {
        $person.PSObject.Properties.Remove('workingHours')
    }
}

function Show-SettingsPersonFields {
    param([int]$Index)
    $script:SettingsLoading = $true
    try {
        $hasPerson = $Index -ge 0 -and $Index -lt $script:SettingsPeople.Count
        $script:SettingsPersonPanel.IsEnabled = $hasPerson
        if (-not $hasPerson) {
            foreach ($control in @($script:SettingsNameBox, $script:SettingsLocationBox, $script:SettingsTimeZoneBox, $script:SettingsZoneLabelBox, $script:SettingsColorBox, $script:SettingsPersonStartBox, $script:SettingsPersonEndBox)) {
                $control.Text = ''
            }
            $script:SettingsCustomHoursBox.IsChecked = $false
            return
        }

        $person = $script:SettingsPeople[$Index]
        $script:SettingsNameBox.Text = [string]$person.name
        $script:SettingsLocationBox.Text = [string]$person.location
        $script:SettingsTimeZoneBox.Text = [string]$person.timeZoneId
        $script:SettingsZoneLabelBox.Text = [string]$person.timeZoneLabel
        $script:SettingsColorBox.Text = [string]$person.color
        $hasCustomHours = $null -ne $person.PSObject.Properties['workingHours']
        $script:SettingsCustomHoursBox.IsChecked = $hasCustomHours
        $script:SettingsPersonStartBox.Text = if ($hasCustomHours) { [string]$person.workingHours.start } else { [string]$script:Config.workingHours.start }
        $script:SettingsPersonEndBox.Text = if ($hasCustomHours) { [string]$person.workingHours.end } else { [string]$script:Config.workingHours.end }
        $script:SettingsPersonStartBox.IsEnabled = $hasCustomHours
        $script:SettingsPersonEndBox.IsEnabled = $hasCustomHours
    }
    finally { $script:SettingsLoading = $false }
}

function Refresh-SettingsPeopleList {
    param([int]$SelectedIndex = 0)
    $script:SettingsPeopleList.Items.Clear()
    foreach ($person in $script:SettingsPeople) {
        $label = if ([string]::IsNullOrWhiteSpace([string]$person.location)) { [string]$person.name } else { "$($person.name) - $($person.location)" }
        [void]$script:SettingsPeopleList.Items.Add($label)
    }
    if ($script:SettingsPeople.Count -gt 0) {
        $script:SettingsPeopleList.SelectedIndex = [Math]::Min([Math]::Max(0, $SelectedIndex), $script:SettingsPeople.Count - 1)
    }
}

function Test-SettingsTime {
    param([string]$Value, [string]$Label)
    $parsed = [TimeSpan]::Zero
    if (-not [TimeSpan]::TryParse($Value, [ref]$parsed)) {
        throw "$Label must use a time such as 09:00 or 17:30."
    }
}

function Save-SettingsConfiguration {
    Update-SettingsPersonFromFields

    $title = $script:SettingsTitleBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($title)) { throw 'Widget title cannot be empty.' }
    if ($script:SettingsPeople.Count -lt 1) { throw 'Add at least one coworker.' }

    Test-SettingsTime $script:SettingsDefaultStartBox.Text.Trim() 'Default start time'
    Test-SettingsTime $script:SettingsDefaultEndBox.Text.Trim() 'Default end time'

    foreach ($person in $script:SettingsPeople) {
        if ([string]::IsNullOrWhiteSpace([string]$person.name)) { throw 'Every coworker needs a name.' }
        if ([string]::IsNullOrWhiteSpace([string]$person.location)) { throw "$($person.name) needs a location." }
        if ([string]::IsNullOrWhiteSpace([string]$person.timeZoneLabel)) { throw "$($person.name) needs a short timezone label." }
        try { [void][TimeZoneInfo]::FindSystemTimeZoneById([string]$person.timeZoneId) }
        catch { throw "Select a valid Windows timezone for $($person.name)." }
        [void](Convert-ToBrush ([string]$person.color))
        if ($null -ne $person.PSObject.Properties['workingHours']) {
            Test-SettingsTime ([string]$person.workingHours.start) "$($person.name)'s start time"
            Test-SettingsTime ([string]$person.workingHours.end) "$($person.name)'s end time"
        }
    }

    $script:Config.display.title = $title
    $script:Config.display.use24HourTime = [bool]$script:Settings24HourBox.IsChecked
    $script:Config.display.showSeconds = [bool]$script:SettingsSecondsBox.IsChecked
    $script:Config.display.showDayOffset = [bool]$script:SettingsDayOffsetBox.IsChecked
    $script:Config.display.showStatus = [bool]$script:SettingsStatusBox.IsChecked
    $script:Config.workingHours.start = $script:SettingsDefaultStartBox.Text.Trim()
    $script:Config.workingHours.end = $script:SettingsDefaultEndBox.Text.Trim()
    $script:Config.people = @($script:SettingsPeople)

    $script:Config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
}

function Show-ConfigurationDialog {
    $script:SettingsPeople = [Collections.ArrayList]::new()
    foreach ($person in $script:Config.people) {
        $clone = $person | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        [void]$script:SettingsPeople.Add($clone)
    }
    $script:SettingsSelectedIndex = -1
    $script:SettingsLoading = $false

    $settingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="World Clock Settings" Width="760" Height="610" MinWidth="680" MinHeight="540"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False" Background="#171E27" Foreground="#F5F7FA">
    <Window.Resources>
        <Style TargetType="TextBlock"><Setter Property="FontFamily" Value="Segoe UI" /></Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#252E3A"/><Setter Property="Foreground" Value="#F5F7FA"/>
            <Setter Property="BorderBrush" Value="#435063"/><Setter Property="Padding" Value="9,7"/><Setter Property="FontSize" Value="14"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#252E3A"/><Setter Property="Foreground" Value="#111820"/>
            <Setter Property="BorderBrush" Value="#435063"/><Setter Property="Padding" Value="7,5"/><Setter Property="FontSize" Value="14"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#2C3745"/><Setter Property="Foreground" Value="#F5F7FA"/>
            <Setter Property="BorderBrush" Value="#435063"/><Setter Property="Padding" Value="14,8"/><Setter Property="FontSize" Value="14"/>
        </Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#F5F7FA"/><Setter Property="FontSize" Value="14"/><Setter Property="Margin" Value="0,5,18,5"/></Style>
    </Window.Resources>
    <Grid Margin="22">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,18">
            <TextBlock Text="World Clock Settings" FontSize="26" FontWeight="SemiBold"/>
            <TextBlock Text="Changes are validated and applied as soon as you save." Foreground="#98A6B7" FontSize="13" Margin="0,4,0,0"/>
        </StackPanel>
        <TabControl Grid.Row="1" Background="#1B222C" BorderBrush="#354151">
            <TabItem Header="General">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="20">
                        <TextBlock Text="DISPLAY" Foreground="#7D9BFF" FontSize="12" FontWeight="Bold" Margin="0,0,0,9"/>
                        <TextBlock Text="Widget title" Foreground="#B8C2CF" FontSize="13" Margin="0,0,0,5"/>
                        <TextBox x:Name="TitleBox" MaxLength="40" Margin="0,0,0,14"/>
                        <WrapPanel Margin="0,0,0,18">
                            <CheckBox x:Name="Hour24Box" Content="Use 24-hour time"/>
                            <CheckBox x:Name="SecondsBox" Content="Show seconds"/>
                            <CheckBox x:Name="DayOffsetBox" Content="Show day offset"/>
                            <CheckBox x:Name="StatusBox" Content="Show availability"/>
                        </WrapPanel>
                        <TextBlock Text="DEFAULT WORKING HOURS" Foreground="#7D9BFF" FontSize="12" FontWeight="Bold" Margin="0,3,0,9"/>
                        <Grid MaxWidth="410" HorizontalAlignment="Left">
                            <Grid.ColumnDefinitions><ColumnDefinition Width="190"/><ColumnDefinition Width="30"/><ColumnDefinition Width="190"/></Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0"><TextBlock Text="Start" Foreground="#B8C2CF" FontSize="13" Margin="0,0,0,5"/><TextBox x:Name="DefaultStartBox"/></StackPanel>
                            <StackPanel Grid.Column="2"><TextBlock Text="End" Foreground="#B8C2CF" FontSize="13" Margin="0,0,0,5"/><TextBox x:Name="DefaultEndBox"/></StackPanel>
                        </Grid>
                        <TextBlock Text="Use 24-hour values such as 09:00 and 17:30. Individual coworkers can override these hours." Foreground="#7E8C9D" FontSize="12.5" Margin="0,10,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="Coworkers">
                <Grid Margin="16">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="240"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Grid Grid.Column="0">
                        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                        <ListBox x:Name="PeopleList" Background="#202936" Foreground="#F5F7FA" BorderBrush="#354151" FontSize="14" Padding="4"/>
                        <Grid Grid.Row="1" Margin="0,10,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                            <Button x:Name="AddPersonButton" Content="Add" Grid.Column="0"/>
                            <Button x:Name="RemovePersonButton" Content="Remove" Grid.Column="2"/>
                        </Grid>
                    </Grid>
                    <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto">
                        <StackPanel x:Name="PersonPanel">
                            <TextBlock Text="NAME" Foreground="#7D9BFF" FontSize="12" FontWeight="Bold"/><TextBox x:Name="NameBox" Margin="0,5,0,12"/>
                            <TextBlock Text="LOCATION" Foreground="#7D9BFF" FontSize="12" FontWeight="Bold"/><TextBox x:Name="LocationBox" Margin="0,5,0,12"/>
                            <TextBlock Text="WINDOWS TIMEZONE" Foreground="#7D9BFF" FontSize="12" FontWeight="Bold"/><ComboBox x:Name="TimeZoneBox" IsEditable="True" IsTextSearchEnabled="True" Margin="0,5,0,12"/>
                            <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0"><TextBlock Text="SHORT LABEL" Foreground="#7D9BFF" FontSize="12" FontWeight="Bold"/><TextBox x:Name="ZoneLabelBox" Margin="0,5,0,12"/></StackPanel>
                                <StackPanel Grid.Column="2"><TextBlock Text="ACCENT COLOR" Foreground="#7D9BFF" FontSize="12" FontWeight="Bold"/><TextBox x:Name="ColorBox" Margin="0,5,0,12"/></StackPanel>
                            </Grid>
                            <CheckBox x:Name="CustomHoursBox" Content="Use custom working hours" Margin="0,2,0,8"/>
                            <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0"><TextBlock Text="START" Foreground="#7D9BFF" FontSize="12" FontWeight="Bold"/><TextBox x:Name="PersonStartBox" Margin="0,5,0,0"/></StackPanel>
                                <StackPanel Grid.Column="2"><TextBlock Text="END" Foreground="#7D9BFF" FontSize="12" FontWeight="Bold"/><TextBox x:Name="PersonEndBox" Margin="0,5,0,0"/></StackPanel>
                            </Grid>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </TabItem>
        </TabControl>
        <Grid Grid.Row="2" Margin="0,18,0,0">
            <TextBlock x:Name="ErrorText" Foreground="#FF8B91" FontSize="13" VerticalAlignment="Center" TextWrapping="Wrap"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="CancelButton" Content="Cancel" MinWidth="86" Margin="0,0,9,0"/>
                <Button x:Name="SaveButton" Content="Save changes" MinWidth="120" Background="#4776E6" BorderBrush="#5D8BFA"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
'@

    $settings = [Windows.Markup.XamlReader]::Parse($settingsXaml)
    $settings.Owner = $script:Window
    $script:SettingsTitleBox = $settings.FindName('TitleBox')
    $script:Settings24HourBox = $settings.FindName('Hour24Box')
    $script:SettingsSecondsBox = $settings.FindName('SecondsBox')
    $script:SettingsDayOffsetBox = $settings.FindName('DayOffsetBox')
    $script:SettingsStatusBox = $settings.FindName('StatusBox')
    $script:SettingsDefaultStartBox = $settings.FindName('DefaultStartBox')
    $script:SettingsDefaultEndBox = $settings.FindName('DefaultEndBox')
    $script:SettingsPeopleList = $settings.FindName('PeopleList')
    $script:SettingsPersonPanel = $settings.FindName('PersonPanel')
    $script:SettingsNameBox = $settings.FindName('NameBox')
    $script:SettingsLocationBox = $settings.FindName('LocationBox')
    $script:SettingsTimeZoneBox = $settings.FindName('TimeZoneBox')
    $script:SettingsZoneLabelBox = $settings.FindName('ZoneLabelBox')
    $script:SettingsColorBox = $settings.FindName('ColorBox')
    $script:SettingsCustomHoursBox = $settings.FindName('CustomHoursBox')
    $script:SettingsPersonStartBox = $settings.FindName('PersonStartBox')
    $script:SettingsPersonEndBox = $settings.FindName('PersonEndBox')
    $errorText = $settings.FindName('ErrorText')
    $addButton = $settings.FindName('AddPersonButton')
    $removeButton = $settings.FindName('RemovePersonButton')
    $saveButton = $settings.FindName('SaveButton')
    $cancelButton = $settings.FindName('CancelButton')

    $script:SettingsTitleBox.Text = [string]$script:Config.display.title
    $script:Settings24HourBox.IsChecked = [bool]$script:Config.display.use24HourTime
    $script:SettingsSecondsBox.IsChecked = [bool]$script:Config.display.showSeconds
    $script:SettingsDayOffsetBox.IsChecked = [bool]$script:Config.display.showDayOffset
    $script:SettingsStatusBox.IsChecked = [bool]$script:Config.display.showStatus
    $script:SettingsDefaultStartBox.Text = [string]$script:Config.workingHours.start
    $script:SettingsDefaultEndBox.Text = [string]$script:Config.workingHours.end
    $script:SettingsTimeZoneBox.ItemsSource = @([TimeZoneInfo]::GetSystemTimeZones() | ForEach-Object { $_.Id })

    $script:SettingsPeopleList.Add_SelectionChanged({
        if ($script:SettingsLoading) { return }
        $errorText.Text = ''
        Update-SettingsPersonFromFields
        $script:SettingsSelectedIndex = $script:SettingsPeopleList.SelectedIndex
        Show-SettingsPersonFields $script:SettingsSelectedIndex
    })
    $script:SettingsCustomHoursBox.Add_Click({
        $enabled = [bool]$script:SettingsCustomHoursBox.IsChecked
        $script:SettingsPersonStartBox.IsEnabled = $enabled
        $script:SettingsPersonEndBox.IsEnabled = $enabled
    })
    $addButton.Add_Click({
        $errorText.Text = ''
        Update-SettingsPersonFromFields
        $newPerson = [pscustomobject]@{
            id = "coworker-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            name = 'New coworker'
            location = 'City'
            timeZoneId = [TimeZoneInfo]::Local.Id
            timeZoneLabel = 'LOCAL'
            color = '#FF7D9BFF'
        }
        [void]$script:SettingsPeople.Add($newPerson)
        Refresh-SettingsPeopleList ($script:SettingsPeople.Count - 1)
    })
    $removeButton.Add_Click({
        if ($script:SettingsPeople.Count -le 1) {
            $errorText.Text = 'The widget needs at least one coworker.'
            return
        }
        $index = $script:SettingsPeopleList.SelectedIndex
        if ($index -ge 0) {
            $errorText.Text = ''
            $script:SettingsPeople.RemoveAt($index)
            $script:SettingsSelectedIndex = -1
            Refresh-SettingsPeopleList ([Math]::Min($index, $script:SettingsPeople.Count - 1))
        }
    })
    $cancelButton.Add_Click({ $settings.DialogResult = $false })
    $saveButton.Add_Click({
        try {
            $errorText.Text = ''
            Save-SettingsConfiguration
            $settings.DialogResult = $true
        }
        catch { $errorText.Text = $_.Exception.Message }
    })

    Refresh-SettingsPeopleList 0
    if ($settings.ShowDialog()) { Reload-Configuration }
}
