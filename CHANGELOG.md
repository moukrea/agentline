# Changelog

All notable changes to agentline. Versions follow [Semantic Versioning](https://semver.org).

## 0.6.7 - 2026-10-01

### Fixed

- In ultracode, Claude Code's effort struck in automodel's route part read
  `xhigh` (what Claude Code's payload says): it reads `ultracode`.
- The number after automodel's why is how likely that relation is (`why_p`,
  automodel 0.19.2), not the effort's confidence; none after `asked`, `kept`…

## 0.6.6 - 2026-10-01

### Changed

- automodel's route part follows automodel 0.19.0: why it made its last decision
  (`extend`, `aside`, `new task`…) before Jev's confidence, and the effort it left
  when it changed it (`xhigh→high · aside 0.59`). The effort Claude Code displays,
  when automodel runs another, is struck through in red (no more "not").

### Fixed

- Behind jaunt's rich view (its `jaunt-statusline` wrapper as `statusLine`), the
  installer and updates read the status line the wrapper chains: agentline's is left
  in place, and one of yours is kept for `--uninstall` instead of the wrapper.

## 0.6.0 - 2026-09-28

### Added

- **Windows**: `irm https://raw.githubusercontent.com/moukrea/agentline/main/install.ps1 | iex`
  finds Git Bash (or installs Git for Windows with winget), installs jq if needed and
  runs the installer there. The status line runs Git's `bash.exe` by its `C:/` path;
  the terminal's width comes from the console, asked in the background.
- CI on macOS (full suite with Homebrew's bash, and `curl | bash` from `/bin/bash`
  3.2) and Windows (install.ps1, render, reinstall, uninstall).

### Added (continued)

- A usage-limit reset on another day says which one, in local time:
  `↻23h19 (Tue 9:00)`, so a reset tomorrow morning is not read as this morning.
  Given up first when the terminal narrows.

### Fixed

- **macOS**: bars and several glyphs came out garbled. macOS's libc takes bytes
  above 0x80 for letters in UTF-8 locales, so bash read `"$REPLY█"` as a
  variable named `REPLY█`; names are now braced (and a test keeps it so). Also a
  UTF-8 locale that exists there (`en_US.UTF-8`; macOS has no `C.UTF-8`).
- Warnings of newer ShellCheck releases (CI was red since 0.5.1).

## 0.5.2 - 2026-09-28

### Changed

- The effort mismatch is shorter and reads the right way round: `medium  not ~~xhigh~~`
  (the effort Claude Code shows, struck through) instead of
  `real effort: medium (Claude Code shows xhigh)` / `(CC: xhigh)`.

## 0.5.1 - 2026-09-28

### Added

- The route part says when automodel's effort differs from the one Claude Code
  shows (its spinner, `/effort`): `real effort: low (Claude Code shows xhigh)`,
  compact `(CC: xhigh)`. From automodel's `claude_effort` (automodel 0.9.0).

## 0.5.0 - 2026-09-27

### Added

- **automodel**: when [automodel](https://github.com/moukrea/automodel) routes the
  session, the model part shows the model it picked (`jev → Opus 5.5`) and the
  effort gauge the effort it picked; its ultracode mode runs the ultracode effect.
  A new **route** part shows how it decided: confidence, `default`, `pinned`,
  `⚠ fallback`, `⚠ catalog`, `⚠ budget` (over automodel's spending cap),
  `⚠ jev: <why>` and `↻ switched|compact|cold`.
  automodel is found through its hook in `settings.json` and asked with
  `automodel statusline --json` (automodel 0.7.0 or later) while the rest
  renders (0.8 s at most); older releases are never called. `AGENTLINE_AUTOMODEL=auto|off`,
  `AGENTLINE_AUTOMODEL_JSON` for a fixed answer.
- **Themes**: `AGENTLINE_THEME=light` for terminals with a light background.
- **Layouts**: `AGENTLINE_LAYOUT=one` for a single line, or a custom spec
  (`"dir git | model route; ctx 5h 7d | cost"`). Every layout degrades with the
  terminal width following one priority order.
- Installer options `--theme`, `--layout` and `--automodel`; the setup assistant
  gets Theme, Layout and automodel routing rows, a "Routing details" part and an
  automodel preview scenario (a sample answer: previews never run automodel).
- Installing over automodel's own status line takes it over and says so;
  uninstalling while automodel is installed gives it its status line back, and
  prints how to chain a status line of yours in automodel's `config.toml`.
- `CHANGELOG.md`.

### Changed

- The config file carries `AGENTLINE_CONFIG_VERSION=2`. Older configs that list
  their parts get `route` next to `effort` (or `model`) once, on install or update.
- The previews of the setup assistant keep their caches to themselves, so the
  "last session" they start from stays your real one.

### Fixed

- Renders were very slow on bash 5.3 (an extglob pattern in the width
  measurement): now about 40 ms, same output.
- Updates never install the unreleased `main` branch: the latest release is found
  from where `github.com/…/releases/latest` redirects (no API rate limit), then
  from the API, and an update that finds no release fails instead. An update
  already on the latest release downloads nothing.
- bash 5 is found on macOS, whose own bash is 3.2: the installer runs itself with
  Homebrew's (or another bash 5), and the Claude Code status line runs it by its
  absolute path instead of the first `bash` in Claude Code's `PATH`; existing
  installs switch on their next install or update. `agentline` no longer needs
  `readlink -f`.
- The cache directory is hardened: private, and used only when it is really
  yours (owner-checked).
- Smaller downloads: release tarballs leave out the 2 MB demo, the tools, tests
  and CI.
- Config values holding `|` (such as layouts) are written and replaced safely;
  values that would break the shell-syntax config file are refused.
- `curl | bash` run from a directory holding a `claude/statusline.sh` (dotfiles)
  installed that script instead of downloading the release.
- Automatic updates never ran on macOS, which has no `setsid`.
- Unicode pie gauges (the default compact gauge without a Nerd Font) were blank
  past 25 %.
- A directory whose path is too long for a cache file name no longer writes
  errors at each render.
- The setup assistant keeps the terminal usable whatever ends it.

## 0.4.2 - 2026-09-25

- New defaults: dots effort gauge, pie compact gauges and the violet ultracode
  effect.
- The demo shows Nerd pie glyphs and labels each setting with its real variable.

## 0.4.1 - 2026-09-25

- The effort gauge follows the bar style by default (`auto`), and ramps stay five steps wide.
- A recorded demo of the configuration options (`docs/demo.gif`).

## 0.4.0 - 2026-09-25

- One catalogue of gauge styles for the bars, compact gauges and effort gauge.
- Codex mirrors the Claude Code parts shown (`AGENTLINE_CODEX_MIRROR`).
- Nerd Font detection picks Nerd icons and capsule bars, or Unicode, and links a
  font guide (`docs/fonts.md`).

## 0.3.0 - 2026-09-25

- A live, full-screen setup assistant: the real status line at your terminal's
  width, re-rendered on every change.
- Toggles for each Claude Code part (`AGENTLINE_SEGMENTS`), a choice of Codex items,
  more gauge styles.

## 0.2.0 - 2026-09-25

First release.

- The two-line status line for Claude Code (directory, git, session, model, effort
  and ultracode, context, 5-hour and 7-day limits, prompt cache, cost, edits) and a
  matching preset for Codex.
- The `curl | bash` installer, the setup assistant, the `agentline` command and
  daily background updates.
