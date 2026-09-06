# Changelog

All notable changes to FiveRoster for FiveM will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-09-06

### Added
- **Training presentations on in-game screens.** A presenter stands at a screen,
  runs `/present`, picks one of their roster's FiveRoster training decks, and it
  appears on that screen for everyone nearby
  - Left / Right arrow change slide, Backspace ends the cast; the keys are
    configurable under `Config.Presentations`
  - The game server owns the slide index and broadcasts it, so everybody sees
    the same slide and a player who arrives mid-briefing joins on the slide
    that is showing. Only the presenter can move the deck
  - Any prop of a model listed in `Config.Presentations.screenModels` is a
    castable screen; `fixedScreens` places screens this resource owns, for
    briefing rooms with no TV in the map
  - `Config.Presentations.maxScreens` caps how many screens are drawn at once,
    and browser surfaces are pooled rather than rebuilt as players move around
  - Attendance: whoever is standing at the screen is reported back to
    FiveRoster and gets a view record against the presentation, so an in-game
    briefing counts towards their training record. Only the presenter's client
    reports, and it sends server IDs the game server resolves itself. Turn it
    off with `Config.Presentations.attendance.enabled = false`
  - `IsPresenting`, `GetActiveCast`, `StopPresenting` and
    `OpenPresentationPicker` client exports; `GetActiveCasts`, `IsPresenting`
    and `StopPresenting` server exports
  - A cast ends when the presenter stops it, disconnects, or the resource
    restarts; FiveRoster closes anything left idle
  - Instances without the casting routes are detected and the commands say so

### Changed
- **The tablet's loading indicator is quieter.** The three spinning rings, the
  pulsing logo and the animated dots are replaced by a static mark and one thin
  sweep, and it holds still for players who have asked their system for reduced
  motion

## [1.3.0] - 2026-09-03

### Added
- **Shift Breaks** - Pause and resume a shift without ending it. The shift stays
  open and keeps its ID, start time and division flag; break time is deducted
  from the hours it finally records
  - `/shiftpause`, `/shiftresume` and a `/shiftbreak` toggle, all configurable
    under `Config.ShiftPause`, with an optional keybind for the toggle
  - `shiftPaused` and `shiftResumed` NUI callbacks so the tablet's Pause and
    Resume buttons update the game client
  - `PauseShift`, `ResumeShift`, `ToggleShiftPause`, `IsShiftPaused`,
    `GetShiftDuration` and `IsShiftPauseSupported` exports on both sides
  - `fiveroster:onShiftPaused` and `fiveroster:onShiftResumed` events
  - Break state (`isPaused`, `pausedAt`, `pausedSeconds`, `pauseCount`,
    `durationSeconds`) on the shift tables returned by `GetActiveShift`
  - A shift already in the requested state (HTTP 409) is treated as
    informational, never as an error, and is never retried
  - Instances without the break routes are detected and the control is hidden
- **Optional shift HUD** (`Config.ShiftHUD`, off by default) showing on duty and
  on break as distinct states, with the duration frozen during a break
- **Shift state resync on player load and resource restart** so breaks started
  on the web dashboard, or outliving a restart, are reflected in-game

### Fixed
- **Shifts no longer stay open when a player disconnects.** The Discord ID is
  now cached from `playerJoining`, because by the time `playerDropped` runs the
  framework player object is gone and identifiers can already be unreadable.
  Without an ID the resource had no way to ask the backend to end the shift and
  silently gave up
- The disconnect end request now retries transient failures (connection errors,
  timeouts, rate limits and 5xx) instead of dropping the shift on the floor.
  Retries are abandoned if the player reconnects, so a new shift is never closed
  by the session that just left
- Shifts are no longer lost when `playerDropped` is never fired or never
  completes. Open shifts and the ends still owed are written to
  `shift_state.json`, so a server crash, a hard shutdown or a backend outage is
  settled on the next resource start. A sweep every 60 seconds catches players
  who vanished without a disconnect the resource ever acted on. Restarting only
  the resource ends nothing: connected players' shifts are picked back up and
  re-read from FiveRoster. Configurable under `Config.ShiftRecovery`, and it
  degrades to in-memory behaviour with a warning if the folder is read-only
- A failed disconnect end is logged with the player's name when a shift was
  known to be open, instead of failing silently
- Non-JSON API responses no longer raise inside a response handler

### Changed
- Updated fxmanifest version to 1.3.0
- Added the new exports to fxmanifest
- Shift tables handed to client code now carry both `snake_case` and `camelCase`
  keys, so existing consumers of either spelling keep working

## [1.2.0] - 2026-04-02

### Added
- **Rank-to-Job Synchronization** - Automatically sync FiveRoster ranks to in-game jobs
  - Support for ESX, QBCore, and QBox frameworks
  - Sync on player join and on rank changes
  - Configurable rank-to-job mappings in `config.lua`
  - Priority system for players with multiple ranks
  - Optional fallback job for unmapped players
  - `SyncPlayerJob(source)` export for manual sync
  - `GetJobForRank(rankUuid)` export for getting mappings
  - `/syncjob` command for admin use
  - `fiveroster:onJobSynced` event for other resources

### Changed
- Updated fxmanifest version to 1.2.0
- Added new exports to fxmanifest

## [1.1.0] - 2025-04-02

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
