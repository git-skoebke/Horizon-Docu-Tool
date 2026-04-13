# =============================================================================
# XAML definition — WPF window with all named controls
# Dot-sourced by HorizonDocTool.ps1 — exposes $xaml variable
# =============================================================================

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Horizon Documentation Tool"
        Width="560"
        MinWidth="520"
        Height="900"
        MinHeight="720"
        WindowStartupLocation="CenterScreen"
        WindowState="Maximized"
        ResizeMode="CanResize"
        Background="#1E1E2E"
        FontFamily="Segoe UI"
        FontSize="13"
        Foreground="#CDD6F4">

    <Window.Resources>
        <!-- Input TextBox style -->
        <Style x:Key="InputStyle" TargetType="TextBox">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="CaretBrush" Value="#CDD6F4"/>
            <Setter Property="SelectionBrush" Value="#89B4FA"/>
        </Style>

        <!-- PasswordBox style -->
        <Style x:Key="PwdStyle" TargetType="PasswordBox">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
            <Setter Property="CaretBrush" Value="#CDD6F4"/>
            <Setter Property="SelectionBrush" Value="#89B4FA"/>
        </Style>

        <!-- Green info button style -->
        <Style x:Key="GreenButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#A6E3A1"/>
            <Setter Property="Foreground" Value="#1E1E2E"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="10,5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#C3FAC3"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Primary accent button style -->
        <Style x:Key="AccentButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#89B4FA"/>
            <Setter Property="Foreground" Value="#1E1E2E"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#B4BEFE"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#45475A"/>
                                <Setter Property="Foreground" Value="#585B70"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Secondary/neutral button style -->
        <Style x:Key="NeutralButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#45475A"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#585B70"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#313244"/>
                                <Setter Property="Foreground" Value="#585B70"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Section label style -->
        <Style x:Key="LabelStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Margin" Value="0,8,0,3"/>
        </Style>

        <!-- Section header style -->
        <Style x:Key="SectionHeaderStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#89B4FA"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,12,0,6"/>
        </Style>

        <!-- Separator style -->
        <Style x:Key="SeparatorStyle" TargetType="Separator">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Margin" Value="0,6,0,0"/>
        </Style>
    </Window.Resources>

    <ScrollViewer VerticalScrollBarVisibility="Auto"
                  HorizontalScrollBarVisibility="Disabled"
                  Background="#1E1E2E">
        <StackPanel Margin="16,12,16,16">

            <!-- ============================================================ -->
            <!-- TITLE AREA                                                    -->
            <!-- ============================================================ -->
            <Grid Margin="0,0,0,8">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                    <TextBlock Text="Horizon Documentation Tool"
                               FontSize="16"
                               FontWeight="SemiBold"
                               Foreground="#CDD6F4"/>
                    <TextBlock Text="Omnissa Horizon VDI — Automated Report Generator"
                               FontSize="11"
                               Foreground="#585B70"
                               Margin="0,2,0,0"/>
                </StackPanel>
                <Button x:Name="BtnRequirements"
                        Grid.Column="1"
                        Content="ℹ  Requirements"
                        Style="{StaticResource GreenButtonStyle}"
                        VerticalAlignment="Center"
                        Margin="12,0,0,0"
                        MinWidth="120"/>
            </Grid>

            <Separator Style="{StaticResource SeparatorStyle}"/>

            <!-- ============================================================ -->
            <!-- CREDENTIALS — TabControl                                     -->
            <!-- ============================================================ -->
            <TextBlock Text="CREDENTIALS" Style="{StaticResource SectionHeaderStyle}"/>
            <TabControl Background="#1E1E2E"
                        BorderBrush="#45475A"
                        BorderThickness="1"
                        Padding="0"
                        Margin="0,0,0,0">
                <TabControl.Resources>
                    <Style TargetType="TabItem">
                        <Setter Property="Background"   Value="#313244"/>
                        <Setter Property="Foreground"   Value="#A6ADC8"/>
                        <Setter Property="BorderBrush"  Value="#45475A"/>
                        <Setter Property="Padding"      Value="12,5"/>
                        <Setter Property="FontSize"     Value="12"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="TabItem">
                                    <Border x:Name="TabBorder"
                                            Background="{TemplateBinding Background}"
                                            BorderBrush="{TemplateBinding BorderBrush}"
                                            BorderThickness="1,1,1,0"
                                            CornerRadius="4,4,0,0"
                                            Margin="0,0,2,0"
                                            Padding="{TemplateBinding Padding}">
                                        <ContentPresenter ContentSource="Header"
                                                          HorizontalAlignment="Center"
                                                          VerticalAlignment="Center"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsSelected" Value="True">
                                            <Setter TargetName="TabBorder" Property="Background" Value="#45475A"/>
                                            <Setter Property="Foreground" Value="#CDD6F4"/>
                                        </Trigger>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="TabBorder" Property="Background" Value="#3D3F55"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
                </TabControl.Resources>

                <!-- ── Tab 1: Horizon ─────────────────────────────────── -->
                <TabItem Header="Horizon">
                    <StackPanel Margin="10,10,10,10"
                                Background="#1E1E2E">
                        <TextBlock Text="Connection Server (FQDN or IP)" Style="{StaticResource LabelStyle}"/>
                        <TextBox x:Name="TxtServer"
                                 Style="{StaticResource InputStyle}"
                                 Tag="cs01.domain.local"/>
                        <TextBlock Text="Username" Style="{StaticResource LabelStyle}"/>
                        <TextBox x:Name="TxtUsername"
                                 Style="{StaticResource InputStyle}"
                                 Tag="DOMAIN\username or username"/>
                        <TextBlock Text="Password" Style="{StaticResource LabelStyle}"/>
                        <PasswordBox x:Name="PwdPassword"
                                     Style="{StaticResource PwdStyle}"/>
                        <TextBlock Text="Domain (optional)" Style="{StaticResource LabelStyle}"/>
                        <TextBox x:Name="TxtDomain"
                                 Style="{StaticResource InputStyle}"
                                 Tag="Leave empty to extract from username"/>
                        <StackPanel Margin="0,10,0,4">
                            <CheckBox x:Name="ChkIgnoreSsl"
                                      Content="Ignore SSL Certificate Errors"
                                      IsChecked="False"
                                      Foreground="#A6ADC8"
                                      FontSize="12"/>
                            <CheckBox x:Name="ChkSaveCredentials"
                                      IsChecked="False"
                                      Foreground="#A6ADC8"
                                      FontSize="12"
                                      Margin="0,6,0,0">
                                <CheckBox.Content>
                                    <TextBlock>
                                        <Run>Save Credentials</Run>
                                        <Run Foreground="#585B70" FontSize="11"> — encrypted with Windows DPAPI (current user only)</Run>
                                    </TextBlock>
                                </CheckBox.Content>
                            </CheckBox>
                        </StackPanel>
                    </StackPanel>
                </TabItem>

                <!-- ── Tab 2: vCenter / Guest ─────────────────────────── -->
                <TabItem Header="vCenter / Guest">
                    <StackPanel Margin="10,10,10,10"
                                Background="#1E1E2E">
                        <TextBlock Text="VCENTER" Style="{StaticResource SectionHeaderStyle}" Margin="0,0,0,4"/>
                        <TextBlock Text="vCenter Username (user@domain or DOMAIN\user)" Style="{StaticResource LabelStyle}"/>
                        <TextBox x:Name="TxtVcUser"
                                 Style="{StaticResource InputStyle}"
                                 Tag="administrator@vsphere.local"/>
                        <TextBlock Text="vCenter Password" Style="{StaticResource LabelStyle}"/>
                        <PasswordBox x:Name="PwdVcPassword" Style="{StaticResource PwdStyle}"/>
                        <TextBlock Text="Optional — enables cp-template/replica lookup and powered-on VM counts"
                                   Foreground="#585B70" FontSize="10" Margin="0,2,0,12"/>

                        <TextBlock Text="GOLDEN IMAGE GUEST SCAN" Style="{StaticResource SectionHeaderStyle}" Margin="0,0,0,4"/>
                        <TextBlock Text="Guest Username (DOMAIN\user or user@domain)" Style="{StaticResource LabelStyle}"/>
                        <TextBox x:Name="TxtGuestUser"
                                 Style="{StaticResource InputStyle}"
                                 Tag="DOMAIN\administrator"/>
                        <TextBlock Text="Guest Password" Style="{StaticResource LabelStyle}"/>
                        <PasswordBox x:Name="PwdGuestPassword" Style="{StaticResource PwdStyle}"/>
                        <TextBlock Text="Optional — PSRemoting credentials for Golden Images (IP, software versions, disk, local admins)"
                                   Foreground="#585B70" FontSize="10" Margin="0,2,0,0"/>
                    </StackPanel>
                </TabItem>

                <!-- ── Tab 3: UAG ─────────────────────────────────────── -->
                <TabItem Header="UAG">
                    <StackPanel Margin="10,10,10,10"
                                Background="#1E1E2E">
                        <TextBlock Text="UNIFIED ACCESS GATEWAY" Style="{StaticResource SectionHeaderStyle}" Margin="0,0,0,4"/>
                        <TextBlock Text="UAG Admin Username" Style="{StaticResource LabelStyle}"/>
                        <TextBox x:Name="TxtUagUser"
                                 Style="{StaticResource InputStyle}"
                                 Tag="admin"/>
                        <TextBlock Text="UAG Admin Password" Style="{StaticResource LabelStyle}"/>
                        <PasswordBox x:Name="PwdUagPassword" Style="{StaticResource PwdStyle}"/>
                        <TextBlock Text="Optional — queries each UAG via REST API (port 9443): config, edge services, auth methods"
                                   Foreground="#585B70" FontSize="10" Margin="0,2,0,0"/>
                    </StackPanel>
                </TabItem>

                <!-- ── Tab 4: App Volumes ─────────────────────────────── -->
                <TabItem Header="App Volumes">
                    <StackPanel Margin="10,10,10,10"
                                Background="#1E1E2E">
                        <TextBlock Text="APP VOLUMES MANAGER" Style="{StaticResource SectionHeaderStyle}" Margin="0,0,0,4"/>
                        <TextBlock Text="Username (DOMAIN\user, user@domain, or username)" Style="{StaticResource LabelStyle}"/>
                        <TextBox x:Name="TxtAvUser"
                                 Style="{StaticResource InputStyle}"
                                 Tag="DOMAIN\administrator"/>
                        <TextBlock Text="Password" Style="{StaticResource LabelStyle}"/>
                        <PasswordBox x:Name="PwdAvPassword" Style="{StaticResource PwdStyle}"/>

                        <TextBlock Text="App Volumes Manager FQDN (optional)" Style="{StaticResource LabelStyle}" Margin="0,8,0,0"/>
                        <TextBox x:Name="TxtAvFqdn"
                                 Style="{StaticResource InputStyle}"
                                 Tag="appvolmgr01.lab.dc"/>
                        <TextBlock Text="Leave empty to use the App Volumes Manager(s) discovered via Horizon. Set this to document an App Volumes Manager directly — Horizon connection fields become optional when an FQDN is provided."
                                   Foreground="#585B70" FontSize="10" Margin="0,2,0,0" TextWrapping="Wrap"/>

                        <TextBlock Text="Optional — queries App Volumes Manager API: applications, packages, assignments, storage groups"
                                   Foreground="#585B70" FontSize="10" Margin="0,6,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </TabItem>

            </TabControl>

            <!-- ============================================================ -->
            <!-- GROUP 3 — BUTTONS ROW                                        -->
            <!-- ============================================================ -->
            <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
                <Button x:Name="BtnTestConnection"
                        Content="Test Connection"
                        Style="{StaticResource AccentButtonStyle}"
                        MinWidth="130"
                        Margin="0,0,8,0"/>
                <Button x:Name="BtnCancel"
                        Content="Cancel"
                        Style="{StaticResource NeutralButtonStyle}"
                        IsEnabled="False"
                        MinWidth="80"/>
            </StackPanel>

            <!-- ============================================================ -->
            <!-- GROUP 4 — STATUS / FEEDBACK                                  -->
            <!-- ============================================================ -->
            <TextBlock x:Name="TxtConnectionInfo"
                       Foreground="#A6E3A1"
                       FontSize="11"
                       TextWrapping="Wrap"
                       Margin="0,6,0,0"
                       Visibility="Collapsed"/>
            <TextBlock x:Name="TxtErrorLabel"
                       Foreground="#F38BA8"
                       FontSize="11"
                       TextWrapping="Wrap"
                       Margin="0,6,0,0"
                       Visibility="Collapsed"/>

            <Separator Style="{StaticResource SeparatorStyle}" Margin="0,10,0,0"/>

            <!-- ============================================================ -->
            <!-- GROUP 5 — OUTPUT FOLDER                                      -->
            <!-- ============================================================ -->
            <TextBlock Text="OUTPUT" Style="{StaticResource SectionHeaderStyle}"/>

            <TextBlock Text="Output Folder" Style="{StaticResource LabelStyle}" Margin="0,0,0,3"/>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBox x:Name="TxtFolderPath"
                         Grid.Column="0"
                         Style="{StaticResource InputStyle}"
                         Margin="0,0,6,0"/>
                <Button x:Name="BtnBrowseFolder"
                        Grid.Column="1"
                        Content="Browse..."
                        Style="{StaticResource NeutralButtonStyle}"
                        MinWidth="80"/>
            </Grid>

            <!-- Company Info button -->
            <Button x:Name="BtnCompanyInfo"
                    Content="Company Info..."
                    Style="{StaticResource NeutralButtonStyle}"
                    HorizontalAlignment="Left"
                    Margin="0,8,0,0"
                    MinWidth="120"/>

            <!-- Report options -->
            <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                <CheckBox x:Name="ChkExportPdf"
                          Content="Export as PDF"
                          IsChecked="False"
                          Foreground="#A6ADC8"
                          FontSize="12"/>
                <CheckBox x:Name="ChkOpenHtml"
                          Content="Open HTML Report"
                          IsChecked="True"
                          Foreground="#A6ADC8"
                          FontSize="12"
                          Margin="18,0,0,0"/>
            </StackPanel>

            <!-- ============================================================ -->
            <!-- GROUP 6 — GENERATE REPORT BUTTON                             -->
            <!-- ============================================================ -->
            <Button x:Name="BtnGenerateReport"
                    Content="Generate Report"
                    Style="{StaticResource AccentButtonStyle}"
                    HorizontalAlignment="Stretch"
                    Margin="0,12,0,0"
                    Height="34"
                    FontSize="14"/>

            <!-- ============================================================ -->
            <!-- GROUP 7 — PROGRESS                                           -->
            <!-- ============================================================ -->
            <ProgressBar x:Name="ProgressBar"
                         Minimum="0"
                         Maximum="100"
                         Value="0"
                         Height="18"
                         Margin="0,10,0,4"
                         Background="#313244"
                         Foreground="#89B4FA"/>
            <TextBlock x:Name="TxtProgressLabel"
                       Text=""
                       FontSize="11"
                       Foreground="#A6ADC8"
                       Margin="0,0,0,0"/>

            <Separator Style="{StaticResource SeparatorStyle}" Margin="0,8,0,0"/>

            <!-- ============================================================ -->
            <!-- GROUP 8 — LOG BOX                                            -->
            <!-- ============================================================ -->
            <TextBlock Text="LOG" Style="{StaticResource SectionHeaderStyle}"/>
            <ScrollViewer VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Auto"
                          Height="300"
                          Background="#11111B">
                <TextBox x:Name="LogBox"
                         IsReadOnly="True"
                         TextWrapping="Wrap"
                         FontFamily="Consolas"
                         FontSize="11"
                         Background="#11111B"
                         Foreground="#CDD6F4"
                         BorderThickness="0"
                         Padding="6"
                         AcceptsReturn="True"
                         VerticalScrollBarVisibility="Disabled"
                         HorizontalScrollBarVisibility="Disabled"/>
            </ScrollViewer>

        </StackPanel>
    </ScrollViewer>
</Window>
"@

