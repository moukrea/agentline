#!/usr/bin/env bash
# agentline installer for Claude Code and Codex.
#
#   curl -fsSL https://raw.githubusercontent.com/moukrea/agentline/main/install.sh | bash
#
# Piped like this it downloads the latest release first. Idempotent: re-run it
# any time, it only rewrites what differs. Each config file it edits is backed
# up once, before its first change; a status line you had before is kept aside
# and restored by --uninstall.
set -euo pipefail

REPO=${AGENTLINE_REPO:-moukrea/agentline}
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/agentline"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/agentline"
CONF="$CONF_DIR/config"
BIN_DIR="${AGENTLINE_BIN_DIR:-$HOME/.local/bin}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_CONFIG="$CODEX_DIR/config.toml"
TAG='# agentline'

FONTS_URL="https://github.com/$REPO/blob/main/docs/fonts.md"
die() { echo "agentline: $*" >&2; exit 1; }

# Is a Nerd Font installed? (AGENTLINE_ASSUME_NERD=1/0 overrides, for tests.)
have_nerd_font() {
    if [ -n "${AGENTLINE_ASSUME_NERD:-}" ]; then [ "$AGENTLINE_ASSUME_NERD" = 1 ]; return; fi
    if command -v fc-list >/dev/null 2>&1 && fc-list : family 2>/dev/null | grep -qi 'nerd font'; then return 0; fi
    local d
    for d in "$HOME/Library/Fonts" /Library/Fonts "$HOME/.local/share/fonts" "$HOME/.fonts"; do
        [ -d "$d" ] && [ -n "$(find "$d" -iname '*nerd*' -print -quit 2>/dev/null)" ] && return 0
    done
    return 1
}

# Codex items closest to the Claude Code segments shown (the "mirror" option).
mirror_items() { # mirror_items "<segments>" → stdout, space-separated
    local s=" $1 " out=""
    [[ $s == *" model "* ]] && out+="model-with-reasoning " || { [[ $s == *" effort "* ]] && out+="reasoning "; }
    [[ $s == *" dir "* ]] && out+="current-dir "
    [[ $s == *" git "* ]] && out+="git-branch "
    [[ $s == *" session "* ]] && out+="thread-title "
    [[ $s == *" ctx "* ]] && out+="context-used "
    [[ $s == *" 5h "* ]] && out+="five-hour-limit "
    [[ $s == *" 7d "* ]] && out+="weekly-limit "
    [[ $s == *" cost "* ]] && out+="estimated-thread-cost "
    echo "${out% }"
}

# fetch_source <dir>: put the agentline sources in <dir>. $AGENTLINE_SOURCE (a
# directory or .tar.gz) wins, then $AGENTLINE_REF, then the latest release.
fetch_source() {
    local dest=$1 ref
    mkdir -p "$dest"
    if [ -n "${AGENTLINE_SOURCE:-}" ]; then
        if [ -d "$AGENTLINE_SOURCE" ]; then cp -R "$AGENTLINE_SOURCE/." "$dest/"
        else tar xzf "$AGENTLINE_SOURCE" -C "$dest" --strip-components=1; fi
        return
    fi
    command -v curl >/dev/null || die "curl is required"
    ref=${AGENTLINE_REF:-$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)}
    curl -fsSL "https://codeload.github.com/$REPO/tar.gz/${ref:-main}" | tar xz -C "$dest" --strip-components=1
}

# Piped from curl (no sources next to this script): fetch them, then run the
# installer they contain with the same arguments.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)
if [ ! -f "$SRC/claude/statusline.sh" ]; then
    tmp=$(mktemp -d)
    fetch_source "$tmp" || die "could not download agentline from github.com/$REPO"
    AGENTLINE_FETCHED="$tmp" exec bash "$tmp/install.sh" "$@"
fi
VERSION=$(cat "$SRC/VERSION" 2>/dev/null || echo dev)

usage() {
    cat <<'EOF'
Usage: install.sh [targets] [options]      (or: agentline <command>)

Targets (default: the agents installed last time, else every agent found)
  --claude              Claude Code status line
  --codex               Codex status line preset

Options
  --configure           Run the setup assistant (it also runs on first install)
  --glyphs SET          nerd (default, needs a Nerd Font, see README) | unicode
  --bar STYLE           context / 5h / 7d bars; STYLE is one of: capsule (default) smooth
                        blocks line segments braille ramp dots bars squares pie none
  --branch-icon ICON    auto | unicode | octicon | powerline | devicon
  --reset-icon ICON     auto | unicode | octicon | mdi-history | mdi-progress-clock | mdi-refresh
  --effort-style STYLE  effort gauge, same styles, or auto = like the bars (default)
  --compact-style STYLE gauges on narrow terminals, same styles (default: ramp)
  --ultra-effect E      rainbow | violet | plain
  --segments "LIST"     Shown parts, among: dir git session meta model effort ctx 5h 7d cache cost lines
  --codex-mirror on|off Codex shows the items closest to the Claude Code parts shown
  --auto-update on|off  One background update check a day
  --update              Install the latest release if it is newer (--force: always)
  --yes                 Never ask; keep the saved configuration
  --quiet               Print nothing unless something fails
  --uninstall           Remove agentline and restore the previous status lines
  --purge               With --uninstall, also delete ~/.config/agentline
  -h, --help            Show this help

Options are saved in ~/.config/agentline/config; omitted ones keep their value.
EOF
}

do_claude=0 do_codex=0 uninstall=0 purge=0 configure=0 update=0 force=0 yes=0 quiet=0
declare -A SET=()
choice() { # choice <flag> <value> <allowed...>
    local flag=$1 value=$2; shift 2
    for a in "$@"; do [ "$value" = "$a" ] && return 0; done
    echo "agentline: invalid value '$value' for $flag (allowed: $*)" >&2; exit 2
}
while [ $# -gt 0 ]; do
    case $1 in
        --claude) do_claude=1 ;;
        --codex) do_codex=1 ;;
        --configure) configure=1 ;;
        --glyphs) choice "$1" "${2-}" unicode nerd; SET[GLYPHS]=$2; shift ;;
        --bar) choice "$1" "${2-}" capsule smooth blocks line segments braille ramp dots bars squares pie none; SET[BAR]=$2; shift ;;
        --branch-icon) choice "$1" "${2-}" auto unicode octicon powerline devicon; SET[BRANCH_ICON]=$2; shift ;;
        --reset-icon) choice "$1" "${2-}" auto unicode octicon mdi-history mdi-progress-clock mdi-refresh; SET[RESET_ICON]=$2; shift ;;
        --effort-style) choice "$1" "${2-}" auto capsule smooth blocks line segments braille ramp dots bars squares pie none; SET[EFFORT_STYLE]=$2; shift ;;
        --compact-style) choice "$1" "${2-}" capsule smooth blocks line segments braille ramp dots bars squares pie none; SET[COMPACT_STYLE]=$2; shift ;;
        --ultra-effect) choice "$1" "${2-}" rainbow violet plain; SET[ULTRA_EFFECT]=$2; shift ;;
        --segments) SET[SEGMENTS]=${2-}; shift ;;
        --codex-mirror) choice "$1" "${2-}" on off; [ "$2" = on ] && SET[CODEX_MIRROR]=1 || SET[CODEX_MIRROR]=0; shift ;;
        --auto-update) choice "$1" "${2-}" on off; [ "$2" = on ] && SET[AUTO_UPDATE]=1 || SET[AUTO_UPDATE]=0; shift ;;
        --update) update=1 ;;
        --force) force=1 ;;
        --yes|-y) yes=1 ;;
        --quiet|-q) quiet=1 ;;
        --uninstall) uninstall=1 ;;
        --purge) purge=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "agentline: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

ok()   { ((quiet)) || printf '  \033[32m✓\033[0m %s\n' "$*"; }
same() { ((quiet)) || printf '  \033[2m· %s (unchanged)\033[0m\n' "$*"; }
note() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
say()  { ((quiet)) || printf '%s\n' "$*"; }

# ── Update: fetch the latest release, hand over to its installer ───────────
if ((update)); then
    tmp=$(mktemp -d)
    fetch_source "$tmp" || { rm -rf "$tmp"; die "update check failed (network, or github.com/$REPO unreachable)"; }
    new=$(cat "$tmp/VERSION" 2>/dev/null || echo "?")
    installed=$(cat "$DATA/current/VERSION" 2>/dev/null || echo none)
    if [ "$new" = "$installed" ] && ((!force)); then
        rm -rf "$tmp"; say "agentline $installed is up to date."; exit 0
    fi
    say "agentline $installed → $new"
    args=(--yes); ((quiet)) && args+=(--quiet)
    AGENTLINE_FETCHED="$tmp" exec bash "$tmp/install.sh" "${args[@]}"
fi

# Targets: explicit flags, else what was installed last time, else what exists.
if ((!do_claude && !do_codex)); then
    if [ -r "$DATA/targets" ]; then
        grep -qx claude "$DATA/targets" && do_claude=1
        grep -qx codex "$DATA/targets" && do_codex=1
    fi
    if ((!do_claude && !do_codex)); then
        { command -v claude >/dev/null || [ -d "$CLAUDE_DIR" ]; } && do_claude=1
        { command -v codex >/dev/null || [ -d "$CODEX_DIR" ]; } && do_codex=1
    fi
    ((do_claude || do_codex)) || die "neither Claude Code nor Codex found; pass --claude or --codex"
fi

# write_file <dest> <mode> < content: atomic, only when the content differs.
write_file() {
    local dest=$1 mode=$2 tmp
    tmp=$(mktemp "$dest.agentline.XXXXXX")
    cat > "$tmp"
    if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then rm -f "$tmp"; return 1; fi
    chmod "$mode" "$tmp"; mv -f "$tmp" "$dest"
}
backup_once() { # the first backup is the pre-agentline state; never overwritten
    [ -f "$1" ] && [ ! -e "$1.agentline-backup" ] && cp -p "$1" "$1.agentline-backup" || true
}

# ── Claude Code ────────────────────────────────────────────────────────────
claude_install() {
    say "Claude Code"
    command -v jq >/dev/null || { note "jq is required (apt install jq / brew install jq)"; return 1; }
    mkdir -p "$DATA" "$CLAUDE_DIR"
    if write_file "$DATA/claude-statusline.sh" 755 < "$SRC/claude/statusline.sh"; then ok "script → $DATA/claude-statusline.sh"
    else same "script"; fi

    local cmd desired current
    cmd="bash \"$DATA/claude-statusline.sh\""
    desired=$(jq -cn --arg c "$cmd" '{type: "command", command: $c, refreshInterval: 1}')
    [ -f "$CLAUDE_SETTINGS" ] || echo '{}' > "$CLAUDE_SETTINGS"
    current=$(jq -c '.statusLine // null' "$CLAUDE_SETTINGS")
    if [ "$current" = "$desired" ]; then same "statusLine in $CLAUDE_SETTINGS"; return 0; fi
    if [ "$current" != null ] && [[ $current != *agentline* ]] && [ ! -e "$DATA/claude-previous-statusline.json" ]; then
        printf '%s\n' "$current" > "$DATA/claude-previous-statusline.json"
        ok "previous statusLine kept for --uninstall"
    fi
    backup_once "$CLAUDE_SETTINGS"
    jq --argjson d "$desired" '.statusLine = $d' "$CLAUDE_SETTINGS" | write_file "$CLAUDE_SETTINGS" 600 || true
    ok "statusLine in $CLAUDE_SETTINGS (refreshInterval 1 s)"
}

claude_uninstall() {
    say "Claude Code"
    local current prev="$DATA/claude-previous-statusline.json"
    if [ -f "$CLAUDE_SETTINGS" ] && command -v jq >/dev/null; then
        current=$(jq -c '.statusLine // null' "$CLAUDE_SETTINGS")
        if [[ $current == *agentline* ]]; then
            if [ -f "$prev" ]; then
                jq --slurpfile p "$prev" '.statusLine = $p[0]' "$CLAUDE_SETTINGS" | write_file "$CLAUDE_SETTINGS" 600 || true
                ok "previous statusLine restored"
            else
                jq 'del(.statusLine)' "$CLAUDE_SETTINGS" | write_file "$CLAUDE_SETTINGS" 600 || true
                ok "statusLine removed"
            fi
        else same "statusLine (not agentline's)"; fi
    fi
    rm -f "$prev" "$DATA/claude-statusline.sh"
}

# ── Codex ──────────────────────────────────────────────────────────────────
# Codex has no external status line command: tui.status_line is a list of
# built-in items. Managed lines carry the "# agentline" tag; a status line of
# yours is commented out as "# agentline-replaced: …" and restored on removal.
codex_render() { # codex_render install|uninstall < config.toml > config.toml
    local items
    local list=""
    if grep -qx 'AGENTLINE_CODEX_MIRROR=1' "$CONF" 2>/dev/null; then
        list=$(mirror_items "$(sed -n 's/^AGENTLINE_SEGMENTS="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$CONF")")
        [ -n "$list" ] || grep -q '^AGENTLINE_SEGMENTS=' "$CONF" || list=$(mirror_items "dir git session meta model effort ctx 5h 7d cache cost lines")
    fi
    [ -n "$list" ] || list=$(sed -n 's/^AGENTLINE_CODEX_ITEMS="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$CONF" 2>/dev/null)
    [ -n "$list" ] || list=$(grep -v '^[[:space:]]*\(#\|$\)' "$SRC/codex/preset" | tr '\n' ' ')
    items=$(printf '%s\n' $list | sed 's/.*/"&"/' | paste -sd, - | sed 's/,/, /g')
    awk -v mode="$1" -v tag="$TAG" -v items="$items" '
        # out(): print, flushing the blank lines held back before it.
        function out(l) { while (blanks > 0) { print ""; blanks-- } print l }
        function managed() { out("status_line = [" items "]  " tag); out("status_line_use_colors = true  " tag) }
        function is_header(l) { return l ~ /^[[:space:]]*\[/ }
        # A [tui] table agentline created is held back on uninstall and only
        # printed if it still holds something of the user once our lines are gone.
        function release() { if (held) { out(held_hdr); for (i = 1; i <= nheld; i++) out(heldl[i]); held = 0; nheld = 0 } }
        function keep(l) {
            if (held && l ~ /^[[:space:]]*(#.*)?$/) { heldl[++nheld] = l; return }
            release(); out(l)
        }
        {
            line = $0
            if (line ~ /^[[:space:]]*$/ && !held) { blanks++; next }
            tagged = index(line, tag) && line !~ /^# agentline-replaced: /
            if (is_header(line)) {
                if (held) { held = 0; nheld = 0 }              # created table left empty: drop it
                in_tui = (line ~ /^[[:space:]]*\[tui\]/)
                if (tagged && mode == "uninstall") {
                    if (blanks > 0) blanks--                     # and the blank line added before it
                    held = 1; held_hdr = line; sub(/[[:space:]]*# agentline[[:space:]]*$/, "", held_hdr); next
                }
                out(line)
                if (in_tui && mode == "install") { managed(); seen = 1 }
                next
            }
            if (tagged) next
            if (line ~ /^# agentline-replaced: /) {
                if (mode == "uninstall") { sub(/^# agentline-replaced: /, "", line); keep(line) } else keep(line)
                next
            }
            if (in_tui && mode == "install" && (cont || line ~ /^[[:space:]]*status_line(_use_colors)?[[:space:]]*=/)) {
                keep("# agentline-replaced: " line)
                if (!cont && line ~ /=[[:space:]]*\[/ && line !~ /\]/) cont = 1
                else if (cont && line ~ /\]/) cont = 0
                next
            }
            keep(line)
        }
        END {
            if (mode == "install" && !seen) { blanks = (NR > 0) ? 1 : 0; out("[tui]  " tag); managed() }
            else while (blanks > 0) { print ""; blanks-- }
        }'
}

codex_install() {
    say "Codex"
    mkdir -p "$CODEX_DIR"; [ -f "$CODEX_CONFIG" ] || : > "$CODEX_CONFIG"
    local out; out=$(mktemp)
    codex_render uninstall < "$CODEX_CONFIG" | codex_render install > "$out"
    if command -v python3 >/dev/null && python3 -c 'import tomllib' 2>/dev/null; then
        python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$out" \
            || { rm -f "$out"; note "the edited config.toml would not parse; nothing changed"; return 1; }
    fi
    if cmp -s "$out" "$CODEX_CONFIG"; then rm -f "$out"; same "tui.status_line in $CODEX_CONFIG"; return 0; fi
    backup_once "$CODEX_CONFIG"
    write_file "$CODEX_CONFIG" 600 < "$out" || true; rm -f "$out"
    ok "tui.status_line in $CODEX_CONFIG ($(grep -cv '^[[:space:]]*\(#\|$\)' "$SRC/codex/preset") items)"
}

codex_uninstall() {
    say "Codex"
    [ -f "$CODEX_CONFIG" ] || { same "no config.toml"; return 0; }
    if codex_render uninstall < "$CODEX_CONFIG" | write_file "$CODEX_CONFIG" 600; then ok "tui.status_line restored"
    else same "tui.status_line (not agentline's)"; fi
}

# ── Sources, CLI and configuration ─────────────────────────────────────────
# The installed copy lives in $DATA/current; `agentline` points into it.
sources_install() {
    local new="$DATA/current.new" f
    mkdir -p "$DATA"
    if [ "$SRC" != "$DATA/current" ]; then
        rm -rf "$new"; mkdir -p "$new"
        for f in install.sh VERSION README.md LICENSE claude codex lib bin; do
            [ -e "$SRC/$f" ] && cp -R "$SRC/$f" "$new/"
        done
        if [ -d "$DATA/current" ] && diff -rq "$new" "$DATA/current" >/dev/null 2>&1; then
            rm -rf "$new"; same "agentline $VERSION in $DATA/current"
        else
            rm -rf "$DATA/current.old"; [ -d "$DATA/current" ] && mv "$DATA/current" "$DATA/current.old"
            mv "$new" "$DATA/current"; rm -rf "$DATA/current.old"
            ok "agentline $VERSION → $DATA/current"
        fi
    fi
    mkdir -p "$BIN_DIR"
    if [ "$(readlink "$BIN_DIR/agentline" 2>/dev/null)" = "$DATA/current/bin/agentline" ]; then same "command $BIN_DIR/agentline"
    else ln -sfn "$DATA/current/bin/agentline" "$BIN_DIR/agentline"; ok "command $BIN_DIR/agentline"; fi
    case ":$PATH:" in *":$BIN_DIR:"*) ;; *) ((quiet)) || note "$BIN_DIR is not in your PATH: add it to use the agentline command" ;; esac
}

config_apply() {
    mkdir -p "$CONF_DIR"
    if [ ! -f "$CONF" ]; then
        local glyphs=unicode bar=smooth
        have_nerd_font && glyphs=nerd bar=capsule
        cat > "$CONF" <<EOF
# agentline configuration: shell syntax, read on every render.
# Change it with \`agentline configure\`, or edit it (values: \`agentline --help\`).
# Environment variables with the same names override this file.
AGENTLINE_GLYPHS=$glyphs
AGENTLINE_BAR=$bar
AGENTLINE_BRANCH_ICON=auto
AGENTLINE_RESET_ICON=auto
AGENTLINE_CODEX_MIRROR=1
AGENTLINE_AUTO_UPDATE=1
EOF
        ok "config → $CONF"
    fi
    local k line changed=0
    for k in "${!SET[@]}"; do
        line="AGENTLINE_$k=${SET[$k]}"
        [[ ${SET[$k]} == *" "* || -z ${SET[$k]} ]] && line="AGENTLINE_$k=\"${SET[$k]}\""
        grep -qx "$line" "$CONF" && continue
        if grep -q "^AGENTLINE_$k=" "$CONF"; then sed -i.bak "s|^AGENTLINE_$k=.*|$line|" "$CONF" && rm -f "$CONF.bak"
        else echo "$line" >> "$CONF"; fi
        changed=1
    done
    if ((changed)); then ok "config: $(grep -h '^AGENTLINE_' "$CONF" | tr '\n' ' ')"
    else same "config ($(grep -h '^AGENTLINE_' "$CONF" | tr '\n' ' '))"; fi
}

if ((uninstall)); then
    ((do_claude)) && claude_uninstall
    ((do_codex)) && codex_uninstall
    [ "$(readlink "$BIN_DIR/agentline" 2>/dev/null)" = "$DATA/current/bin/agentline" ] && rm -f "$BIN_DIR/agentline"
    rm -rf "$DATA/current" "$DATA/targets" "$DATA/last-update-check"
    rmdir "$DATA" 2>/dev/null || true
    ((purge)) && rm -rf "$CONF_DIR" && ok "config removed"
    ok "agentline removed"
    exit 0
fi

# The assistant runs on first install and with --configure, when a terminal is
# there to answer (also under `curl | bash`: it reads /dev/tty).
TTY=${AGENTLINE_TTY:-}
if [ -z "$TTY" ] && ( : </dev/tty ) 2>/dev/null && [ -t 1 ]; then TTY=/dev/tty; fi
if [ -n "$TTY" ] && ((!yes)) && { ((configure)) || { [ ! -f "$CONF" ] && ((${#SET[@]} == 0)); }; }; then
    command -v jq >/dev/null || die "jq is required (apt install jq / brew install jq)"
    # shellcheck source=lib/wizard.sh
    . "$SRC/lib/wizard.sh"
    wizard
fi

say "agentline $VERSION"
sources_install
config_apply
rc=0
((do_claude)) && { claude_install || rc=1; }
((do_codex)) && { codex_install || rc=1; }
{ ((do_claude)) && echo claude; ((do_codex)) && echo codex; } > "$DATA/targets"
[ -n "${AGENTLINE_FETCHED:-}" ] && [ "$AGENTLINE_FETCHED" != "$DATA/current" ] && rm -rf "$AGENTLINE_FETCHED"
if ((!quiet)) && grep -q '^AGENTLINE_GLYPHS=nerd' "$CONF" && ! have_nerd_font; then
    printf 'Nerd glyphs are on but no Nerd Font was found: \e]8;;%s\e\\install one\e]8;;\e\\ (%s)\n' "$FONTS_URL" "$FONTS_URL"
fi
exit $rc
