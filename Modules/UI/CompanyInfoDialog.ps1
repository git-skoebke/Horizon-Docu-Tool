# =============================================================================
# CompanyInfoDialog — Modal WPF dialog for optional company/contact details
# Dot-sourced in main scope by HorizonDocTool.ps1
# Requires: PresentationFramework assembly (loaded by main script)
# =============================================================================

function Show-CompanyInfoDialog {
    <#
    .SYNOPSIS
        Opens a modal dialog for entering company and contact information.
    .PARAMETER CurrentData
        Hashtable with existing values to pre-fill the dialog fields.
    .PARAMETER Owner
        The parent WPF window (for modal centering).
    .OUTPUTS
        Hashtable with field values if Save was clicked, $null if Cancel/closed.
    #>
    param(
        [hashtable]$CurrentData = @{},
        [System.Windows.Window]$Owner = $null
    )

    [xml]$dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Company Information"
        Width="440"
        MinWidth="380"
        SizeToContent="Height"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="#1E1E2E"
        FontFamily="Segoe UI"
        FontSize="13"
        Foreground="#CDD6F4">

    <Window.Resources>
        <Style x:Key="DlgInputStyle" TargetType="TextBox">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="CaretBrush" Value="#CDD6F4"/>
            <Setter Property="SelectionBrush" Value="#89B4FA"/>
        </Style>
        <Style x:Key="DlgLabelStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Margin" Value="0,8,0,3"/>
        </Style>
    </Window.Resources>

    <StackPanel Margin="20,16,20,20">

        <TextBlock Text="Company &amp; Contact Information"
                   FontSize="15" FontWeight="SemiBold" Foreground="#89B4FA"
                   Margin="0,0,0,4"/>
        <TextBlock Text="All fields are optional. Data is shown on the PDF cover page."
                   FontSize="11" Foreground="#585B70" Margin="0,0,0,12"/>

        <TextBlock Text="Company Name" Style="{StaticResource DlgLabelStyle}"/>
        <TextBox x:Name="TxtCompanyName" Style="{StaticResource DlgInputStyle}"/>

        <TextBlock Text="Contact Person" Style="{StaticResource DlgLabelStyle}"/>
        <TextBox x:Name="TxtContactPerson" Style="{StaticResource DlgInputStyle}"/>

        <TextBlock Text="Position / Role" Style="{StaticResource DlgLabelStyle}"/>
        <TextBox x:Name="TxtContactRole" Style="{StaticResource DlgInputStyle}"/>

        <TextBlock Text="Street Address" Style="{StaticResource DlgLabelStyle}"/>
        <TextBox x:Name="TxtStreet" Style="{StaticResource DlgInputStyle}"/>

        <TextBlock Text="ZIP / City" Style="{StaticResource DlgLabelStyle}"/>
        <TextBox x:Name="TxtZipCity" Style="{StaticResource DlgInputStyle}"/>

        <TextBlock Text="Country" Style="{StaticResource DlgLabelStyle}"/>
        <TextBox x:Name="TxtCountry" Style="{StaticResource DlgInputStyle}"/>

        <TextBlock Text="Phone" Style="{StaticResource DlgLabelStyle}"/>
        <TextBox x:Name="TxtPhone" Style="{StaticResource DlgInputStyle}"/>

        <TextBlock Text="Email" Style="{StaticResource DlgLabelStyle}"/>
        <TextBox x:Name="TxtEmail" Style="{StaticResource DlgInputStyle}"/>

        <!-- Buttons -->
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="BtnDialogCancel" Content="Cancel" MinWidth="80"
                    Background="#45475A" Foreground="#CDD6F4" BorderThickness="0"
                    Padding="12,6" Margin="0,0,8,0" Cursor="Hand">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Button.Template>
            </Button>
            <Button x:Name="BtnDialogSave" Content="Save" MinWidth="80"
                    Background="#89B4FA" Foreground="#1E1E2E" BorderThickness="0"
                    Padding="12,6" FontWeight="SemiBold" Cursor="Hand">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Button.Template>
            </Button>
        </StackPanel>

    </StackPanel>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $dialogXaml
    $dlg = [Windows.Markup.XamlReader]::Load($reader)

    # Set owner for modal behavior
    if ($Owner) { $dlg.Owner = $Owner }

    # Get controls
    $fields = @{}
    foreach ($name in @("TxtCompanyName","TxtContactPerson","TxtContactRole",
                        "TxtStreet","TxtZipCity","TxtCountry","TxtPhone","TxtEmail")) {
        $fields[$name] = $dlg.FindName($name)
    }
    $btnSave   = $dlg.FindName("BtnDialogSave")
    $btnCancel = $dlg.FindName("BtnDialogCancel")

    # Pre-fill from existing data
    if ($CurrentData) {
        if ($CurrentData.CompanyName)    { $fields["TxtCompanyName"].Text    = $CurrentData.CompanyName }
        if ($CurrentData.ContactPerson)  { $fields["TxtContactPerson"].Text  = $CurrentData.ContactPerson }
        if ($CurrentData.ContactRole)    { $fields["TxtContactRole"].Text    = $CurrentData.ContactRole }
        if ($CurrentData.Street)         { $fields["TxtStreet"].Text         = $CurrentData.Street }
        if ($CurrentData.ZipCity)        { $fields["TxtZipCity"].Text        = $CurrentData.ZipCity }
        if ($CurrentData.Country)        { $fields["TxtCountry"].Text        = $CurrentData.Country }
        if ($CurrentData.Phone)          { $fields["TxtPhone"].Text          = $CurrentData.Phone }
        if ($CurrentData.Email)          { $fields["TxtEmail"].Text          = $CurrentData.Email }
    }

    # Result holder — use a mutable wrapper so the closure can write back
    $resultHolder = @{ Value = $null }

    $btnSave.Add_Click({
        $resultHolder.Value = @{
            CompanyName   = $fields["TxtCompanyName"].Text.Trim()
            ContactPerson = $fields["TxtContactPerson"].Text.Trim()
            ContactRole   = $fields["TxtContactRole"].Text.Trim()
            Street        = $fields["TxtStreet"].Text.Trim()
            ZipCity       = $fields["TxtZipCity"].Text.Trim()
            Country       = $fields["TxtCountry"].Text.Trim()
            Phone         = $fields["TxtPhone"].Text.Trim()
            Email         = $fields["TxtEmail"].Text.Trim()
        }
        $dlg.Close()
    }.GetNewClosure())

    $btnCancel.Add_Click({
        $dlg.Close()
    })

    # Show modal
    $dlg.ShowDialog() | Out-Null

    return $resultHolder.Value
}
