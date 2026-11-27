<div align="center">
    <img src="./Resources/AppIcon.svg" alt="Ripcord logo" width="128" height="128">
    <h1>Ripcord</h1>
</div>

> A small, resident launcher for Apple silicon Macs, written in Swift and AppKit.

- Fuzzy-search apps by their localized or file name (`システム設定` and `System Settings` both work)
- ⌘Space shows the panel at once, on Liquid Glass; with nothing typed it lists running apps and
  Quicklinks
- Calculator: `1+2*3`, `(1.5+2)^2`, full-width input too; Return copies the result
- Quicklinks: `g swift testing` opens a search; with no match, the query goes to each Quicklink
- Drafts: Create Snippet or Add Bookmark left with something typed waits under Drafts at the top
  of the empty search, across relaunches; Return opens it again and ⌃X discards it
- Favorites: ⇧⌘F on an app, command or Quicklink pins it to the top of the empty search, in
  your order (⌥⌘↑ and ⌥⌘↓ move it), as Raycast's Favorites do
- ⌘K lists the selected row's actions (Open Command ↵, Show in Finder ⌘↵, Copy Path or URL ⇧⌘C,
  Add to Favorites ⇧⌘F)
- Backdrop: an optional Metal shader animated behind the panel's text, built in (Glow, Matrix) or
  your own; off by default
- Settings (⌘,): Launch at Login, the hotkey, the input source to type in and Quicklinks, kept
  in sync with the config file. "Search settings..." at the top of the sidebar finds a page by
  its name or by a setting or command on it, as in Raycast
- Settings has a page per extension (Applications, Quicklinks, Clipboard History, Snippets, System
  Actions, Window Management): give any app, Quicklink or command an alias, a hotkey that runs it
  from anywhere, or turn it off so it never shows up in search
- Clipboard History: copied text and images, including a copied image file such as a CleanShot X
  capture, and other copied files with their Finder icons, with a preview and details of the
  selected one (a file's kind, size and path). Return pastes into the app you were in (files paste
  as files, into Finder too), ⇧⌘P pins an item to the top, ⌃X deletes it and ⇧⌘X deletes all but the
  pinned ones; the All Types menu (⌘P) narrows the list to text, images, files, links, emails or
  colors. Text in copied images is read (Text Recognition, with Vision, on the Mac), so a search
  finds an image by it. Settings › Clipboard History can make Return copy instead, with paste on ⌘↵,
  and list apps whose copies aren't recorded (Passwords and Keychain Access to start with). Copies a
  password manager marks as concealed are never recorded, and switching the command off on its
  settings page stops recording
- Snippets: Create Snippet saves text with a name, keyword, icon and tags from the panel, and
  Search Snippets pastes it into the app you were in. `{clipboard}`, `{date}`, `{time}`,
  `{datetime}`, `{day}` and `{uuid}` are filled in, and `{cursor}` is where the caret lands.
  ⇧⌘C copies, ⌘E edits, ⌘D duplicates and ⌃X deletes; the tag menu filters the list. Export
  Snippets and Import Snippets read and write the JSON Raycast uses. Typing a snippet's keyword
  (`;addr`) in another app replaces it with the snippet, while typing in English rather than kana
  and never in a password field or Ripcord's own panel and Notes; Settings › Snippets sets when
  it expands, and the apps it stays out of
- System Actions: lock the screen, log out, restart, shut down, sleep, control music and volume,
  hide, unhide or quit apps, restart the frontmost app, open or empty the Trash, eject disks, show
  the desktop, and toggle Dark Mode or Finder's hidden files. Ones that lose work ask first
- Git Repositories: Search Repositories lists the repositories in the folders you pick (`~/dev`
  and the like) and opens one in the app you assign to ↵, ⌘↵, ⌥↵, ⌃↵ or ⇧↵, an editor or a
  terminal; ⌘K adds Open on GitHub, Show in Finder and Copy Path. Clone Repo, as Raycast's Git
  Repos has it, takes a repository URL and one of those folders beside the search bar and runs
  `git clone` there. Remove Repo lists them to move one to the Trash, asked first and refused
  while it has uncommitted changes, untracked files or unpushed commits; ⇧⌘D force-removes
- Coffee: Caffeinate keeps the Mac and its display awake until Decaffeinate; type a time after
  it, as in `caffeinate 1h 30m`, to stop on its own. A cup with the time left shows in the menu bar.
  As Raycast's Coffee: Toggle Caffeinate; Caffeinate for ... takes hours, minutes and seconds in
  its fields; Caffeinate Until a time of day, as 5pm or 17:30; Caffeinate While keeps it awake
  until the app picked, or the one you were in, quits; Caffeinate Status says which, and until
  when. Settings › Coffee picks what's kept awake (the display, the system and the disk by
  default, and the system on AC power with the lid closed if asked) and can start it with Ripcord
- Sleep Timer: type a time after it, as in `sleep timer 30m`, then pick Sleep or Turn Off Display;
  a moon with the time left shows in the menu bar until it fires or Stop Sleep Timer
- Lid Awake: keeps the Mac from sleeping, with the lid closed and on battery too, until turned off
  or for a time typed after it, as in `lid awake 2h`; while on, it's pinned at the top of the
  search with the time left, and a sun shows in the menu bar. It sets `pmset -a disablesleep 1`,
  so while on the Mac doesn't sleep at all; Ripcord's Sleep and Sleep Timer turn it off first. It
  turns itself off when its time is up, when the battery falls to the level set in Settings › Lid
  Awake (10% unless changed), when Ripcord quits, and, as the setting outlives a restart, the
  next time Ripcord starts after a crash. `pmset -a disablesleep` takes root, so Settings › Lid
  Awake asks once for an administrator password to add a sudoers rule
  (`/etc/sudoers.d/ripcord-lid-awake`) allowing exactly `pmset -a disablesleep 0` and `1`;
  Remove… there takes it out
- Color Picker: Pick Color copies a color from anywhere on screen in the format set on its settings
  page: Raycast's (HEX, HEX Lower Case, HEX No Prefix, RGB, RGB %, RGBA, RGBA %, HSLA, HSVA, OKLCH,
  LCH, P3), written as the colorjs.io library Raycast calls writes them (HEX as #F00 where it can),
  or HSL, SwiftUI or NSColor. A message says what was copied, with the nearest named color if Show
  Color Name After Picking is on. Color History lists the colors picked, to copy in any format, its
  favorites first (⇧⌘F adds or removes one, and Favorite Colors lists only them; a favorite stays
  past the 100 kept); Color Names lists the CSS color names nearest a hex typed, as #00ff00, or the
  names containing what's typed; Convert Color writes a CSS color typed or pasted (hex, a name,
  rgb(), hsl(), oklch() or color(display-p3 …)) in every format, the one copied last first; Color
  Wheel shows a wheel of every hue in the panel and opens the color sampler over it, to pick from it
  as Pick Color does
- Clean Keyboard: turns every key off, media keys included, for a time typed after it (15 seconds
  to 5 minutes) so the keyboard can be wiped, with the time left over the screen; ⌃⌥⌘↩ turns it
  back on early. As Raycast's, Settings › Clean Keyboard sets a Default Duration that starts it at
  once (up to 24 hours, or Forever, until ⌃⌥⌘↩) instead of asking, can leave the function row
  (F-keys, media and brightness keys) working, and can lock mouse clicks too
- Bookmarks: Search Bookmarks lists the Markdown links in `~/.config/ripcord/bookmarks.md`
  (`- [Title](URL) - description`) under their `#` headings; Return opens one, and ⌘K copies its
  URL or title, edits it, moves it to another group or deletes it. Add Bookmark opens a form for
  a new one, filled with the tab you're on in Safari, Chrome or Arc. Only the lines a change
  touches are rewritten; the rest stays as you wrote it
- Notes: Ripcord Notes opens a small window at the top right of the screen, floating over your
  apps without taking them out of front, on one note at a time, and grows with the note. Its
  Markdown is formatted as you type, as in Raycast Notes: once a mark is complete it's hidden
  (`# ` makes a heading, `**bold**` turns bold), and lists, checkboxes, quotes and code blocks are
  drawn in place of theirs. Tab and Shift-Tab nest list items, Shift-Return breaks a line inside
  one, and ⌘Return checks a task. The T button (⇧⌘,) formats the selection, ⌘K lists the note's
  actions, ⌘N starts another and ⌘P searches them. Each note is a Markdown file in
  `~/.config/ripcord/notes`, marks and all, titled by its first line and saved as you type. Edits
  another editor saves show up in the open note, and a note changed outside Ripcord is never saved
  over. Search Notes finds notes by their text, and ⌃X moves one to the Trash, with Undo for a
  few seconds
- Lorem Ipsum Generator JP: Generate Dummy Text writes Japanese or English filler text of the
  length typed in the field beside the search bar, as Raycast's Japanese Lorem Ipsum Generator
  does; Return pastes it into the app you were in and ⌘↵ copies it. Settings › Lorem Ipsum
  Generator JP sets the default language, Japanese unless changed
- Emoji & Symbols: Search Emoji & Symbols shows emoji and symbols (→ ° ⌘ and the like) in a grid by
  category, Frequently Used first; search in English or Japanese (`cat`, `ねこ`), Return pastes,
  ⌘↵ copies, and ⌘K picks a skin tone that's remembered. Settings › Emoji & Symbols sets the
  grid's Column Count (6 to 10), the Primary Action (Return copies instead, pasting on ⌘↵) and
  the skin tone, as Raycast's does. Typing `:` and a word in Notes or Create Snippet's text box
  lists the emoji it names, as Raycast's inline emoji picker does: ↑↓ choose, Return or Tab put
  one in, Esc closes the list; Disable Inline Emoji Picker there turns it off
- Script Commands: Raycast's Script Commands in the folders set under Settings › Script Commands
  are listed in the root search; `silent` ones show their last line over the screen, `compact`
  ones over the footer and `fullOutput` ones all of it in the panel, and a failure shows its exit
  code and error. A script's arguments are fields beside the search bar, as Raycast's: Tab and
  Shift-Tab move through them, dropdowns too, and a space right after the script's alias jumps
  into the first; a dropdown steps with ↑↓, and Space or a letter opens its list to filter.
  Return runs the script once the required ones are filled, after asking first when it sets
  `needsConfirmation`. A refreshing `inline` isn't run yet
- HTTP Status Codes: look a code up by number or name, grouped by hundred; Return opens its MDN
  page and ⌘K copies the code or its name
- CleanShot X: Capture Area, Window, Fullscreen and Previous Area, Scrolling Capture, Record
  Screen, Capture Text (OCR), Self Timer, Pin, Annotate, History and the rest of its URL scheme,
  named as Raycast's extension names them and listed when CleanShot X is installed; the captures
  take an Action (Copy, Save, Annotate, Upload or Pin) and Open Settings a tab, in a field beside
  the search bar
- Window Management: put the frontmost window in a half, quarter or third, maximize or center
  it, move it to the next or previous display, or restore where it was; give each a hotkey such
  as ⌃⌥← on its settings page
- Drag the panel anywhere; it remembers the spot, and Reset Ripcord Window Position brings it back

## Quick start

Free ⌘Space first: turn off Spotlight's shortcut and unassign it in any other launcher, or pick
another hotkey in Settings later.

1. Download `Ripcord-<version>.zip` from [Releases](https://github.com/meltin/ripcord/releases),
   unzip it and move `Ripcord.app` to `/Applications`.
2. Ripcord is signed with its own self-signed certificate and not notarized, so macOS blocks the
   first launch. Run `xattr -dr com.apple.quarantine /Applications/Ripcord.app`, or Control-click
   the app and choose Open.

Requires macOS 26 or later on Apple silicon.

### Updates

Ripcord looks for a new release once a day and offers to install it, through
[Sparkle](https://sparkle-project.org). Check for Updates is in the menu bar menu, the panel's ⌘K
menu and the search; Settings › General turns the daily check off. 0.1.0 has no updater, so install
the release after it by hand once. A copy installed with Nix is updated by Nix instead.

### With Nix

```sh
nix profile add github:meltin/ripcord
# or try it without installing
nix build github:meltin/ripcord && open result/Applications/Ripcord.app
```

The flake builds with the host's Xcode 26 or later, because SwiftUI's `@State` is a macro whose
plugin ships only with Xcode and nixpkgs' Swift can't expand it. The build therefore runs outside
the Nix sandbox, which macOS's default `sandbox = false` or `relaxed` allows.

## Build from source

Requires Xcode 26 or later.

```sh
scripts/build-app.sh
open build/Ripcord.app
swift test
```

## Permissions

Pasting from Clipboard History or Search Snippets presses ⌘V for you, which needs Ripcord to
be allowed under System Settings › Privacy & Security › Accessibility; Ripcord asks once per
launch, on the first paste. Until then, Return only copies the item and beeps. Snippet keywords
need the same permission to expand.

macOS ties the permission to how the app is signed. A build signed ad hoc, as one made without
the certificate below is, counts as a new app each time, so after an update remove Ripcord from
that list and add it again, or run `tccutil reset Accessibility io.github.meltin.ripcord`. To
build from source and keep the permission across rebuilds, create a signing certificate once:

```sh
scripts/create-signing-certificate.sh
```

It adds a self-signed certificate to your login keychain and asks for your password once, to trust
it for code signing. `scripts/build-app.sh` signs with it from then on. Once after creating it,
remove Ripcord from the Accessibility list (or run the `tccutil reset` command above) and grant it
to the next build; later builds keep it.

Releases after 0.1.0 are signed with the project's own certificate, the same one each time, so an
update keeps the permission. Moving from 0.1.0, which was signed ad hoc, grant it once more.

System Actions use Accessibility for the music and volume keys too, as Window Management does to
move windows. Empty Trash, Toggle System Appearance and Log Out, Restart and Shut Down ask macOS
to let Ripcord control Finder, System Events and the login window; allow it in the prompt, or
later under System Settings › Privacy & Security › Automation.

## Configuration

`~/.config/ripcord/config.json` is created on first launch and re-read every time the panel or
the settings window opens. The settings window writes every change back to it.

```json
{
  "hotkey": "cmd+space",
  "launchAtLogin": false,
  "inputSource": "com.apple.keylayout.ABC",
  "repositories": {
    "folders": ["~/dev"], "depth": 3,
    "openWith": { "return": "/Applications/Visual Studio Code.app", "cmd": "/Applications/Ghostty.app" }
  },
  "colorFormat": "hex",
  "showColorName": false,
  "emoji": { "columns": 8, "primaryAction": "paste", "disableInlinePicker": false },
  "favorites": ["com.apple.Safari", "command:search-snippets"],
  "snippetExpansion": {
    "enabled": true, "mode": "immediately", "withinWords": false,
    "disabledApps": ["com.1password.1password", "com.apple.keychainaccess"]
  },
  "dummyTextLanguage": "ja",
  "clipboardHistory": { "keepFor": "unlimited", "maxEntries": 300 },
  "backdrop": "off",
  "cycleHalves": true,
  "cleanKeyboard": { "defaultDuration": "ask", "lockFunctionKeys": true, "lockMouseClicks": false },
  "coffee": { "preventDisplay": true, "preventSystem": true, "preventDisk": true,
    "preventSleepOnAC": false, "startOnLaunch": false },
  "windowGap": 0,
  "screenGap": 0,
  "lidAwakeLowBattery": 10,
  "snippets": [
    { "name": "Address", "keyword": "addr", "text": "1 Infinite Loop\nCupertino", "icon": "house",
      "tags": ["home"] }
  ],
  "quicklinks": [
    { "name": "Google Search", "keyword": "g", "url": "https://www.google.com/search?q={query}" }
  ],
  "items": {
    "com.1password.1password": { "alias": "pass" },
    "com.apple.Safari": { "hotkey": "ctrl+option+s" },
    "command:quit": { "disabled": true }
  }
}
```

`hotkey` is `cmd`, `option` or `ctrl` (plus `shift` if you like), then `space`, `return`, an
arrow (`left`, `right`, `up`, `down`), a letter or a digit; or one modifier twice, as Raycast
allows: `shift+shift` is ⇧ pressed twice on its own. A double tap needs Accessibility, as snippet
keywords do, and stands aside while a password field has secure input on.
Clipboard History keeps its last 300 unpinned items (plus every pinned one), for as long as
Settings › Clipboard History says (`clipboardHistory`'s `keepFor` is `day`, `week`, `month`,
`threeMonths`, `sixMonths`, `year` or `unlimited`, and `maxEntries` the most kept, Unlimited
saved as 9223372036854775807), in
`~/Library/Application Support/Ripcord/Clipboard`, as plain text and image files; copied files
are kept by path, not copied, so one moved or deleted since can't be pasted. An image over
32 MB or a text over 1 MB isn't kept. Delete the folder to clear it. `disabledApps` lists the
bundle IDs whose copies aren't recorded, `primaryAction` is `paste` or `copy` (what Return does),
and `updateAfterAction` (on by default) moves an entry to the top once it's pasted or copied.
A text copied with formatting keeps it, as an RTF or HTML file in `formats`; `preferPlainText` (on
by default, as Raycast's Prefer pasting as plain text) leaves it out of a paste, while Copy to
Clipboard puts it back either way. `showLinkPreviews` (on by default, as Raycast's Show visual
information for links) fetches favicons and social images with LinkPresentation, keeping them in
`~/Library/Caches/Ripcord/Links`: a Quicklink's or copied link's site home page is requested for
its favicon when its row shows, and a copied link's own address, query and all, once its preview
shows. Off, Ripcord requests nothing.
`textRecognition` (on by default) reads the text in copied images for search, kept in
`history.json`, and `recognitionMode` is `fast` or `accurate`; Accurate also reads Japanese and
other non-Latin scripts. When Fast finds nothing in an image, Ripcord reads it again as Accurate.

`items` holds the aliases, hotkeys and on/off switches set on the settings pages, for apps (by
bundle ID) and Ripcord's commands; a Quicklink keeps its own `hotkey` and `disabled`, and its
`keyword` is its alias.

`snippetExpansion` sets keyword expansion, as Settings › Snippets does: `mode` is `immediately`,
`afterDelimiterKeeping` or `afterDelimiterDiscarding`, and `disabledApps` lists bundle IDs.

`cycleHalves` (on by default) makes a half used again on the same window go ½ → ⅔ → ⅓ and back
to ½, as Raycast's Cycling setting; Settings › Window Management turns it off. `windowGap` and
`screenGap` (0 by default) are Raycast's Window Gap and Screen Gap, in points: the layouts keep
`screenGap` from the screen's edges, and halves, quarters, thirds and fourths keep `windowGap`
between each other. Settings › Window Management picks them from Raycast's sizes (8 to 128).

`backdrop` animates a Metal shader behind the panel's text: `off` (the default), `glow`, `matrix`,
or the name of a `.metal` file in `~/.config/ripcord/shaders`. Pick it under Settings › General,
whose Open Folder button opens that folder. A shader defines one function:

```metal
float4 backdrop(float2 p, Backdrop b) {
  float2 uv = p / b.size;
  return float4(b.accent.rgb, 0.3 * uv.y);
}
```

`p` is the pixel's position in points from the panel's top-left corner; return a straight sRGB
color and its alpha, which Ripcord premultiplies and clips to the panel's corners. `b` holds the
panel's `size`, `time` since it showed, `dark` (1 or 0), the system `accent` color (`.rgb`),
`keystroke` (seconds since the query last changed), `query` (its length) and `field` (the search
field's height). A file can be at most 32 KB. It's read each time the panel or Settings opens;
one that doesn't compile keeps the last that did, and Settings › General shows why. It runs on
the GPU for every pixel while the panel shows, so a heavy one slows the panel; under Reduce
Motion or Low Power Mode it holds still.

`inputSource` is the keyboard input source the panel switches to while it's open, so a Japanese
input method left on doesn't turn the query into kana; the previous one comes back when it closes.
Leave it out to keep whatever is on. Pick it under Settings > General.

## Command line

The app carries a `ripcord` command, at `Ripcord.app/Contents/MacOS/ripcord-cli`. Link it onto
your `PATH` yourself; a Nix install puts it in the profile's `bin` already.

```sh
ln -s /Applications/Ripcord.app/Contents/MacOS/ripcord-cli ~/.local/bin/ripcord
```

It talks to the running app, which has to be open:

- `ripcord open [--query TEXT]` opens the panel, with `TEXT` typed in the search field if given.
  A panel already open stays open.
- `ripcord pick [--placeholder TEXT] < lines` lists the lines it's given in the panel and prints
  the one picked with Return. Up to 10,000 lines are read; the rest are left out. Esc, or the
  panel closing any other way, picks nothing. Another `pick` replaces the one waiting.
- `ripcord config get [KEY]` prints the config file, or one top-level key's value as JSON (its
  default when the file leaves it out).
- `ripcord config set KEY JSON` sets a top-level key, as in
  `ripcord config set colorFormat '"rgb"'`. Give a key's whole value, as `config get KEY` prints
  it; `null` clears one that can be left out, such as `inputSource`. A key the config doesn't
  have, or a value it can't take, is refused and the file is left alone.

It exits with 0 when done, 1 when a pick was left without one, 2 on an error (Ripcord isn't
running, or the value was refused) and 64 for arguments it doesn't take.

### MCP server

`ripcord mcp` serves the same controls to an agent such as Claude over the Model Context Protocol,
on stdin and stdout. Register it with your client, for example:

```json
{
  "mcpServers": {
    "ripcord": {
      "command": "/Applications/Ripcord.app/Contents/MacOS/ripcord-cli",
      "args": ["mcp"]
    }
  }
}
```

Its tools are `open_panel`, `pick` (waits for you to pick a line), `get_config` and `set_config`
(checks the value and applies it, or refuses it and changes nothing). An agent you give it can read
your whole config, snippets and Quicklinks included, and change any setting. It speaks the
protocol versions that begin with `initialize` (2024-11-05 to 2025-11-25). A cancelled tool call
isn't stopped: a pick waits until you pick or close the panel.

The app listens on a socket in your user's temporary folder, readable and writable by your user
only. Any process running as you can use it, as it could edit the config file itself. It can open
the panel, ask you to pick, and read and write the config, nothing more: it doesn't run commands,
paste, or read Clipboard History itself. A config it writes can still change what your own actions
do later, such as the snippets a keyword expands to or the folders Script Commands come from.

## Known limitations

Things Ripcord leaves as they are rather than work around with something macOS doesn't support:

- Notes: with Ripcord Notes and another app's floating window that doesn't bring its app forward,
  such as Raycast Notes, both open, clicking the other one can leave the keys with Ripcord Notes
  ([#73](https://github.com/meltin/ripcord/issues/73)). Clicking any ordinary app moves them as
  usual.
- System Actions: there's no Dismiss Notifications, as Raycast has. macOS offers no way for an app
  to clear Notification Center; the only route is pressing its buttons through Accessibility, which
  breaks as macOS changes them ([#30](https://github.com/meltin/ripcord/issues/30)).

## Roadmap

Planned work lives in [Issues](https://github.com/meltin/ripcord/issues): clipboard history,
snippets, window management, an emoji picker, notes, local Git repositories, Markdown bookmarks,
CleanShot X commands and more small tools that replace Raycast extensions.

## License

Ripcord is licensed under [MIT](./LICENSE).

The GitHub icon in the panel's actions comes from [it-icons](https://github.com/ouka-lab/it-icons), under
[MIT](./Resources/ThirdParty/GitHub-LICENSE.txt).
The emoji names come from Unicode's [CLDR](https://github.com/unicode-org/cldr-json) and
[emoji-test.txt](https://unicode.org/Public/emoji/latest/emoji-test.txt), under the
[Unicode License](./Resources/ThirdParty/Unicode-LICENSE.txt).
The other icons are [Tabler Icons](https://github.com/tabler/tabler-icons), under
[MIT](./Resources/ThirdParty/Tabler-LICENSE.txt).
Generate Dummy Text's word lists come from Raycast's
[Japanese Lorem Ipsum Generator](https://github.com/raycast/extensions/tree/main/extensions/lipsum),
under [MIT](./Resources/ThirdParty/Lipsum-LICENSE.txt).
Updates come through [Sparkle](https://github.com/sparkle-project/Sparkle), under
[its license](./Resources/ThirdParty/Sparkle-LICENSE.txt).
