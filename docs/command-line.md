# Command line

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

## MCP server

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
