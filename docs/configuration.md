# Configuration

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
  "httpStatusPicture": "none",
  "notes": { "escapeLosesFocus": false, "moveCheckedTasksToBottom": false },
  "quicklinkSettings": { "passSelectedText": false, "showDeleteWarning": true },
  "bookmarksFile": "~/.config/ripcord/bookmarks.md",
  "systemActions": {
    "warnBeforeEmptyingTrash": true, "warnBeforeQuittingAll": true, "quitAllExcluded": [],
    "warnBeforeQuittingOthers": true, "quitOthersExcluded": []
  },
  "favorites": ["com.apple.Safari", "command:search-snippets"],
  "snippetExpansion": {
    "enabled": true, "mode": "immediately", "withinWords": false,
    "disabledApps": ["com.1password.1password", "com.apple.keychainaccess"],
    "showDeleteWarning": true
  },
  "dummyTextLanguage": "ja",
  "datePicker": { "format": "yyyy/MM/dd(E)", "primaryAction": "paste", "separator": ", ",
    "rangeSeparator": "〜", "spacesAroundRange": false },
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
