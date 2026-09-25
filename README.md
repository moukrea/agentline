# agentline

A two-line status line for AI coding agents in the terminal: the full version for
**Claude Code**, a matching built-in preset for **Codex**.

```
~/…/Personal/agentline  ⎇ feat/installer +2 !1 ?3  “Refactor the billing module”          ◇ Concise  Opus 5.5 ▁▂▄▆█ medium
context ██▋       26%  5h ██▋       27% ↻3h29  7d ████▍     44% ↻3d18h           cache 🔥 51m  $10.28 in 3h12  edits +663 −41
```

- **Line 1**: where you are (directory, git branch and status, session name) on the
  left; who answers (output style, model, reasoning effort) on the right.
- **Line 2**: budgets (context window, 5-hour and 7-day limits) on the left; session
  stats (prompt cache, cost and duration, lines edited) on the right. Both right
  blocks line up.

## What it shows

| Segment | Details |
|---|---|
| Directory | In Claude Code's own accent colour. |
| Git | Branch, ahead/behind, then staged, modified, untracked, conflicts, stash (see [Glyphs](#glyphs)). Worktrees get their own icon. Cached 2 s per directory. |
| Effort | 5-step gauge `▁▂▄▆█` coloured from `low` to `max`. **Ultracode** makes the model name, gauge and sparkles cycle through a rainbow. |
| Context | Gradient bar and percentage; the percentage pulses above 85 %. |
| 5h / 7d | Usage bar and percentage. `⚠ 1h20` in red when the current pace reaches the limit before it resets; otherwise the time until reset. |
| Prompt cache | `🔥 51m` while warm, `⏳ 4m` in the last sixth of its TTL, `🧊 cold` once expired. A cold cache makes the next turn re-read the whole context. |
| Cost, duration, edits | From Claude Code's session counters. |

**Responsive**: every segment has progressively shorter forms. When the terminal
narrows, each line gives up the least useful detail first (session name, edits,
labels), then bars turn into the compact `▁▂▄▆█` gauge, then the branch name is
truncated. It stays readable down to about 60 columns.

**Animation**: Claude Code re-renders a status line at most once per second
(`refreshInterval` cannot go below 1), so the ultracode rainbow is designed for one
frame per second: a fine gradient that drifts a little each second instead of
jumping.

**Fast**: one `jq` call per render and cached git and terminal lookups: about 40 ms,
so the 1-second refresh the installer sets (needed for the animations) is cheap.

## Install

Requirements: bash 5, `jq`, `git`, `curl`.

```sh
curl -fsSL https://raw.githubusercontent.com/moukrea/agentline/main/install.sh | bash
```

The first install opens a full-screen setup assistant. At the top, a live preview:
the real status line, drawn from your last Claude Code session (a sample one on a
fresh machine), at your terminal's exact width. It re-renders on every change, every
second (animations run) and when you resize the window, so you see the responsive
layout at work. "Preview as" switches the preview to ultracode, near-the-limits or a
cold prompt cache. Below, with ↑↓ ←→ and space:

- glyphs, progress bars, compact gauges (narrow terminals), effort gauge,
  ultracode effect, branch and reset icons, automatic updates;
- which parts Claude Code shows (directory, git, session name, model, effort,
  context, limits, cache, cost, edits…);
- which items Codex shows.

Enter saves and installs for Claude Code and Codex, whichever are on the machine.

Non-interactive (CI, dotfiles), with options passed through `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/moukrea/agentline/main/install.sh \
  | bash -s -- --yes --glyphs nerd --bar capsule
```

From a clone, `./install.sh` does the same. `./install.sh --help` lists every option.

The installer is idempotent: run it again at any time, it only rewrites what
differs. It backs up each file it edits once (`settings.json.agentline-backup`,
`config.toml.agentline-backup`) and keeps any status line you had configured, so
uninstalling puts it back.

### The `agentline` command

Installed in `~/.local/bin`:

```sh
agentline configure            # run the assistant again
agentline update               # install the latest release if newer
agentline uninstall            # restore the previous status lines
agentline uninstall --purge    # and delete ~/.config/agentline
agentline version
```

### Updates

With automatic updates on (the assistant's default), the status line checks for a
new release at most once a day, in the background: rendering never waits for it.
Your configuration is kept across updates. Turn it off with
`agentline install --auto-update off`, or update by hand with `agentline update`.

## Fonts

**Recommended: [JuliaMono](https://github.com/cormullion/juliamono), with
[Symbols Nerd Font Mono](https://github.com/ryanoasis/nerd-fonts) as fallback.**

Claude Code draws its interface with about 50 symbols (`⏺ ⎿ ⏵ ⏸ ✶ ✻ ✽ ✔ ✗ ⚠ ◉ ❯ …`).
89 free monospace fonts were compared against those symbols and this status line.
JuliaMono is the only one that covers all of them. Iosevka, Iosevka Term and Adwaita
Mono miss one rarely used symbol (`⎯`). Popular fonts (JetBrains Mono, Fira Code,
Cascadia, Hack, Meslo, Monaspace…) miss 9 or more, and your terminal draws those
with whatever fallback font it finds.

JuliaMono has no icons, so Nerd glyphs (`--glyphs nerd`) come from Symbols Nerd
Font Mono. Both fonts are free for any use: JuliaMono is under the SIL Open Font
License 1.1, the Nerd Fonts symbols under MIT (the icon sets inside are MIT,
Apache 2.0, OFL or CC BY 4.0).

Install them:

```sh
# macOS
brew install --cask font-juliamono font-symbols-only-nerd-font

# Linux
mkdir -p ~/.local/share/fonts && cd ~/.local/share/fonts
curl -fLO https://github.com/cormullion/juliamono/releases/latest/download/JuliaMono-ttf.tar.gz
tar xzf JuliaMono-ttf.tar.gz && rm JuliaMono-ttf.tar.gz
curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz
tar xJf NerdFontsSymbolsOnly.tar.xz SymbolsNerdFontMono-Regular.ttf && rm NerdFontsSymbolsOnly.tar.xz
fc-cache -f
```

Then set JuliaMono as the terminal font, with Symbols Nerd Font Mono as fallback:

| Terminal | Setting |
|---|---|
| Ghostty | `font-family = JuliaMono` then `font-family = Symbols Nerd Font Mono` |
| kitty | `font_family JuliaMono` and `symbol_map U+E000-U+F8FF,U+F0000-U+FFFFD Symbols Nerd Font Mono` |
| WezTerm | `font = wezterm.font_with_fallback { 'JuliaMono', 'Symbols Nerd Font Mono' }` |
| Alacritty, GNOME Terminal, iTerm2 | JuliaMono; Nerd symbols come from the system's font fallback |
| VS Code | `"terminal.integrated.fontFamily": "JuliaMono, 'Symbols Nerd Font Mono'"` |

## Configuration

`~/.config/agentline/config`, written by the installer and read on every render.
Environment variables with the same names override it.

| Variable | Values | Default |
|---|---|---|
| `AGENTLINE_GLYPHS` | `unicode`, `nerd` | `unicode` |
| `AGENTLINE_BAR` | `blocks` `█▒░`, `smooth` (eighth-cell bar on a solid rail), `line` `━╸─`, `segments` `■□`, `braille` `⣿⣀`, `capsule` (smooth with rounded Nerd caps) | `blocks` |
| `AGENTLINE_BRANCH_ICON` | `auto`, `unicode` `⎇`, `octicon`, `powerline`, `devicon` | `auto` |
| `AGENTLINE_RESET_ICON` | `auto`, `unicode` `↻`, `octicon` (history), `mdi-history`, `mdi-progress-clock`, `mdi-refresh` | `auto` |
| `AGENTLINE_PATH_COLOR` | `R;G;B` | `215;119;87` (Claude Code's accent) |
| `AGENTLINE_COMPACT_STYLE` | gauge used when a terminal is too narrow for bars: `ramp` `▁▂▄▆█`, `minibar`, `pie` (Nerd circle slices, `◔◑◕` in Unicode), `braille`, `percent` | `ramp` |
| `AGENTLINE_EFFORT_STYLE` | `ramp` `▁▂▄▆█`, `dots` `●●○○○`, `bars` `▰▰▱▱▱`, `squares` `■■□□□`, `text` (word only) | `ramp` |
| `AGENTLINE_ULTRA_EFFECT` | `rainbow` (drifting gradient), `violet` (Claude Code's ultracode violet with a sweeping highlight), `plain` (static violet) | `rainbow` |
| `AGENTLINE_SEGMENTS` | shown parts: `dir git session meta model effort ctx 5h 7d cache cost lines` | all |
| `AGENTLINE_CODEX_ITEMS` | Codex items, in order (see `codex/preset`) | the preset |
| `AGENTLINE_AUTO_UPDATE` | `1`, `0` | `1` |
| `AGENTLINE_ICON_GAP` | `auto`, `0`, `1`: space after Nerd icons, which are often drawn wider than their cell | `auto` (on with Nerd glyphs) |

`auto` icons follow `AGENTLINE_GLYPHS`: octicons with `nerd`, Unicode otherwise.
The preview above uses `unicode` glyphs and `smooth` bars. `capsule` needs Nerd glyphs; with `unicode` it falls back to `smooth`.

### Glyphs

| Git state | `unicode` | `nerd` (octicons) |
|---|---|---|
| staged | `+` | diff-added |
| modified, not staged | `!` | diff-modified |
| untracked | `?` | question |
| conflicts | `=` | alert |
| stash | `$` | stack |
| ahead / behind | `↑` `↓` | arrow-up / arrow-down |
| clean | `✓` | check |

The Unicode set follows [Starship](https://starship.rs)'s conventions.

## Codex

Codex has no external status line command: its `tui.status_line` setting is a list
of items Codex draws itself, so custom glyphs, bars, colours and layout are not
possible there. What you can choose is which items it shows and in what order: the
assistant lists all of them (default: model and reasoning, directory, git branch,
context used, 5-hour and weekly limits, estimated cost), or set
`AGENTLINE_CODEX_ITEMS`. `status_line_use_colors = true` is set as well.

The installer only touches the two keys it manages in `[tui]` (tagged
`# agentline`). A `status_line` of yours is commented out, not deleted, and
`--uninstall` puts it back.

## How ultracode is detected

Claude Code reports ultracode to status lines as effort `xhigh`. The real signal is
the `ultra_effort_enter` / `ultra_effort_exit` entry in the session transcript, or
`"ultracode": true` in the settings. The transcript is read incrementally: only the
bytes added since the previous render.

## Development

```sh
tests/run.sh    # renders every fixture × glyph set × bar style at 17 widths;
                # installs, reinstalls, updates and uninstalls in a throwaway HOME,
                # including a simulated `curl | bash` with scripted assistant answers
```

CI runs ShellCheck and the suite on every push.

## License

MIT
