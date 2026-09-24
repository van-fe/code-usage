# CodeUsage

English | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="Assets/AppIcon-1024.png" width="112" alt="CodeUsage app icon">
</p>

CodeUsage is a lightweight, native macOS menu bar app that brings Codex, Cursor, Claude Code, Kiro, and Qoder usage and quota information together in one panel.

Project homepage: <https://github.com/van-fe/code-usage>

> CodeUsage is an unofficial third-party tool and is not affiliated with or endorsed by OpenAI, Cursor, Anthropic, AWS, Kiro, or Qoder. All names and marks belong to their respective owners.

## Features

- Show usage in the menu bar with Brief, Moderate, and Full display modes, plus independent visibility controls for each tool.
- Add one adaptive system widget to Notification Center on macOS 13+, or place it on the desktop on macOS 14+, and choose its small, medium, or large size.
- Open a right-aligned panel from the menu bar while preserving the native selected state.
- Refresh usage or open the corresponding app with one click; action buttons provide hover feedback.
- Refresh automatically every five minutes; when a request fails, retain the most recent successful data and mark it as stale.
- Distinguish Cursor's base plan allowance, personal spending, and team or organization totals; show Enterprise shared pools according to the service's billing mode.
- Provide an isolated subscription simulation mode for checking free, personal, team, and enterprise layouts.
- Launch automatically at login, with an option to disable it at any time from the bottom of the panel.
- Optionally sync a reduced usage snapshot through iCloud for future iPhone clients.
- Open the CodeUsage project homepage from the GitHub button at the bottom of the panel.
- Show a clear empty state and guidance when no supported tools are detected.
- No telemetry; login tokens are not written to CodeUsage logs or usage snapshots.

## Supported Tools

| Tool | Data shown | Local requirement |
| --- | --- | --- |
| Codex | Server-provided 5-hour, 7-day, monthly, and other plan windows, plus available extra Credits | Install and sign in to Codex CLI, Codex App, or ChatGPT App with Codex |
| Cursor | Personal plan allowance or reported progress and personal spending; team or organization totals when available | Install and sign in to Cursor |
| Claude Code | The current Claude account's shared 5-hour and 7-day subscription quotas | Install and sign in to Claude Code CLI |
| Kiro | Monthly plan Credits and purchased Add-ons when supported by the sign-in method and returned by the API | Install and sign in to Kiro IDE or Kiro CLI |
| Qoder | Plan Credits, Add-ons returned by the API, and shared organization Credits | Install and sign in to Qoder IDE or Qoder CLI; keep the IDE running if only the IDE is installed |

Only tools detected on the current Mac are shown. After installing a tool or changing its sign-in state, click the refresh button in the upper-right corner of the panel to detect it again.

### Team and enterprise accounts

The table describes what a signed-in member can see. Each item still depends on the data returned by the service. A Team or Enterprise plan name alone does not grant access to administrator billing data.

| Tool | Current member | Team or organization data | Data not inferred |
| --- | --- | --- | --- |
| Codex Business / Enterprise | 5-hour, 7-day, and other plan windows; personal limits when returned | Workspace Credits balance when returned | Team-wide spending or budget percentage |
| Cursor Team / Enterprise | Personal base allowance or reported overall progress, and personal spending | Team or organization totals and limits when returned; Enterprise shared pools may cover total contract-period usage | Personal spending from team totals |
| Claude Code Team / Enterprise | Current member's 5-hour and 7-day quotas | Organization spending is unavailable through standard OAuth credentials | Organization on-demand spending or team budget |
| Kiro Enterprise | Current member's monthly plan Credits | No reliable organization spending in the current personal API | Enterprise overage or administrator quotas |
| Qoder Team / Enterprise | Plan Credits; Add-ons when the API returns `addOnQuota` | Shared organization Credits when returned | US-dollar spending from shared Credits or administrator billing |

## Usage Semantics

### Cursor

Cursor metrics cover plan allowances and spending or shared usage:

- **Plan allowances**: older billing modes retain Cursor's reported overall, Auto, and Other Models (API) progress percentages. These are not spending amounts to add together, and `autoPercentUsed` is not the amount spent on requests made with Auto selected. The newer Team billing mode shows the personal base allowance and third-party model (API) progress. Reaching 100% of the base allowance does not mean bonus usage is exhausted or on-demand billing has started.
- **Spending and shared usage**: individual plans show current-period spending; Teams shows personal spending and the team total separately. Personal spending comes first from Cursor's individual spending field. For the newer Team mode, the app falls back to on-demand spending in the individual usage summary only when that field is absent. If neither is available, it never substitutes the team total for personal spending. An Enterprise shared pool may include total usage over the contract term and is not necessarily overage.

If Cursor does not return a personal spending limit, you can set a display budget in CodeUsage. It only calculates local progress; it does not change Cursor's spending limit or stop usage. When personal spending has a calculable progress value, the menu bar prioritizes its remaining percentage, whether the limit came from Cursor or from a display budget. Otherwise, it shows the primary plan metric. In older billing modes, the remaining percentage derived from Cursor's reported overall progress is not a monetary balance.

### Codex

CodeUsage shows the 5-hour, 7-day, monthly, and other included plan windows returned by the server. If a Business or Enterprise plan returns a personal limit or workspace Credits, those appear separately under Extra Credits. Workspace Credits may be shared by members and supported features; they are neither a personal balance nor a team-wide budget. The app does not infer a team percentage from missing fields.

### Claude Code

CodeUsage shows the subscription quota of the current Claude account. Claude and Claude Code share these limits. Claude Team usage is generally measured per seat rather than from a shared team pool. Standard Claude Code OAuth sign-in does not provide organization spending, so CodeUsage does not infer an amount or team budget.

### Kiro

CodeUsage shows the current account's monthly plan Credits. Purchased Add-ons appear only when the social sign-in or AWS Builder ID method supports them and the API returns unexpired purchased credits; this is not a separate verification of the account's purchasing type. Enterprise overage requires administrator reports or AWS quota data and cannot be inferred reliably from the personal API.

### Qoder

When Qoder CLI is installed, CodeUsage uses it first to read plan Credits, Add-ons returned by the API, and shared organization Credits without requiring Qoder IDE to remain open. If the CLI is unavailable, CodeUsage falls back to the local Qoder IDE service. An `addOnQuota` response is displayed without a separate check that the account uses individual purchasing. Extra quota is measured in Credits, not converted to US dollars, and administrator OpenAPI data is never inferred from a standard user session.

The `expiresAt` value from Qoder's usage API is the expiration or clearing boundary for the current plan Credits, so the interface labels it as “Expires” rather than always describing it as the next reset. Credits for a renewed period are issued separately by Qoder's server.

## Subscription Simulation Mode

Simulation mode does not read or overwrite real account data. Use it to inspect the interface for each subscription type:

```bash
open -a CodeUsage --args --subscription-simulation
```

After opening it, switch among Free Trial, Individual, Team, and Enterprise at the top of the panel. Quit and launch CodeUsage normally to return to real data automatically.

## Installation

### Use the DMG (Recommended)

1. Go to [Releases](https://github.com/van-fe/code-usage/releases) and download the latest `CodeUsage-*-macos-universal.dmg`.
2. Open the DMG and drag `CodeUsage.app` into the Applications folder.
3. Launch CodeUsage. A dashboard icon and the remaining percentage of each enabled tool's primary metric will appear in the menu bar.

Use the gear menu to choose a menu bar mode. To add the system widget, edit the macOS widget gallery, choose CodeUsage, and select the size you need. On macOS 14 or later, right-click the widget and choose Edit Widget: small widgets can show 1 selected metric, medium widgets up to 3, and large widgets always show every metric grouped by provider.

The Universal build supports:

- Apple Silicon: `arm64`
- Intel: `x86_64`

App requirement: macOS 13 Ventura or later. The configurable system widget requires macOS 14 Sonoma or later.

### Signing and Security

Official release builds are signed with Apple Developer ID and notarized by Apple, so they can be launched normally. Download installers only from this project's [Releases](https://github.com/van-fe/code-usage/releases) page.

## Data Sources and Privacy

CodeUsage reads existing sign-in states locally and sends requests only to each tool's own usage service:

- **Codex**: starts the local `codex app-server` and calls `account/rateLimits/read`; it does not read `~/.codex/auth.json`.
- **Cursor**: reads the existing sign-in state from Cursor's local state database. Refresh tokens are used only for in-memory session renewal and are never written back to disk.
- **Claude Code**: reads the OAuth sign-in state saved by Claude Code. Refresh tokens are used only for in-memory session renewal and are never written back to disk.
- **Kiro**: reads local sign-in records from Kiro IDE or CLI. When a supported social sign-in expires, it uses the existing refresh token and saves the renewed credential back to Kiro's original credential file or CLI database. It does not read device registration keys or browser cookies.
- **Qoder**: first calls the local usage control interface of the signed-in Qoder CLI. If the CLI is unavailable, it uses the owner- and permission-validated `.info.json` and Unix socket to call the Qoder IDE JSON-RPC service. Qoder handles authentication; CodeUsage does not read, decrypt, or save Qoder tokens.

The app contains no telemetry and does not upload usage data to a CodeUsage server. Widgets receive only a local App Group snapshot containing provider names, plan names, usage metrics, percentages, amounts or counts, stale state, and refresh time. iCloud sync is off by default. When explicitly enabled, it writes only provider names, plan names, usage metrics, percentages, amounts or counts, and refresh timestamps to the user's private CloudKit database. Access tokens, refresh tokens, cookies, local databases, file paths, raw command output, and raw server responses are excluded from both snapshot models. Some Cursor and Kiro client protocols are not stable public APIs; if fields change, the app preserves other available metrics where possible and displays a clear error.

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

### Why can't Cursor overall, Auto, and API progress be added together?

In older billing modes, these percentages measure different kinds of progress, not spending amounts to add together. The newer Team billing mode shows the personal base allowance and third-party model progress without treating Auto's percentage as Auto request usage.

### Why isn't the team-wide budget shown?

CodeUsage displays only data that can be read reliably with the current sign-in state. If the server does not provide a team budget or organization spending permission, the app does not guess it from personal data.

## Third-Party Notices

Tool names and monochrome marks are used only to identify the corresponding services. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for complete source, license, and trademark notices.

## License

CodeUsage is distributed under a [proprietary source-available license](LICENSE), not an open-source license.

Users may download, install, and use official unmodified builds published by the author free of charge. Without the author's written permission, you may not modify, create derivative works, repackage, redistribute, sell, commercialize, or publish official or modified builds to any app store, software marketplace, package repository, or download platform. Third-party materials remain subject to the separate terms listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
