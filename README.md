# Ripcord

A small, resident launcher for Apple silicon Macs, written in Swift and AppKit.

- Fuzzy-search apps by their localized or file name (`システム設定` and `System Settings` both work)
- Calculator: `1+2*3`, `(1.5+2)^2`, full-width input too; Return copies the result
- Quicklinks: `g swift testing` opens a search, set up in the config file
- ⌘Space shows the panel on Liquid Glass (configurable); opening Ripcord.app again shows it too
- With nothing typed, the panel lists running apps and Quicklinks; with no match, it offers the
  query to each Quicklink
- ⌘K lists the selected row's actions (Open Command ↵, Show in Finder ⇧⌘F, Copy Path or URL
  ⇧⌘C); the … button at the bottom left has Edit Config (⌘,) and Quit Ripcord (⌘Q)

## Build and run

Requires macOS 26 or later and Xcode 26 or later.

```sh
scripts/build-app.sh
open build/Ripcord.app
swift test
```

## Configuration

`~/.config/ripcord/config.json` is created on first launch and re-read every time the panel opens.

```json
{
  "hotkey": "cmd+space",
  "quicklinks": [
    { "name": "Google Search", "keyword": "g", "url": "https://www.google.com/search?q={query}" }
  ]
}
```

`hotkey` is one or more of `cmd`, `option`, `ctrl` and `shift`, then `space`, a letter or a digit.
For the default `cmd+space`, first unassign it in Spotlight or any other launcher that has it.

## Roadmap

1. Panel on Liquid Glass, hotkey, start screen, app search, calculator, Quicklinks (this release)
2. Clipboard history, snippets, window management
3. Local Git repositories, Markdown bookmarks, CleanShot X commands, keep-awake, color picker,
   HTTP status codes, keyboard cleaning mode, sleep timer, Raycast Script Commands
4. Shaders, CLI, MCP

## License

[MIT](./LICENSE)
