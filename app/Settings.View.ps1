# Steam Boot Switch V1.1 Preview - WPF visual redesign.
# The UI is opened on demand; no resident UI or polling process.
function New-SbsSettingsView($Config, [bool]$InstallerMode=$false) {
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
    $xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Steam Boot Switch - Settings (V1.1.1)" Width="1040" Height="740" MinWidth="890" MinHeight="660"
        Background="#090B10" Foreground="#F1F5FB" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Muted" Color="#A3B2C9"/>
    <Style x:Key="PageHeading" TargetType="TextBlock">
      <Setter Property="FontSize" Value="21"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
    </Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#141820"/>
      <Setter Property="BorderBrush" Value="#303846"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/><Setter Property="Padding" Value="15,13"/>
      <Setter Property="Margin" Value="0,0,0,11"/>
    </Style>
    <Style x:Key="MutedDescription" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="TextWrapping" Value="Wrap"/><Setter Property="FontSize" Value="12"/>
      <Setter Property="Margin" Value="0,2,0,0"/>
    </Style>
    <Style x:Key="Nav" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#ADC2D6"/>
      <Setter Property="BorderThickness" Value="0"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Padding" Value="14,10"/><Setter Property="Margin" Value="0,2,0,6"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="FontSize" Value="14"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="outline" Background="{TemplateBinding Background}" CornerRadius="9"
                  BorderThickness="1" BorderBrush="Transparent">
            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"
                              Margin="{TemplateBinding Padding}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="outline" Property="BorderBrush" Value="#556941"/></Trigger>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="outline" Property="BorderBrush" Value="#ACF75C"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalAlignment" Value="Right"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Margin" Value="16,0,4,0"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Border x:Name="track" Width="48" Height="27" CornerRadius="16" Background="#343A45" BorderThickness="1" BorderBrush="#657083">
            <Ellipse x:Name="thumb" Width="19" Height="19" Margin="3,0,0,0"
                     Fill="#DEE3EC" HorizontalAlignment="Left" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="track" Property="Background" Value="#A7F755"/>
              <Setter TargetName="track" Property="BorderBrush" Value="#A7F755"/>
              <Setter TargetName="thumb" Property="Fill" Value="#13230F"/>
              <Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right"/>
              <Setter TargetName="thumb" Property="Margin" Value="0,0,3,0"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="track" Property="Opacity" Value="0.35"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Number" TargetType="TextBox">
      <Setter Property="Background" Value="#0B111A"/><Setter Property="Foreground" Value="#ECF5FF"/>
      <Setter Property="BorderBrush" Value="#53657C"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,0"/><Setter Property="Width" Value="112"/>
      <Setter Property="Height" Value="40"/><Setter Property="FontSize" Value="14"/>
      <Setter Property="TextAlignment" Value="Left"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="HorizontalAlignment" Value="Right"/>
    </Style>
    <Style x:Key="ChoiceItem" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#EAF2FF"/><Setter Property="Background" Value="#0C1119"/>
      <Setter Property="Padding" Value="13,10"/>
      <Style.Triggers>
        <Trigger Property="IsHighlighted" Value="True"><Setter Property="Background" Value="#27353E"/><Setter Property="Foreground" Value="#A7F755"/></Trigger>
        <Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="#25372B"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Choice" TargetType="ComboBox">
      <Setter Property="Foreground" Value="#EAF2FF"/><Setter Property="Background" Value="#0C1119"/>
      <Setter Property="Width" Value="Auto"/><Setter Property="Height" Value="36"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource ChoiceItem}"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ComboBox">
          <Grid>
            <Border x:Name="comboBorder" CornerRadius="9" BorderThickness="1" BorderBrush="#4C6175" Background="#0B111B">
              <Grid Margin="14,0,14,0">
                <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Left" Margin="0,0,28,0"
                                  Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
                <Path Data="M 0 0 L 5 5 L 10 0" Stroke="#BFCCE1" StrokeThickness="1.8"
                      HorizontalAlignment="Right" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ToggleButton Focusable="False" Background="Transparent" BorderThickness="0"
                          IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
              <ToggleButton.Template><ControlTemplate TargetType="ToggleButton">
                <Border Background="Transparent"/>
              </ControlTemplate></ToggleButton.Template>
            </ToggleButton>
            <Popup x:Name="PART_Popup" AllowsTransparency="True" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" Focusable="False">
              <Border MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" Background="#0C1119"
                      BorderThickness="1" BorderBrush="#526178" CornerRadius="8" Padding="3">
                <ScrollViewer MaxHeight="240" CanContentScroll="True"><ItemsPresenter/></ScrollViewer>
              </Border>
            </Popup>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="comboBorder" Property="BorderBrush" Value="#A7F755"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="comboBorder" Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Background" Value="#ABF957"/><Setter Property="Foreground" Value="#101611"/>
      <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Padding" Value="19,10"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="buttonBorder" Background="{TemplateBinding Background}" CornerRadius="11">
            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="buttonBorder" Property="Background" Value="#C0FF80"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="buttonBorder" Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Secondary" TargetType="Button">
      <Setter Property="Background" Value="#262E3D"/><Setter Property="Foreground" Value="#E5F0FF"/>
      <Setter Property="BorderThickness" Value="0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Padding" Value="18,10"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border Background="{TemplateBinding Background}" CornerRadius="10" BorderBrush="#445165" BorderThickness="1">
          <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <DockPanel LastChildFill="True">
    <Grid DockPanel.Dock="Top" Height="100" ClipToBounds="True" Background="#06080D">
      <Ellipse Width="330" Height="210" HorizontalAlignment="Left" Margin="-130,-80,0,0" VerticalAlignment="Top" Opacity="0.78">
        <Ellipse.Fill><RadialGradientBrush><GradientStop Color="#313AE9" Offset="0"/><GradientStop Color="#142198" Offset="0.50"/><GradientStop Color="#0006090F" Offset="1"/></RadialGradientBrush></Ellipse.Fill>
      </Ellipse>
      <Ellipse Width="290" Height="180" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,-110,-70,0" Opacity="0.75">
        <Ellipse.Fill><RadialGradientBrush><GradientStop Color="#12E63C" Offset="0"/><GradientStop Color="#08721E" Offset="0.55"/><GradientStop Color="#0006090F" Offset="1"/></RadialGradientBrush></Ellipse.Fill>
      </Ellipse>
      <Ellipse Width="230" Height="100" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,240,-86" Opacity="0.50">
        <Ellipse.Fill><RadialGradientBrush><GradientStop Color="#BD1BC8" Offset="0"/><GradientStop Color="#68167A" Offset="0.45"/><GradientStop Color="#0006090F" Offset="1"/></RadialGradientBrush></Ellipse.Fill>
      </Ellipse>
      <Grid Margin="23,13,24,10">
        <Grid.ColumnDefinitions><ColumnDefinition Width="59"/><ColumnDefinition Width="*"/><ColumnDefinition Width="115"/></Grid.ColumnDefinitions>
        <Grid Grid.Column="0" Width="49" Height="49" VerticalAlignment="Center" HorizontalAlignment="Left">
          <Ellipse Width="47" Height="47" StrokeThickness="7">
            <Ellipse.Stroke><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#2EF5B2" Offset="0"/><GradientStop Color="#AFFF4A" Offset="0.52"/><GradientStop Color="#A44BFC" Offset="1"/></LinearGradientBrush></Ellipse.Stroke>
          </Ellipse>
          <Ellipse Width="22" Height="22" Fill="#A8FF55"/>
        </Grid>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock Text="STEAM BOOT SWITCH" FontWeight="SemiBold" Foreground="#BDFF83" FontSize="12" Margin="0,0,0,5"/>
          <TextBlock Text="Intuitive Steam Big Picture." FontSize="22" FontWeight="SemiBold" Margin="0,0,0,2"/>
          <TextBlock Text="Controller startup, Puck docking, and desktop settings." Foreground="#A4B7D2" FontSize="12"/>
        </StackPanel>
        <Border Grid.Column="2" Background="#17201B" CornerRadius="14" Padding="12,6"
                VerticalAlignment="Top" HorizontalAlignment="Right" Margin="0,4,0,0">
          <TextBlock Text="V1.1.1" Foreground="#C1FF89" FontSize="11"/>
        </Border>
      </Grid>
    </Grid>
    <Border DockPanel.Dock="Bottom" Background="#0F131B" BorderBrush="#2C3643" BorderThickness="0,1,0,0" Padding="24,8">
      <DockPanel LastChildFill="True">
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" VerticalAlignment="Center">
          <Button x:Name="CancelButton" Content="Close" Style="{StaticResource Secondary}" Margin="0,0,12,0"/>
          <Button x:Name="SaveButton" Content="Save and apply" Style="{StaticResource Primary}"/>
        </StackPanel>
        <TextBlock x:Name="FooterHint" Text="Undocking changes apply immediately. Other settings may restart controller monitoring."
                   Foreground="#A3B6CF" TextWrapping="Wrap" MaxWidth="610" VerticalAlignment="Center" FontSize="12" Margin="0,0,12,0"/>
      </DockPanel>
    </Border>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="205"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Border Grid.Column="0" Background="#0B0E14" BorderBrush="#26303B" BorderThickness="0,0,1,0" Padding="17,20">
        <DockPanel LastChildFill="True">
          <StackPanel DockPanel.Dock="Bottom" Margin="9,14,0,5">
            <TextBlock Text="GAME PROTECTION" Foreground="#788DA7" FontSize="11" Margin="0,0,0,8"/>
            <TextBlock Text="Automatic exit is blocked during active Steam games." Foreground="#A2B3C8" TextWrapping="Wrap" FontSize="12"/>
            <TextBlock x:Name="MonitorStatus" Text="Controller monitoring is running" Foreground="#A7F755" FontSize="11" TextWrapping="Wrap" Margin="0,13,0,0"/>
          </StackPanel>
          <StackPanel>
            <TextBlock Text="SETTINGS" Foreground="#8D9FB8" FontSize="11" Margin="9,0,0,15"/>
            <Button x:Name="NavStartup" Content="Startup and docking" Style="{StaticResource Nav}"/>
            <Button x:Name="NavPicture" Content="Big Picture" Style="{StaticResource Nav}"/>
            <Button x:Name="NavDesktop" Content="Steam window" Style="{StaticResource Nav}"/>
          </StackPanel>
        </DockPanel>
      </Border>
      <Grid Grid.Column="1" Margin="22,13,23,9">
        <ScrollViewer x:Name="PageStartup" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel Margin="0,0,7,3">
            <TextBlock Text="Startup and docking" Style="{StaticResource PageHeading}"/>
            <TextBlock Text="Configure Big Picture startup and Steam Controller docking." Foreground="{StaticResource Muted}" Margin="0,0,0,8"/>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Windows startup" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,7"/>
              <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0"><TextBlock Text="Open Big Picture at sign-in" FontWeight="SemiBold"/>
                  <TextBlock Text="Opens when a controller is connected. Steam must start with Windows." Style="{StaticResource MutedDescription}"/></StackPanel>
                <CheckBox x:Name="autoOpenOnStartup" Grid.Column="1" Style="{StaticResource Switch}" AutomationProperties.Name="Open Big Picture when a controller is connected at sign-in"/>
              </Grid>
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0"><TextBlock Text="Controller detection time" FontWeight="SemiBold"/>
                  <TextBlock Text="How long to check after sign-in (15 to 600 seconds)." Style="{StaticResource MutedDescription}"/></StackPanel>
                <TextBox x:Name="startupWindowSeconds" Grid.Column="1" Style="{StaticResource Number}"/>
              </Grid>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Steam Controller Puck" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,7"/>
              <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0"><TextBlock Text="Turn off controller when docked" FontWeight="SemiBold"/>
                  <TextBlock Text="Docking your Steam Controller on the Puck turns it off." Style="{StaticResource MutedDescription}"/></StackPanel>
                <CheckBox x:Name="autoPowerOffOnDock" Grid.Column="1" Style="{StaticResource Switch}" AutomationProperties.Name="Power off Steam Controller when docked"/>
              </Grid>
              <Border BorderThickness="0,1,0,0" BorderBrush="#2A3341" Padding="0,10,0,0"><StackPanel>
                <TextBlock Text="Open Big Picture after undocking" TextWrapping="Wrap" Margin="0,0,0,7" FontWeight="SemiBold"/>
                <ComboBox x:Name="undockBigPictureMode" Style="{StaticResource Choice}">
                  <ComboBoxItem Content="Off - open manually" Tag="Disabled"/>
                  <ComboBoxItem Content="When the controller connects" Tag="OnConnection"/>
                  <ComboBoxItem Content="Immediately after undocking" Tag="Immediate"/>
                </ComboBox>
                <TextBlock x:Name="UndockDescription" Style="{StaticResource MutedDescription}" Margin="0,6,0,0"/>
              </StackPanel></Border>
            </StackPanel></Border>
          </StackPanel>
        </ScrollViewer>
        <ScrollViewer x:Name="PagePicture" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Visibility="Collapsed">
          <StackPanel Margin="0,0,7,3">
            <TextBlock Text="Big Picture" Style="{StaticResource PageHeading}"/>
            <TextBlock Text="Choose what happens when controllers disconnect." Foreground="{StaticResource Muted}" Margin="0,0,0,8"/>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Automatic Big Picture exit" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,7"/>
              <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0"><TextBlock Text="Close Big Picture when the last controller disconnects" FontWeight="SemiBold" TextWrapping="Wrap"/>
                  <TextBlock Text="Steam stays running. Active games and fullscreen apps prevent automatic exit." Style="{StaticResource MutedDescription}"/></StackPanel>
                <CheckBox x:Name="autoExitOnDisconnect" Grid.Column="1" Style="{StaticResource Switch}" AutomationProperties.Name="Exit Big Picture after last controller disconnects"/>
              </Grid>
              <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0"><TextBlock Text="Wait before closing Big Picture" FontWeight="SemiBold"/>
                  <TextBlock Text="Seconds to allow reconnection (1 or more)." Style="{StaticResource MutedDescription}"/></StackPanel>
                <TextBox x:Name="disconnectGraceSeconds" Grid.Column="1" Style="{StaticResource Number}"/>
              </Grid>
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0"><TextBlock Text="Keep Big Picture open if I use the keyboard or mouse" TextWrapping="Wrap" FontWeight="SemiBold"/>
                  <TextBlock Text="Cancels the pending exit if you use the keyboard or mouse during the wait." Style="{StaticResource MutedDescription}"/></StackPanel>
                <CheckBox x:Name="mouseActivityCancelsExit" Grid.Column="1" Style="{StaticResource Switch}" AutomationProperties.Name="Cancel auto exit on keyboard or mouse activity"/>
              </Grid>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Known Steam behavior" FontSize="17" FontWeight="SemiBold" Margin="0,0,0,7"/>
              <TextBlock Text="Steam may briefly take focus from another app when Big Picture closes." Style="{StaticResource MutedDescription}"/>
            </StackPanel></Border>
          </StackPanel>
        </ScrollViewer>
        <ScrollViewer x:Name="PageDesktop" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Visibility="Collapsed">
          <StackPanel Margin="0,0,7,3">
            <TextBlock Text="Steam window" Style="{StaticResource PageHeading}"/>
            <TextBlock Text="Control Steam desktop window visibility and size." Foreground="{StaticResource Muted}" Margin="0,0,0,8"/>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Steam window visibility" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,7"/>
              <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0"><TextBlock Text="Hide the Steam window when Big Picture closes" FontWeight="SemiBold" TextWrapping="Wrap"/>
                  <TextBlock Text="Steam keeps running in the background." Style="{StaticResource MutedDescription}"/></StackPanel>
                <CheckBox x:Name="cleanupSteamWindow" Grid.Column="1" Style="{StaticResource Switch}" AutomationProperties.Name="Hide Steam desktop after Big Picture closes"/>
              </Grid>
              <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0"><TextBlock Text="Hide the Steam window when Big Picture opens" FontWeight="SemiBold" TextWrapping="Wrap"/></StackPanel>
                <CheckBox x:Name="preHideSteamDesktop" Grid.Column="1" Style="{StaticResource Switch}" AutomationProperties.Name="Hide Steam desktop while Big Picture opens"/>
              </Grid>
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0"><TextBlock Text="Delay before hiding Steam" FontWeight="SemiBold"/>
                  <TextBlock Text="Milliseconds (0 to 3000)" Style="{StaticResource MutedDescription}"/></StackPanel>
                <TextBox x:Name="cleanupDelayMs" Grid.Column="1" Style="{StaticResource Number}"/>
              </Grid>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Steam desktop window size" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,7"/>
              <TextBlock Text="Window size when Big Picture closes" FontWeight="SemiBold" Margin="0,0,0,7"/>
              <ComboBox x:Name="windowSizeMode" Style="{StaticResource Choice}" Margin="0,0,0,10">
                <ComboBoxItem Content="Keep previous size" Tag="Preserve"/><ComboBoxItem Content="Maximize" Tag="Maximize"/>
                <ComboBoxItem Content="Custom dimensions" Tag="Custom"/>
              </ComboBox>
              <Grid Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBlock Text="Custom width (pixels)" VerticalAlignment="Center"/>
                <TextBox x:Name="windowWidth" Grid.Column="1" Style="{StaticResource Number}"/>
              </Grid>
              <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBlock Text="Custom height (pixels)" VerticalAlignment="Center"/>
                <TextBox x:Name="windowHeight" Grid.Column="1" Style="{StaticResource Number}"/>
              </Grid>
            </StackPanel></Border>
          </StackPanel>
        </ScrollViewer>
      </Grid>
    </Grid>
  </DockPanel>
</Window>
'@
    $reader=New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window=[Windows.Markup.XamlReader]::Load($reader)
    $names=@('NavStartup','NavPicture','NavDesktop','PageStartup','PagePicture','PageDesktop','MonitorStatus','FooterHint','SaveButton','CancelButton','UndockDescription')
    foreach($key in $script:SbsDefaults.Keys) { $names += $key }
    $controls=@{}
    foreach($name in $names) {
        $c=$window.FindName($name)
        if ($null -eq $c) { throw "UI control missing: $name" }
        $controls[$name]=$c
    }
    foreach($key in $script:SbsDefaults.Keys) {
        $control=$controls[$key]
        if ($control -is [Windows.Controls.CheckBox]) { $control.IsChecked=[bool]$Config.$key }
        elseif($control -is [Windows.Controls.TextBox]) { $control.Text=[string]$Config.$key }
        elseif($control -is [Windows.Controls.ComboBox]) {
            foreach($item in $control.Items) { if($item.Tag -ceq $Config.$key) {$control.SelectedItem=$item;break} }
        }
    }
    $sections=@('Startup','Picture','Desktop')
    $navigate={param([string]$destination)
        foreach($s in $sections){
            $controls["Page$s"].Visibility=if($s -eq $destination){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
            $controls["Nav$s"].Background=if($s -eq $destination){[Windows.Media.BrushConverter]::new().ConvertFromString('#202A20')}else{[Windows.Media.Brushes]::Transparent}
            $controls["Nav$s"].Foreground=if($s -eq $destination){[Windows.Media.BrushConverter]::new().ConvertFromString('#ACFF6E')}else{[Windows.Media.BrushConverter]::new().ConvertFromString('#ADC2D6')}
        }
    }.GetNewClosure()
    foreach($s in $sections) {
        $target=$s
        $controls["Nav$s"].Add_Click(({ & $navigate $target }).GetNewClosure())
    }
    & $navigate 'Startup'
    $describe={
        $selected=$controls['undockBigPictureMode'].SelectedItem
        if($null -eq $selected){return}
        $controls['UndockDescription'].Text=switch([string]$selected.Tag) {
            'Disabled' {'Undocking will not open Big Picture. You can open it manually or at Windows sign-in.'}
            'OnConnection' {'Opens Big Picture when Steam detects the controller connecting after undocking.'}
            'Immediate' {'Opens Big Picture after undocking if Steam is running, without waiting for a new controller connection.'}
        }
    }.GetNewClosure()
    $controls['undockBigPictureMode'].Add_SelectionChanged($describe);& $describe
    $enable={
        $controls['startupWindowSeconds'].IsEnabled=($controls['autoOpenOnStartup'].IsChecked -eq $true)
        $enabled=($controls['autoExitOnDisconnect'].IsChecked -eq $true)
        $controls['disconnectGraceSeconds'].IsEnabled=$enabled
        $controls['mouseActivityCancelsExit'].IsEnabled=$enabled
        $clean=($controls['cleanupSteamWindow'].IsChecked -eq $true)
        foreach($key in @('preHideSteamDesktop','cleanupDelayMs','windowSizeMode')){$controls[$key].IsEnabled=$clean}
        $selected=$controls['windowSizeMode'].SelectedItem
        $custom=$clean -and $null -ne $selected -and $selected.Tag -eq 'Custom'
        $controls['windowWidth'].IsEnabled=$custom
        $controls['windowHeight'].IsEnabled=$custom
    }.GetNewClosure()
    foreach($key in @('autoOpenOnStartup','autoExitOnDisconnect','cleanupSteamWindow')) {
        $controls[$key].Add_Checked($enable)
        $controls[$key].Add_Unchecked($enable)
    }
    $controls['windowSizeMode'].Add_SelectionChanged($enable); & $enable
    $monitor=Get-Process -Name 'SteamBootSwitch' -ErrorAction SilentlyContinue
    $controls['MonitorStatus'].Text=if($monitor){'Controller monitoring is running'}else{'Controller monitoring is not running'}
    if($InstallerMode){$controls['FooterHint'].Text='Installer preview. Save settings without restarting the watcher.';$controls['SaveButton'].Content='Save choices'}
    $controls['CancelButton'].Add_Click(({ $window.DialogResult=$false }).GetNewClosure())
    return [pscustomobject]@{Window=$window;Controls=$controls;Save=$controls['SaveButton'];Cancel=$controls['CancelButton']}
}
function Get-SbsViewChoices($View) {
    $chosen=[pscustomobject]@{}
    $limits=@{startupWindowSeconds=@(15,600); disconnectGraceSeconds=@(1,[int]::MaxValue);cleanupDelayMs=@(0,3000);windowWidth=@(640,7680);windowHeight=@(480,4320)}
    foreach($key in $script:SbsDefaults.Keys) {
        $control=$View.Controls[$key]
        if($control -is [Windows.Controls.CheckBox]) {$v=[bool]$control.IsChecked}
        elseif($control -is [Windows.Controls.ComboBox]) {
            if ($null -eq $control.SelectedItem) { throw "Choose a value for $key." }
            $v=[string]$control.SelectedItem.Tag
        } else {
            [int]$parsed=0
            if(-not [int]::TryParse([string]$control.Text,[ref]$parsed)) {throw "Enter a whole number for $key."}
            if($parsed -lt $limits[$key][0] -or $parsed -gt $limits[$key][1]) {throw "$key must be between $($limits[$key][0]) and $($limits[$key][1])."}
            $v=$parsed
        }
        $chosen | Add-Member -NotePropertyName $key -NotePropertyValue $v
    }
    Assert-SbsConfig $chosen
    return $chosen
}
