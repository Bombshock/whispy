# Changelog

All notable changes to Whispy are documented here.

## [Unreleased]

### Added
- The sound picker now offers 45 built-in game sounds instead of nine.
- The picker groups sounds under section headers.
- Sounds registered through LibSharedMedia -- by WIM, SharedMedia, and others -- appear in the picker automatically.
- The sound dropdown scrolls with the mouse wheel.
- The dropdown opens scrolled to the current selection.

### Fixed
- The numeric fallback id for the "Alarm 3" sound pointed at Alarm 2.

## [1.4] - 2026-08-18

### Added
- Hiding windows during combat is now an option, on by default.
- With it off, windows stay open and new conversations open mid-fight.

### Changed
- Whispering someone who is offline shows the "not online" reply inside the conversation window instead of the main chat.
- The offline notice is not saved to history and disappears when its window is closed.

## [1.3] - 2026-08-18

### Added
- The window header shows a class icon for in-game characters.
- Battle.net conversations show the client icon of the game the contact is in.
- The header icon follows a Battle.net contact when they switch games or log off.
- Invite and Ignore buttons sit next to the name in the window header.
- Invite works for Battle.net contacts playing WoW, and reports when they are not online.
- Ignore asks for confirmation, then blocks the person and closes the window.
- Options window, opened from the minimap button or with `/whispy options`.
- The alert sound for incoming whispers can be picked from nine game sounds.
- Battle.net whispers can use a sound of their own.
- An optional sound plays when you send a whisper.
- Sounds can be forced through while the game's sound is switched off.
- Preview button next to each sound picker.

### Changed
- Right-clicking the minimap button opens a menu with History and Options instead of the chat list directly.

## [1.2] - 2026-08-08

### Changed
- Clicking the message list no longer focuses the input box; clicking the input strip still does.

### Fixed
- A whisper arriving in combat no longer throws `ADDON_ACTION_BLOCKED` and breaks the conversation.

### Added
- Message text is selectable: drag across a line and `Ctrl+C`.
- Copied text is stripped of colour codes and hyperlink markup.
- Messages with a hyperlink become selectable on click, so their tooltip and link still work on hover.
- Unread badge on the minimap button counts whispers that arrive while their window is hidden.

## [1.1] - 2026-08-01

**Also prepares for patch 12.1.** Beyond the translation and fixes below, this release makes Whispy ready for 12.1 — that part adds no new features and changes nothing on the live client.

### Added
- German (`deDE`) translation covering the window and chat-list UI, the minimap tooltip, and all `/whispy` chat output, plus a localised `Notes-deDE` in the TOC.
- Date formats are now part of the localisation table, so day dividers and chat-list stamps follow the locale's own ordering (`1. August 2026` rather than `August 01, 2026`).

### Fixed
- The resize grip was drawn and clicked underneath the message input box, leaving windows effectively unresizable; it now sits above the footer, and the input text stops short of it.
- The minimap button's distance from the minimap centre was a fixed 80 pixels, which no longer sat flush against the edge; it is now measured from the minimap's real size, so the button stays put if the minimap is ever resized.

### Changed
- Runs on both the live client and the 12.1 PTR — the TOC now declares both (`120007, 120100`), so this single build loads without an "out of date" flag on either, and will keep working the day 12.1 goes live with no update needed.
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
