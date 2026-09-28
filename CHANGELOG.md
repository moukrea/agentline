# Changelog

All notable changes to agentline. Versions follow [Semantic Versioning](https://semver.org).

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
