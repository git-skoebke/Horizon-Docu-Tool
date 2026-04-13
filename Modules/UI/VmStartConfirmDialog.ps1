# =============================================================================
# VmStartConfirmDialog — Modal WPF dialog asking whether to start a Golden Image VM
# Called from the Runspace via $window.Dispatcher.Invoke — result via synchronized table
# Dot-sourced in main scope by HorizonDocTool.ps1
# =============================================================================

function Show-VmStartConfirmDialog {
    <#
    .SYNOPSIS
        Opens a modal dialog asking whether to power on a Golden Image VM for a guest scan.
    .PARAMETER VmName
        Display name of the VM.
    .PARAMETER Owner
        Parent WPF window for modal centering.
    .OUTPUTS
        Hashtable: { Start = $true/$false; ApplyToAll = $true/$false }
        Start      — $true = power on, $false = skip
        ApplyToAll — $true = apply this choice to all remaining VMs without asking again
    #>
    param(
        [string]$VmName,
        [System.Windows.Window]$Owner = $null
    )

    [xml]$dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Golden Image — VM starten?"
        Width="460"
        MinWidth="380"
        SizeToContent="Height"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="#1E1E2E"
        FontFamily="Segoe UI"
        FontSize="13"
        Foreground="#CDD6F4">

    <StackPanel Margin="20,18,20,20">

        <!-- Icon + heading -->
        <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
            <TextBlock Text="💿" FontSize="22" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <StackPanel VerticalAlignment="Center">
                <TextBlock Text="VM für Guest Scan starten?"
                           FontSize="14" FontWeight="SemiBold" Foreground="#CDD6F4"/>
                <TextBlock Text="Softwareversionen können nur bei eingeschalteter VM gelesen werden."
                           FontSize="11" Foreground="#585B70" Margin="0,2,0,0" TextWrapping="Wrap"/>
            </StackPanel>
        </StackPanel>

        <!-- VM name box -->
        <Border Background="#313244" CornerRadius="5" Padding="12,8" Margin="0,0,0,14">
            <StackPanel>
                <TextBlock Text="Golden Image VM:" FontSize="11" Foreground="#A6ADC8" Margin="0,0,0,3"/>
                <TextBlock x:Name="TxtVmName"
                           FontSize="12" FontWeight="SemiBold" Foreground="#89B4FA"
                           TextWrapping="Wrap"/>
            </StackPanel>
        </Border>

        <!-- Info text -->
        <TextBlock TextWrapping="Wrap" Foreground="#A6ADC8" FontSize="11" LineHeight="18" Margin="0,0,0,14">
Die VM wird eingeschaltet, der Guest Scan durchgeführt und danach automatisch wieder heruntergefahren.
Erst wenn die VM vollständig gestoppt wurde, wird die nächste VM gestartet.
        </TextBlock>

        <!-- Apply to all checkbox -->
        <Border Background="#252535" CornerRadius="5" Padding="10,8" Margin="0,0,0,16">
            <CheckBox x:Name="ChkApplyToAll"
                      Foreground="#CDD6F4"
                      FontSize="12"
                      IsChecked="False"
                      Cursor="Hand">
                <TextBlock TextWrapping="Wrap">
                    <Run FontWeight="SemiBold">Für alle VMs übernehmen</Run>
                    <Run Foreground="#A6ADC8"> — diese Auswahl ohne weitere Nachfragen für alle verbleibenden Golden Images anwenden</Run>
                </TextBlock>
            </CheckBox>
        </Border>

        <!-- Buttons -->
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnSkip"
                    Content="Überspringen"
                    MinWidth="110"
                    Background="#45475A" Foreground="#CDD6F4"
                    BorderThickness="0" Padding="12,7"
                    Margin="0,0,8,0" Cursor="Hand">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#585B70"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Button.Template>
            </Button>
            <Button x:Name="BtnStart"
                    Content="▶  VM starten"
                    MinWidth="110"
                    Background="#A6E3A1" Foreground="#1E1E2E"
                    BorderThickness="0" Padding="12,7"
                    FontWeight="SemiBold" Cursor="Hand">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#C3FAC3"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Button.Template>
            </Button>
        </StackPanel>

    </StackPanel>
</Window>
"@

    $reader    = New-Object System.Xml.XmlNodeReader $dialogXaml
    $dlg       = [Windows.Markup.XamlReader]::Load($reader)

    if ($Owner) { $dlg.Owner = $Owner }

    # Set VM name label
    $dlg.FindName("TxtVmName").Text = $VmName

    $chkApplyToAll = $dlg.FindName("ChkApplyToAll")
    $btnStart      = $dlg.FindName("BtnStart")
    $btnSkip       = $dlg.FindName("BtnSkip")

    $result = @{ Start = $false; ApplyToAll = $false }

    $btnStart.Add_Click({
        $result.Start      = $true
        $result.ApplyToAll = ($chkApplyToAll.IsChecked -eq $true)
        $dlg.Close()
    }.GetNewClosure())

    $btnSkip.Add_Click({
        $result.Start      = $false
        $result.ApplyToAll = ($chkApplyToAll.IsChecked -eq $true)
        $dlg.Close()
    }.GetNewClosure())

    # If closed via X button — treat as skip, no apply-to-all
    $dlg.ShowDialog() | Out-Null

    return $result
}
