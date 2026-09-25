# agentline

A two-line status line for AI coding agents in the terminal: the full version for
**Claude Code**, a matching built-in preset for **Codex**.

![agentline: bars, effort gauge, responsive layout, glyphs, live states and ultracode effects](docs/demo.gif)

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
fresh machine) in the directory you run it from, with its real git state (simulated
outside a repository), at your terminal's exact width. The session is read once, so
only the animations move. It re-renders on every change, every
second (animations run) and when you resize the window, so you see the responsive
layout at work. "Preview as" switches the preview to ultracode, near-the-limits or a
cold prompt cache; the preview also narrows itself while you pick compact gauges and
shows ultracode while you pick its effect. Defaults are Nerd icons and capsule bars
when a Nerd Font is installed, Unicode otherwise, with a link to the font guide. Below, with ↑↓ ←→ and space:

- glyphs, progress bars, compact gauges (narrow terminals), effort gauge,
  ultracode effect, branch and reset icons, automatic updates;
- which parts Claude Code shows (directory, git, session name, model, effort,
  context, limits, cache, cost, edits…);
- for Codex, "Mirror Claude Code" (on by default) ticks the Codex items closest to
  the parts shown on the Claude Code side; the item list folds out to pick by hand.

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
JuliaMono is the only free monospace font that draws every symbol Claude Code uses;
the Nerd symbols provide the icons. Both are free for any use (SIL OFL 1.1, MIT).

The installer uses Nerd icons and capsule bars when it finds a Nerd Font on the
machine, and Unicode glyphs otherwise. Installation per system and terminal
settings: **[docs/fonts.md](docs/fonts.md)**.

## Configuration

`~/.config/agentline/config`, written by the installer and read on every render.
Environment variables with the same names override it.

The three gauges (bars, compact gauges, effort) share one catalogue of styles:
`capsule` (rounded ends, Nerd), `smooth` (eighth-cell bar on a solid rail), `blocks`
`█▒░`, `line` `━╸─`, `segments` `■□`, `braille` `⣿⣀`, `ramp` `▁▂▄▆█`, `dots` `●○`,
`bars` `▰▱`, `squares` `■□`, `pie` (a single circle slice) and `none` (value only).

| Variable | Values | Default |
|---|---|---|
| `AGENTLINE_GLYPHS` | `nerd`, `unicode` | `nerd` when a Nerd Font is installed, else `unicode` |
| `AGENTLINE_BAR` | context, 5h and 7d bars: any style | `capsule` with Nerd glyphs, else `smooth` |
| `AGENTLINE_COMPACT_STYLE` | gauges when the terminal is too narrow for bars: any style | `pie` |
| `AGENTLINE_EFFORT_STYLE` | effort gauge: any style, or `auto` (same as the bars) | `dots` |
| `AGENTLINE_ULTRA_EFFECT` | `rainbow` (drifting gradient), `violet` (Claude Code's ultracode violet with a sweeping highlight), `plain` (static violet); applies to the effort part only | `violet` |
| `AGENTLINE_BRANCH_ICON` | `auto`, `unicode` `⎇`, `octicon`, `powerline`, `devicon` | `auto` |
| `AGENTLINE_RESET_ICON` | `auto`, `unicode` `↻`, `octicon` (history), `mdi-history`, `mdi-progress-clock`, `mdi-refresh` | `auto` |
| `AGENTLINE_SEGMENTS` | shown parts: `dir git session meta model effort ctx 5h 7d cache cost lines` | all |
| `AGENTLINE_CODEX_MIRROR` | `1`: Codex shows the items closest to the Claude Code parts shown; `0`: `AGENTLINE_CODEX_ITEMS` | `1` |
| `AGENTLINE_CODEX_ITEMS` | Codex items, in order (see `codex/preset`) | the preset |
| `AGENTLINE_PATH_COLOR` | `R;G;B` | `215;119;87` (Claude Code's accent) |
| `AGENTLINE_ICON_GAP` | `auto`, `0`, `1`: space after Nerd icons, which are often drawn wider than their cell | `auto` (on with Nerd glyphs) |
| `AGENTLINE_AUTO_UPDATE` | `1`, `0` | `1` |

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
possible there. What you can choose is which items it shows. By default it mirrors
the Claude Code side: model and reasoning, directory, git branch, session title,
context used, 5-hour and weekly limits and estimated cost, minus whatever you hide
in Claude Code. Turn mirroring off to pick items by hand (`AGENTLINE_CODEX_ITEMS`). `status_line_use_colors = true` is set as well.

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

`docs/demo.gif` is recorded from the real renderer with a pinned clock and sample
session: `tools/record-demo.py --fonts DIR` (JuliaMono and Symbols Nerd Font Mono
files in DIR; needs Pillow, ffmpeg and Noto Color Emoji).

## License

MIT
