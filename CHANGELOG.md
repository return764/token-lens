# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-06-30

### Added

- tag-triggered GitHub Actions release workflow
- release notes generated from CHANGELOG.md during releases
- overview token usage chart with range handling and hourly today view
- dashboard usage heatmap
- OpenCode local source support

### Changed

- live cost and token display options merged into live usage mode
- settings window replaced with dashboard tabs
- overview chart hover performance optimized
- local usage adapter records redesigned
- README split by language
- agent skills moved to the Codex directory

### Fixed

- non-tag release workflow handling and build script sed delimiter usage
- OpenCode WAL change handling
- menu popover responsiveness

## [0.1.0] - 2026-06-13

### Added

- Menu bar app displaying cost or token usage for today / month / all time
- Live token feed with animated input/output token counts on new usage
- Automatic scanning of Codex, Claude Code, and pi local JSONL session logs
- FSEvents-based background watcher for real-time session monitoring
- SQLite database (GRDB) for local usage tracking and model pricing
- Built-in model pricing seeded from [models.dev](https://models.dev) on first launch
- Key-based idempotent deduplication for repeated scan/watcher events
- Settings window with Local Sources status, recent usage, and display preferences
- Privacy-first design: no prompt, response, tool output, API key, or Authorization header storage
- DMG packaging support via `build-release.sh`
