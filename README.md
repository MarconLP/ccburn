# ccburn

A live burn-rate screen for Claude Code and Codex spend, in the terminal or in the macOS menu bar.

ccburn reads the transcripts the Claude Code and Codex CLIs already write to disk, prices every
message against [LiteLLM's rate table](https://github.com/BerriAI/litellm), and draws one screen:

- **Pace**: spend rate over the last 5, 15 and 60 minutes and today's average, each with where today ends
  if that pace holds until midnight
- **Today so far**
- **Provider** and **Model** tables: last 60 minutes and today
- **Per-minute cost**: a stacked chart of the last hour

Costs are API-equivalent estimates. They are not what a Claude or ChatGPT subscription bills.

## Terminal

```sh
./ccburn            # redraw every 60 s
./ccburn --once     # one frame, then exit
```

| Flag | |
|---|---|
| `--once` | print one frame and exit |
| `--interval SECONDS` | seconds between redraws (default 60) |
| `--height ROWS` | chart height (default 12) |
| `--width COLUMNS` | screen width (default: the terminal's) |
| `--offline` | never fetch the LiteLLM rate table |
| `--json` | one frame for the menu bar app: the colored screen at table width, the chart's data, the headline numbers |

Needs only `python3` (3.9 or newer), no packages. `make cli` links `~/.local/bin/ccburn` to this checkout.

## Menu bar app

`app/` is a small AppKit app that shows the same screen in a menu bar menu. It runs the bundled
`ccburn --json` every 60 seconds and draws the frame on a character grid, the way a terminal does.
It draws the per-minute chart itself, with bars thinner than a character, so the chart fits the
tables' width instead of needing a column per minute.

```sh
make install        # build, copy to /Applications, start
/Applications/ccburn.app/Contents/MacOS/ccburn --login-item on   # start at login (also in the menu); off | status
```

- Click the number in the menu bar to open the screen. It opens like any system menu bar item, with the
  settings below it: refresh, what the menu bar shows (last 60 min rate, last 5 min rate or today so far),
  launch at login, quit.
- Needs macOS 13 or newer, the Xcode Command Line Tools to build, and `python3` on the machine at run time.
- The build is signed ad hoc for local use. There are no prebuilt releases.

## Configuration

ccburn always scans `~/.claude`, `~/.config/claude`, every directory in `CLAUDE_CONFIG_DIR`
(comma-separated) and `$CODEX_HOME` (default `~/.codex`). If you run Claude Code or Codex from more
config directories, for example one per account, list them in `~/.config/ccburn/config.json`:

```json
{
  "claude_config_dirs": ["~/.claude-work"],
  "codex_homes": []
}
```

The menu bar app has no shell environment, so set up extra profiles here rather than through
environment variables. `CCBURN_CONFIG` points at a different config file.

Caches live in `~/.cache/ccburn/`: the rate table (refreshed daily) and a per-file scan cache.

## Development

```sh
make app            # build/ccburn.app
make snapshot       # render the panel to build/snapshot.png without the menu bar
CCBURN_SCRIPT=./ccburn build/ccburn.app/Contents/MacOS/ccburn   # run the app against the checkout's script
```

## License

MIT
