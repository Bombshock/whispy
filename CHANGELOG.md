# Changelog

All notable changes to Whispy are documented here.

## [Unreleased]

### Added
- German (`deDE`) translation covering the window and chat-list UI, the minimap tooltip, and all `/whispy` chat output, plus a localised `Notes-deDE` in the TOC.
- Date formats are now part of the localisation table, so day dividers and chat-list stamps follow the locale's own ordering (`1. August 2026` rather than `August 01, 2026`).

### Fixed
- The resize grip was drawn and clicked underneath the message input box, leaving windows effectively unresizable; it now sits above the footer, and the input text stops short of it.

### Changed
- The remaining hard-coded chat output (slash-command help, toggle confirmations, usage errors) routes through the localisation table instead of literal English strings.

## [1.0] - 2026-08-01

### Added
- Initial release of **Whispy**.
- Per-conversation whisper windows with a chat-bubble layout: your lines right and green, theirs left and grey, each timestamped, with centred date dividers between days.
- Persistent per-character history (200 lines per conversation by default), replayed into a window each time it is opened and pruned back to the cap on load.
- Full BattleNet whisper support alongside regular whispers, resolved to account names and coloured separately from class-coloured character names.
- Whisper interception: `/w <name>`, clicking a name in chat, and the unit menu all open a focused Whispy window instead of the default chat edit box, with the default copy of the whisper suppressed while routing is on.
- Canonical conversation keys, so `Bob` and `Bob-YourRealm` share one window instead of splitting into two.
- Shift-click item, spell, quest, and achievement linking into Whispy windows from anywhere in the UI, routed so the game's own edit boxes and search fields keep first claim on the link, with a fallback to the most recently used Whispy window.
- Interactive hyperlinks inside message bubbles: tooltips on hover, click to open, and the wheel still scrolls the message list.
- AFK and DND auto-replies shown as system lines inside an existing conversation.
- Combat handling: windows hide on entering combat and return afterwards, and whispers arriving mid-fight are queued rather than lost.
- Minimap button with a recent-chats flyout on left-click, the full scrollable chat list on right-click, and drag-to-reposition around the minimap.
- Chat list rows showing class-coloured names, relative timestamps (`now`, `5m`, `3h`, `2d`), and a preview of the last line, sorted by most recent activity.
- Movable and resizable windows with a thin custom scrollbar, bubble re-flow on resize, and a remembered size and last position.
- Optional incoming-whisper sound and taskbar flash.
- Screenshot mode (`/whispy ss`) that substitutes a deterministic sample conversation set for captures, pins the UI to English, and restores your real data on toggle-off and on logout so the samples can never reach SavedVariables.
- Demo and simulation commands (`/whispy test`, `/whispy sim`) that inject local-only messages for testing the layout.
- Slash commands `/whispy` with `help`, `chats`, `list`, `toggle`, `sound`, `minimap`, `clear`, `clearall`, `test`, `sim`, and `screenshot` subcommands.
- Localisation layer: every user-visible string and all displayed dates route through a single English table that translations can override per locale.
