# Changelog

All notable changes to agentline. Versions follow [Semantic Versioning](https://semver.org).

## 0.5.0 - 2026-09-27

### Added

- **automodel**: when [automodel](https://github.com/moukrea/automodel) routes the
  session, the model part shows the model it picked (`jev → Opus 5.5`) and the
  effort gauge the effort it picked; its ultracode mode runs the ultracode effect.
  A new **route** part shows how it decided: confidence, `default`, `pinned`,
  `⚠ fallback`, `⚠ catalog`, `⚠ jev: <why>` and `↻ switched|compact|cold`.
  automodel is found through its hook in `settings.json` and asked with
  `automodel statusline --json` while the rest renders (0.8 s at most); releases
  without `--json` are never called. `AGENTLINE_AUTOMODEL=auto|off`,
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

- Rendering took seconds on bash 5.3 (an extglob pattern in the width
  measurement): back to a few tens of milliseconds, same output.
- Config values holding `|` (such as layouts) are written and replaced safely;
  values that would break the shell-syntax config file are refused.

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
