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
- ⌘K lists the selected row's actions (Open Command ↵, Show in Finder ⇧⌘F, Copy Path or URL ⇧⌘C)
- Settings (⌘,): Launch at Login, the hotkey and Quicklinks, kept in sync with the config file
- Shortcuts: give any app, Quicklink or command an alias, a hotkey that runs it from anywhere, or
  turn it off so it never shows up in search
- Clipboard History: copied text and images, including a copied image file such as a CleanShot X
  capture, with a preview and details of the selected one. Return pastes into the app you were in,
  ⇧⌘P pins an item to the top and ⌃X deletes it. Copies a password manager marks as concealed are
  never recorded, and switching the command off on the Shortcuts page stops recording
- Drag the panel anywhere; it remembers the spot, and Reset Ripcord Window Position brings it back

## Quick start

Free ⌘Space first: turn off Spotlight's shortcut and unassign it in any other launcher, or pick
another hotkey in Settings later.

1. Download `Ripcord-<version>.zip` from [Releases](https://github.com/meltin/ripcord/releases),
   unzip it and move `Ripcord.app` to `/Applications`.
2. Ripcord is ad-hoc signed and not notarized, so macOS blocks the first launch. Run
   `xattr -dr com.apple.quarantine /Applications/Ripcord.app`, or Control-click the app and choose
   Open.

Requires macOS 26 or later on Apple silicon.

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

Pasting from Clipboard History presses ⌘V for you, which needs Ripcord to be allowed under
System Settings › Privacy & Security › Accessibility; Ripcord asks once per launch, on the first
paste. Until then, Return only copies the item and beeps. Ripcord is ad-hoc signed, so macOS forgets the
permission whenever a new build replaces the app: after an update, remove Ripcord from that list
and add it again, or run `tccutil reset Accessibility io.github.meltin.ripcord`.

## Configuration

`~/.config/ripcord/config.json` is created on first launch and re-read every time the panel or
the settings window opens. The settings window writes every change back to it.

```json
{
  "hotkey": "cmd+space",
  "launchAtLogin": false,
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

`hotkey` is `cmd`, `option` or `ctrl` (plus `shift` if you like), then `space`, a letter or a
digit.
Clipboard History keeps its last 300 unpinned items (plus every pinned one) in
`~/Library/Application Support/Ripcord/Clipboard`, as plain text and image files; an image over
32 MB or a text over 1 MB isn't kept. Delete the folder to clear it.

`items` holds the Shortcuts page's settings for apps (by bundle ID) and Ripcord's commands; a
Quicklink keeps its own `hotkey` and `disabled`, and its `keyword` is its alias.

## Roadmap

Planned work lives in [Issues](https://github.com/meltin/ripcord/issues): clipboard history,
snippets, window management, an emoji picker, notes, local Git repositories, Markdown bookmarks,
CleanShot X commands and more small tools that replace Raycast extensions.

## License

Ripcord is licensed under [MIT](./LICENSE).
