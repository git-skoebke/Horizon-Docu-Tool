# Changelog

All notable changes to the Horizon Documentation Tool are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [Unreleased]

---

## [2026-04-14]

### Fixed
- Column widths in HTML report tables no longer overflow or truncate content
  - `Members` column: 70 px → 120 px (fits collapsible group toggle)
  - `Member Count` column: 100 px → 130 px (fits header + member toggles)
  - `Feature | Enabled` split: 75 %/25 % → 60 %/40 % (better balance)
  - App Volumes `Last Updated` column: 135 px → 160 px (fits full datetime string)
  - License `Usage` table: auto-calculated 960 px replaced by explicit 75 %/12 %/13 %
  - Application Pools `Entitlements` table: auto-calculated 940 px replaced by 75 %/12 %/13 %

---

## [2026-04-13]

### Added
- Initial release of the Horizon Documentation Tool
- Core collector modules: Connection Servers, vCenters, Datastores, ESXi Hosts, AD Domains,
  Gateways, UAG, License, General Settings, Global Policies, Event Database,
  SAML Authenticators, TrueSSO, Permissions, IC Domain Accounts, Environment Properties,
  App Volumes Manager, App Volumes Config, Desktop Pools, RDS Farms, Application Pools,
  Local Desktop/Application Entitlements, Golden Images, Syslog, CPA, VCenter inventory
- Renderer modules with collapsible detail cards, badges, and print-optimised layout
- WPF-based GUI (`HorizonDocTool.ps1`) with company info dialog and PDF export
- HTML report with sticky TOC sidebar, cover page, and full-page print support
- Comprehensive README with architecture overview and module descriptions

### Changed
- Cleaned up development notes; updated module references

---
