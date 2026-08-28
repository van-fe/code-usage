# CodeUsage

English | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="Assets/AppIcon-1024.png" width="112" alt="CodeUsage app icon">
</p>

CodeUsage is a lightweight, native macOS menu bar app that brings Codex, Cursor, Claude Code, Kiro, and Qoder usage and quota information together in one panel.

Project homepage: <https://github.com/van-fe/code-usage>

> CodeUsage is an unofficial third-party tool and is not affiliated with or endorsed by OpenAI, Cursor, Anthropic, AWS, Kiro, or Qoder. All names and marks belong to their respective owners.

## Features

- Show icons and remaining percentages for multiple tools in the menu bar, with independent visibility controls for each tool.
- Open a right-aligned panel from the menu bar while preserving the native selected state.
- Refresh usage or open the corresponding app with one click; buttons include hover and pressed feedback.
- Refresh automatically every five minutes; when a request fails, retain the most recent successful data and mark it as stale.
- Mark the suggested usage pace for the current billing window on each progress bar.
- Separate Cursor plan usage from on-demand spending; personal plans show current-period spending, while team and enterprise plans distinguish personal and organization spending.
- Provide an isolated subscription simulation mode for checking free, personal, team, and enterprise layouts.
- Launch automatically at login, with an option to disable it at any time from the bottom of the panel.
- Optionally sync a reduced usage snapshot through iCloud for future iPhone and widget clients.
- Open the CodeUsage project homepage from the GitHub button at the bottom of the panel.
- Show a clear empty state and guidance when no supported tools are detected.
- No telemetry, and no login tokens are stored, logged, or printed.

## Supported Tools

| Tool | Data shown | Local requirement |
| --- | --- | --- |
| Codex | Server-provided 5-hour, 7-day, monthly, and other plan windows, plus available extra Credits | Install and sign in to Codex CLI, Codex App, or ChatGPT App with Codex |
| Cursor | Total included usage, Auto, specified models (API), and personal or team on-demand spending | Install and sign in to Cursor |
| Claude Code | The current member's 5-hour and 7-day subscription quotas | Install and sign in to Claude Code CLI |
| Kiro | Monthly plan Credits and personal Add-ons explicitly returned by the API | Install and sign in to Kiro IDE or Kiro CLI |
| Qoder | Plan Credits, personal Add-ons, and shared organization Credits | Install and sign in to Qoder IDE or Qoder CLI; keep the IDE running if only the IDE is installed |

Only tools detected on the current Mac are shown. After installing a tool or changing its sign-in state, click the refresh button in the upper-right corner of the panel to detect it again.

## Usage Semantics

### Cursor

Cursor data is divided into two groups:

- **Included usage**: total usage, Auto, and specified models (API). Auto and specified-model usage use different accounting methods and cannot be added together directly.
- **On-demand spending**: personal plans show current-period spending. Separate personal and team or organization spending is shown only when the account is confirmed to be on a team or enterprise plan.

If Cursor does not return a spending limit, you can set a display budget in CodeUsage. This value is used only to calculate the progress bar and remaining percentage. It does not change the spending limit in Cursor or stop actual spending. When set, the menu bar prioritizes the reference remaining percentage for on-demand spending; otherwise, it shows total plan usage.

## Subscription Simulation Mode

Simulation mode does not read or overwrite real account data. Use it to inspect the interface for each subscription type:

```bash
open -a CodeUsage --args --subscription-simulation
```

After opening it, switch among Free Trial, Individual, Team, and Enterprise at the top of the panel. Quit and launch CodeUsage normally to return to real data automatically.

### Codex

CodeUsage shows the 5-hour, 7-day, monthly, and other included plan windows returned by the server. If a Business or Enterprise plan returns a personal limit or workspace Credits, those appear separately under Extra Credits. A workspace balance is not the same as a team-wide budget, and the app does not infer a team percentage from missing fields.

### Claude Code

CodeUsage shows the subscription quota of the currently signed-in member. Claude Team usage is generally measured per seat rather than from a shared team pool. Standard Claude Code OAuth credentials cannot read organization on-demand spending, so CodeUsage does not invent an amount or team budget.

### Kiro

CodeUsage shows monthly personal plan Credits. Add-ons appear only when the API can confirm that they belong to an individually purchased account. Enterprise overage requires administrator reports or AWS quota data and cannot be inferred reliably from the personal API.

### Qoder

When Qoder CLI is installed, CodeUsage uses it first to read plan Credits, personal Add-ons, and shared organization Credits without requiring Qoder IDE to remain open. If the CLI is unavailable, CodeUsage falls back to the local Qoder IDE service. Extra quota is measured in Credits, not converted to US dollars, and administrator OpenAPI data is never inferred from a standard user session.

The `expiresAt` value from Qoder's usage API is the expiration or clearing boundary for the current plan Credits, so the interface labels it as “Expires” rather than always describing it as the next reset. Credits for a renewed period are issued separately by Qoder's server.

## Suggested Usage

The green marker on a progress bar represents the suggested cumulative usage percentage for the current billing window. It is a pacing aid, not an official restriction from any provider.

- Windows shorter than 24 hours progress by hour.
- Windows of 24 hours or longer progress by day.
- For example, a full seven-day window shows approximately `14%` on day one and `29%` on day two.

## Installation

### Use the DMG (Recommended)

1. Go to [Releases](https://github.com/van-fe/code-usage/releases) and download the latest `CodeUsage-*-macos-universal.dmg`.
2. Open the DMG and drag `CodeUsage.app` into the Applications folder.
3. Launch CodeUsage. A dashboard icon and the remaining usage for enabled tools will appear in the menu bar.

The Universal build supports:

- Apple Silicon: `arm64`
- Intel: `x86_64`

System requirement: macOS 13 Ventura or later.

### Signing and Security

Official release builds are signed with Apple Developer ID and notarized by Apple, so they can be launched normally. Download installers only from this project's [Releases](https://github.com/van-fe/code-usage/releases) page.

## Data Sources and Privacy

CodeUsage reads existing sign-in states locally and sends requests only to each tool's own usage service:

- **Codex**: starts the local `codex app-server` and calls `account/rateLimits/read`; it does not read `~/.codex/auth.json`.
- **Cursor**: reads the existing sign-in state from Cursor's local state database. Refresh tokens are used only for in-memory session renewal and are never written back to disk.
- **Claude Code**: reads the OAuth sign-in state saved by Claude Code. Refresh tokens are used only for in-memory session renewal and are never written back to disk.
- **Kiro**: reads local sign-in records from Kiro IDE or CLI and uses only short-lived access tokens; it does not use refresh tokens or read device registration keys or browser cookies.
- **Qoder**: first calls the local usage control interface of the signed-in Qoder CLI. If the CLI is unavailable, it uses the owner- and permission-validated `.info.json` and Unix socket to call the Qoder IDE JSON-RPC service. Qoder handles authentication; CodeUsage does not read, decrypt, or save Qoder tokens.

The app contains no telemetry and does not upload usage data to a CodeUsage server. iCloud sync is off by default. When explicitly enabled, it writes only provider names, plan names, usage metrics, percentages, amounts or counts, and refresh timestamps to the user's private CloudKit database. Access tokens, refresh tokens, cookies, local databases, file paths, raw command output, and raw server responses are excluded from the sync model. Some Cursor and Kiro client protocols are not stable public APIs; if fields change, the app preserves other available metrics where possible and displays a clear error.

## Build from Source

Requirements:

- macOS 13 or later
- Swift 6 toolchain
- Xcode Command Line Tools

Run tests and build for the current architecture:

```bash
./Scripts/test.sh
./Scripts/package.sh
open dist/CodeUsage.app
```

Build a Universal app and ZIP for both Apple Silicon and Intel:

```bash
./Scripts/package_universal.sh
```

Package `dist/CodeUsage.app` as a language-neutral drag-to-install DMG written directly to `dist/`:

```bash
./Scripts/package_dmg.sh
```

When creating a DMG for the first time, macOS may ask for permission to let Terminal control Finder so it can configure icon positions and the window background.

Create a source archive:

```bash
./Scripts/package_source.sh
```

The DMG is written to the project's `dist/` directory by default. Universal ZIP and source archives are written to `outputs/`. Set `CODEUSAGE_OUTPUT_DIR` to use another output directory.

Regular local packaging scripts such as `package.sh` and `package_universal.sh` use ad-hoc signing by default. Official release builds use the local release process with Developer ID Application, Hardened Runtime, and secure timestamp signing, followed by Apple notarization.

See [RELEASING.md](RELEASING.md) for GitHub Actions, Release Please version automation, and the official signing workflow that keeps Apple credentials only in the local Keychain.

## Project Structure

```text
CodeUsage/
├── Sources/CodeUsage/   # SwiftUI interface, menu bar controller, and usage providers
├── Assets/              # App icon, provider icons, and DMG background
├── Scripts/             # Tests and single-architecture, Universal, DMG, and source packaging
├── dist/                # Current-architecture App and DMG (not committed)
├── outputs/             # Local release artifacts (not committed)
├── LICENSE              # CodeUsage proprietary source-available license
├── Package.swift
├── README.md
├── README.zh-CN.md
└── THIRD_PARTY_NOTICES.md
```

## FAQ

### A tool is installed but not shown

Confirm that the corresponding tool is signed in, then click the refresh button in the upper-right corner of the panel. If a CLI is signed out or its session has expired, the card shows the appropriate sign-in command and a copy button. Refresh after signing in. If only Qoder IDE is installed, keep Qoder IDE running.

### Why can't Cursor total, Auto, and API usage be added together?

They are not mutually exclusive billing items at the same level. Total usage measures overall plan consumption, while Auto and specified-model usage describe different routing methods, so they cannot be added together.

### Why isn't the team-wide budget shown?

CodeUsage displays only data that can be read reliably with the current sign-in state. If the server does not provide a team budget or organization spending permission, the app does not guess it from personal data.

### Does suggested usage restrict how much I can use?

No. It is only a local pacing reference. It does not modify server-side quotas, stop requests, or cause additional spending.

## Third-Party Notices

Tool names and monochrome marks are used only to identify the corresponding services. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for complete source, license, and trademark notices.

## License

CodeUsage is distributed under a [proprietary source-available license](LICENSE), not an open-source license.

Users may download, install, and use official unmodified builds published by the author free of charge. Without the author's written permission, you may not modify, create derivative works, repackage, redistribute, sell, commercialize, or publish official or modified builds to any app store, software marketplace, package repository, or download platform. Third-party materials remain subject to the separate terms listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
