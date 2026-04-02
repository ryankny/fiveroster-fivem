# Changelog

All notable changes to FiveRoster for FiveM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-04-02

### Added
- **Multi-Guild Support** - Connect multiple Discord servers (PD, EMS, Fire, etc.)
  - Configure multiple API keys in `server/config.lua`
  - Players see rosters from all Discord servers they belong to
  - Seamless aggregation into single interface
- **Shift Management Exports** - Full API for integrating with MDTs and other resources
  - `StartShift(source, rosterUuid, flagId, callback)` - Start a shift via API
  - `EndShift(source, callback)` - End a player's active shift
  - `GetPlayerRosters(source, callback)` - Get available rosters for a player
- **Auto-End Shifts on Disconnect** - Automatically ends active shifts when players leave
- **Single Shift Enforcement** - Prevents players from having multiple active shifts
- **Active Shift UI** - Shows active shift banner on roster selection screen
- **Client-Side Exports** - `StartShift()` and `EndShift()` for client scripts
- **Server Events** - `fiveroster:onShiftStarted` and `fiveroster:onShiftEnded` events
- **Client Events** - Local shift start/end events for other resources
- **Debug Mode** - Comprehensive logging with configurable categories
- **Framework Support** - ESX, QBCore, and custom Discord ID sources

### Changed
- Improved error messages with roster names for shift conflicts
- Enhanced API response handling with detailed error information
- Better configuration documentation with examples
- Updated fxmanifest with export declarations

### Fixed
- Shift tracking synchronization between client and server
- NUI focus handling on close
- Animation cleanup when closing tablet

## [1.0.0] - 2026-03-15

### Added
- Initial release
- In-game tablet interface for FiveRoster
- Shift tracking via web UI
- Multi-framework Discord ID support (FiveM, ESX, QBCore)
- Configurable commands and aliases
- Multiple notification system support
- Tablet prop and animation
- Session-based authentication
