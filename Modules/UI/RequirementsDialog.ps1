# =============================================================================
# RequirementsDialog — Modal WPF dialog explaining requirements and features
# Dot-sourced in main scope by HorizonDocTool.ps1
# Requires: PresentationFramework assembly (loaded by main script)
# =============================================================================

function Show-RequirementsDialog {
    param(
        [System.Windows.Window]$Owner = $null
    )

    [xml]$dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Requirements &amp; Features"
        Width="620"
        MinWidth="520"
        Height="720"
        MinHeight="500"
        WindowStartupLocation="CenterOwner"
        ResizeMode="CanResize"
        Background="#1E1E2E"
        FontFamily="Segoe UI"
        FontSize="13"
        Foreground="#CDD6F4">

    <Window.Resources>
        <Style x:Key="HeadingStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#89B4FA"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,14,0,5"/>
        </Style>
        <Style x:Key="SubHeadingStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,8,0,3"/>
        </Style>
        <Style x:Key="BodyStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="LineHeight" Value="18"/>
            <Setter Property="Margin" Value="0,0,0,3"/>
        </Style>
        <Style x:Key="TagStyle" TargetType="Border">
            <Setter Property="CornerRadius" Value="3"/>
            <Setter Property="Padding" Value="5,2"/>
            <Setter Property="Margin" Value="0,0,4,4"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <ScrollViewer Grid.Row="0"
                      VerticalScrollBarVisibility="Auto"
                      HorizontalScrollBarVisibility="Disabled"
                      Padding="20,16,20,8">
            <StackPanel>

                <!-- Title -->
                <TextBlock Text="Horizon Documentation Tool"
                           FontSize="16" FontWeight="SemiBold" Foreground="#CDD6F4"
                           Margin="0,0,0,2"/>
                <TextBlock Text="Omnissa Horizon VDI — Automated Report Generator"
                           FontSize="11" Foreground="#585B70" Margin="0,0,0,4"/>

                <!-- Intro -->
                <Border Background="#313244" CornerRadius="6" Padding="12,10" Margin="0,6,0,0">
                    <TextBlock TextWrapping="Wrap" Foreground="#CDD6F4" FontSize="11.5" LineHeight="18">
Dieses Tool verbindet sich mit einem Omnissa Horizon Connection Server und erstellt automatisch einen vollständigen HTML-Bericht der gesamten Horizon-Umgebung — inklusive Infrastruktur, Pools, Berechtigungen, Zertifikaten und mehr. Der Bericht kann optional als PDF exportiert werden.
                    </TextBlock>
                </Border>

                <!-- ═══════════════════════════════════════════════════════════ -->
                <!-- REQUIREMENTS                                                -->
                <!-- ═══════════════════════════════════════════════════════════ -->
                <TextBlock Text="VORAUSSETZUNGEN" Style="{StaticResource HeadingStyle}"/>

                <!-- Mandatory -->
                <TextBlock Text="✔  Pflicht (immer erforderlich)" Style="{StaticResource SubHeadingStyle}"/>
                <Border Background="#1E3A2F" CornerRadius="5" Padding="12,8" Margin="0,0,0,6">
                    <StackPanel>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run FontWeight="SemiBold" Foreground="#A6E3A1">PowerShell 5.1</Run>
                            <Run Foreground="#A6ADC8"> — Mindestversion. Läuft auf Windows 10/11 und Windows Server 2016+.</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run FontWeight="SemiBold" Foreground="#A6E3A1">Omnissa Horizon PowerShell Module</Run>
                            <Run Foreground="#A6ADC8"> — Im Unterordner </Run>
                            <Run FontFamily="Consolas" Foreground="#CDD6F4">Omnissa Horizon Modules\</Run>
                            <Run Foreground="#A6ADC8"> mitgeliefert. Kein separates Install nötig.</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run FontWeight="SemiBold" Foreground="#A6E3A1">Horizon Administrator-Konto</Run>
                            <Run Foreground="#A6ADC8"> — Leseberechtigung auf den Connection Server (Read-Only Administrator reicht aus).</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run FontWeight="SemiBold" Foreground="#A6E3A1">Netzwerkzugriff</Run>
                            <Run Foreground="#A6ADC8"> — HTTPS (Port 443) zum Connection Server.</Run>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- vCenter optional -->
                <TextBlock Text="☁  Optional: vCenter-Zugangsdaten" Style="{StaticResource SubHeadingStyle}"/>
                <Border Background="#1E2A3A" CornerRadius="5" Padding="12,8" Margin="0,0,0,6">
                    <StackPanel>
                        <TextBlock Style="{StaticResource BodyStyle}" Foreground="#A6ADC8">
Wenn vCenter-Credentials angegeben werden, werden folgende zusätzliche Daten erfasst:
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run FontWeight="SemiBold" Foreground="#89B4FA">VMware PowerCLI</Run>
                            <Run Foreground="#A6ADC8"> — Im Unterordner </Run>
                            <Run FontFamily="Consolas" Foreground="#CDD6F4">VMware PowerCLI Modules\</Run>
                            <Run Foreground="#A6ADC8"> mitgeliefert.</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#89B4FA">•  Internal Template VMs</Run>
                            <Run Foreground="#A6ADC8"> — cp-template / cp-replica VMs mit Golden Image und Snapshot-Zuordnung</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#89B4FA">•  Eingeschaltete VMs</Run>
                            <Run Foreground="#A6ADC8"> — Anzahl laufender VMs pro Desktop Pool / Farm</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#89B4FA">•  Golden Image Details</Run>
                            <Run Foreground="#A6ADC8"> — IP-Adresse, Betriebssystem, installierte Software (via PSRemoting)</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#89B4FA">•  ESXi Hosts</Run>
                            <Run Foreground="#A6ADC8"> — NVIDIA vGPU Package-Version je Host</Run>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- PSRemoting optional -->
                <TextBlock Text="🔧  Optional: PSRemoting auf Connection Servern" Style="{StaticResource SubHeadingStyle}"/>
                <Border Background="#2A1E2A" CornerRadius="5" Padding="12,8" Margin="0,0,0,6">
                    <StackPanel>
                        <TextBlock Style="{StaticResource BodyStyle}" Foreground="#A6ADC8">
Wenn PSRemoting (WinRM) auf den Connection Servern aktiviert ist, werden zusätzlich erfasst:
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  locked.properties</Run>
                            <Run Foreground="#A6ADC8"> — Gesperrte Horizon-Konfigurationsparameter je Connection Server</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  Lokale Administratoren</Run>
                            <Run Foreground="#A6ADC8"> — Mitglieder der lokalen Admin-Gruppe auf jedem Connection Server</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  Letzter Windows-Patch</Run>
                            <Run Foreground="#A6ADC8"> — Datum des zuletzt installierten Windows-Updates</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  Freier Festplattenspeicher</Run>
                            <Run Foreground="#A6ADC8"> — Verfügbarer Speicher auf System-Laufwerk (C:) je Server</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}" Margin="0,6,0,0">
                            <Run FontWeight="SemiBold" Foreground="#CDD6F4">Aktivieren mit:</Run>
                            <Run FontFamily="Consolas" Foreground="#F9E2AF">  Enable-PSRemoting -Force</Run>
                            <Run Foreground="#A6ADC8"> (auf jedem Connection Server, als Administrator)</Run>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- PSRemoting Golden Image Guest Scan -->
                <TextBlock Text="🔍  Optional: PSRemoting auf Golden Images (Guest Scan)" Style="{StaticResource SubHeadingStyle}"/>
                <Border Background="#2A1E2A" CornerRadius="5" Padding="12,8" Margin="0,0,0,6">
                    <StackPanel>
                        <TextBlock Style="{StaticResource BodyStyle}" Foreground="#A6ADC8">
Wenn im Feld "Golden Image Guest Scan" separate Credentials angegeben werden, verbindet sich das Tool per PSRemoting direkt mit jeder Golden Image VM und liest folgende Daten aus (nur bei eingeschalteten VMs):
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}" Margin="0,4,0,0">
                            <Run Foreground="#CBA6F7">•  IP-Adresse(n)</Run>
                            <Run Foreground="#A6ADC8"> — Alle aktiven IPv4-Adressen der VM (außer Loopback und APIPA)</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  Horizon Agent</Run>
                            <Run Foreground="#A6ADC8"> — Installierte Version (Omnissa/VMware Horizon Agent)</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  App Volumes Agent</Run>
                            <Run Foreground="#A6ADC8"> — Installierte Version (Omnissa/VMware App Volumes Agent)</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  Dynamic Environment Manager (DEM)</Run>
                            <Run Foreground="#A6ADC8"> — Installierte Version</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  FSLogix</Run>
                            <Run Foreground="#A6ADC8"> — Installierte Version (Microsoft FSLogix Apps)</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  VMware Tools</Run>
                            <Run Foreground="#A6ADC8"> — Installierte Version (VMware Tools / Open VM Tools)</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  NVIDIA Grafiktreiber</Run>
                            <Run Foreground="#A6ADC8"> — Version des vGPU Guest Drivers (GRID / Display Driver), falls installiert</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  Letzter Windows-Patch</Run>
                            <Run Foreground="#A6ADC8"> — Datum des zuletzt installierten Windows-Updates</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  Festplattenspeicher (C:)</Run>
                            <Run Foreground="#A6ADC8"> — Gesamtgröße und freier Speicher des System-Laufwerks</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run Foreground="#CBA6F7">•  Lokale Administratoren</Run>
                            <Run Foreground="#A6ADC8"> — Mitglieder der lokalen Administrators-Gruppe inkl. Typ (User/Group)</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}" Margin="0,6,0,0">
                            <Run FontWeight="SemiBold" Foreground="#CDD6F4">Voraussetzung:</Run>
                            <Run Foreground="#A6ADC8"> VMware Tools muss laufen (für Hostname-Auflösung), VM muss eingeschaltet sein, PSRemoting aktiviert:</Run>
                        </TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}">
                            <Run FontFamily="Consolas" Foreground="#F9E2AF">  Enable-PSRemoting -Force</Run>
                            <Run Foreground="#A6ADC8"> (auf jeder Golden Image VM, als Administrator)</Run>
                        </TextBlock>
                    </StackPanel>
                </Border>

                <!-- ═══════════════════════════════════════════════════════════ -->
                <!-- FEATURES                                                    -->
                <!-- ═══════════════════════════════════════════════════════════ -->
                <TextBlock Text="FUNKTIONSUMFANG DES REPORTS" Style="{StaticResource HeadingStyle}"/>

                <TextBlock Style="{StaticResource BodyStyle}" Margin="0,0,0,8">
Der generierte HTML-Report enthält folgende Abschnitte:
                </TextBlock>

                <!-- Feature blocks -->
                <Border Background="#252535" CornerRadius="5" Padding="12,8" Margin="0,0,0,5">
                    <StackPanel>
                        <TextBlock Text="🏢  Infrastruktur" Style="{StaticResource SubHeadingStyle}" Margin="0,0,0,4"/>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Connection Servers</Run><Run Foreground="#A6ADC8"> — Version, Status, Zertifikat-Ablauf, Build-Nummer, PSRemoting-Daten (locked.properties, Admins, Patch, Disk)</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Gateways / UAGs</Run><Run Foreground="#A6ADC8"> — Alle konfigurierten Access Points mit Verbindungsstatus und Zertifikat-Ablaufdaten</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">vCenter</Run><Run Foreground="#A6ADC8"> — Verbundene vCenter-Server, Version, Zertifikat</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Event-Datenbank</Run><Run Foreground="#A6ADC8"> — SQL-Datenbank-Konfiguration für Horizon Events</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Syslog</Run><Run Foreground="#A6ADC8"> — Konfigurierte Syslog-Server</Run></TextBlock>
                    </StackPanel>
                </Border>

                <Border Background="#252535" CornerRadius="5" Padding="12,8" Margin="0,0,0,5">
                    <StackPanel>
                        <TextBlock Text="👥  Benutzer &amp; Berechtigungen" Style="{StaticResource SubHeadingStyle}" Margin="0,0,0,4"/>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">AD-Domänen</Run><Run Foreground="#A6ADC8"> — Verbundene Active Directory Domains</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">IC Domain Accounts</Run><Run Foreground="#A6ADC8"> — Instant Clone Domain Service Accounts</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Administratoren</Run><Run Foreground="#A6ADC8"> — Horizon Admin-Rollen mit Mitgliederanzahl und aufklappbarer Benutzerliste</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">SAML-Authenticators</Run><Run Foreground="#A6ADC8"> — Konfigurierte SAML-Anbieter (z.B. für True SSO)</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">True SSO</Run><Run Foreground="#A6ADC8"> — True SSO Enrollment Server-Konfiguration</Run></TextBlock>
                    </StackPanel>
                </Border>

                <Border Background="#252535" CornerRadius="5" Padding="12,8" Margin="0,0,0,5">
                    <StackPanel>
                        <TextBlock Text="🖥  Pools, Farms &amp; Entitlements" Style="{StaticResource SubHeadingStyle}" Margin="0,0,0,4"/>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Desktop Pools</Run><Run Foreground="#A6ADC8"> — Alle Instant Clone / Full Clone Pools mit Typ, Protokoll, vCenter-Zuordnung und laufenden VMs</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">RDS Farms</Run><Run Foreground="#A6ADC8"> — RDS-basierte Server-Farms mit Konfigurationsdetails</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Application Pools</Run><Run Foreground="#A6ADC8"> — Veröffentlichte Anwendungen mit Berechtigungsgruppen (aufklappbar)</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Global Entitlements</Run><Run Foreground="#A6ADC8"> — Cloud Pod Architecture Berechtigungen mit aufklappbaren AD-Gruppen</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Local Desktop Entitlements</Run><Run Foreground="#A6ADC8"> — Lokale Desktop-Berechtigungen mit Mitgliederanzahl und Benutzer-Drill-down</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Local App Entitlements</Run><Run Foreground="#A6ADC8"> — Lokale Anwendungs-Berechtigungen analog Desktop Entitlements</Run></TextBlock>
                    </StackPanel>
                </Border>

                <Border Background="#252535" CornerRadius="5" Padding="12,8" Margin="0,0,0,5">
                    <StackPanel>
                        <TextBlock Text="💿  Golden Images &amp; VMs" Style="{StaticResource SubHeadingStyle}" Margin="0,0,0,4"/>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Golden Images</Run><Run Foreground="#A6ADC8"> — Master-VMs mit aktuellem Snapshot, zugeordnetem Pool und IP (via PSRemoting)</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Internal Template VMs</Run><Run Foreground="#A6ADC8"> — cp-template / cp-replica Paare aus vCenter, Pool-Zuordnung, fehlende Einträge rot markiert und sortiert ans Ende</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Datastores</Run><Run Foreground="#A6ADC8"> — Genutzter und freier Speicher je Datastore mit Auslastungsbalken</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">ESXi Hosts</Run><Run Foreground="#A6ADC8"> — Hosts mit Version, CPU/RAM-Auslastung, NVIDIA vGPU Package-Version</Run></TextBlock>
                    </StackPanel>
                </Border>

                <Border Background="#252535" CornerRadius="5" Padding="12,8" Margin="0,0,0,5">
                    <StackPanel>
                        <TextBlock Text="⚙  Einstellungen &amp; Policies" Style="{StaticResource SubHeadingStyle}" Margin="0,0,0,4"/>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">General Settings</Run><Run Foreground="#A6ADC8"> — Globale Horizon-Konfigurationsparameter</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Global Policies</Run><Run Foreground="#A6ADC8"> — USB, Clipboard, Printing und weitere globale Richtlinien</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Environment Properties</Run><Run Foreground="#A6ADC8"> — Horizon-Umgebungsvariablen und Build-Informationen</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Cloud Pod Architecture (CPA)</Run><Run Foreground="#A6ADC8"> — Pods, Sites und Inter-Pod-Verbindungen</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Lizenz</Run><Run Foreground="#A6ADC8"> — Lizenzstatus, Ablaufdatum und Health-Indikator</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">App Volumes Manager</Run><Run Foreground="#A6ADC8"> — Verbundene App Volumes Manager mit Status und Version</Run></TextBlock>
                    </StackPanel>
                </Border>

                <Border Background="#252535" CornerRadius="5" Padding="12,8" Margin="0,0,0,5">
                    <StackPanel>
                        <TextBlock Text="📄  Report &amp; Export" Style="{StaticResource SubHeadingStyle}" Margin="0,0,0,4"/>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">HTML-Report</Run><Run Foreground="#A6ADC8"> — Vollständiger, selbstenthaltener HTML-Bericht, lokal ohne Internet-Verbindung öffenbar</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">PDF-Export</Run><Run Foreground="#A6ADC8"> — Optionaler PDF-Export über mitgeliefertes wkhtmltopdf (Checkbox "Export as PDF" aktivieren)</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Titelseite</Run><Run Foreground="#A6ADC8"> — Optionale Unternehmens- und Kontaktdaten via "Company Info..." eintragen</Run></TextBlock>
                        <TextBlock Style="{StaticResource BodyStyle}"><Run Foreground="#89B4FA">Kollapsierbare Sektionen</Run><Run Foreground="#A6ADC8"> — Alle Bereiche im Report ein-/ausklappbar für übersichtliche Darstellung</Run></TextBlock>
                    </StackPanel>
                </Border>

                <!-- Bottom margin -->
                <Border Height="8"/>

            </StackPanel>
        </ScrollViewer>

        <!-- Close button row -->
        <Border Grid.Row="1" Background="#181825" Padding="16,10">
            <Button x:Name="BtnClose"
                    Content="Schließen"
                    MinWidth="100"
                    HorizontalAlignment="Right"
                    Background="#89B4FA"
                    Foreground="#1E1E2E"
                    BorderThickness="0"
                    Padding="14,7"
                    FontWeight="SemiBold"
                    Cursor="Hand">
                <Button.Template>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#B4BEFE"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Button.Template>
            </Button>
        </Border>

    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $dialogXaml
    $dlg = [Windows.Markup.XamlReader]::Load($reader)

    if ($Owner) { $dlg.Owner = $Owner }

    $btnClose = $dlg.FindName("BtnClose")
    $btnClose.Add_Click({ $dlg.Close() })

    $dlg.ShowDialog() | Out-Null
}
