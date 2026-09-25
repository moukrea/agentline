#!/usr/bin/env bash
# agentline installer for Claude Code and Codex.
#
# Idempotent: re-run it any time, it only rewrites what differs. Each config
# file it edits is backed up once, before its first change. A status line you
# had before is kept aside and restored by --uninstall.
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/agentline"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/agentline"
CONF="$CONF_DIR/config"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_CONFIG="$CODEX_DIR/config.toml"
TAG='# agentline'

usage() {
    cat <<'EOF'
Usage: ./install.sh [targets] [options]

Targets (default: every agent found on this machine)
  --claude              Claude Code status line
  --codex               Codex status line preset

Options
  --glyphs SET          unicode (default) | nerd  (needs a Nerd Font, see README)
  --bar STYLE           blocks | smooth | line | segments | braille | capsule
  --branch-icon ICON    auto | unicode | octicon | powerline | devicon
  --reset-icon ICON     auto | unicode | octicon | mdi-history | mdi-progress-clock | mdi-refresh
  --uninstall           Remove agentline and restore the previous status lines
  --purge               With --uninstall, also delete ~/.config/agentline
  -h, --help            Show this help

Options are saved in ~/.config/agentline/config; omitted ones keep their value.
EOF
}

do_claude=0 do_codex=0 uninstall=0 purge=0
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
        --glyphs) choice "$1" "${2-}" unicode nerd; SET[GLYPHS]=$2; shift ;;
        --bar) choice "$1" "${2-}" blocks smooth line segments braille capsule; SET[BAR]=$2; shift ;;
        --branch-icon) choice "$1" "${2-}" auto unicode octicon powerline devicon; SET[BRANCH_ICON]=$2; shift ;;
        --reset-icon) choice "$1" "${2-}" auto unicode octicon mdi-history mdi-progress-clock mdi-refresh; SET[RESET_ICON]=$2; shift ;;
        --uninstall) uninstall=1 ;;
        --purge) purge=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "agentline: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
if ((!do_claude && !do_codex)); then
    { command -v claude >/dev/null || [ -d "$CLAUDE_DIR" ]; } && do_claude=1
    { command -v codex >/dev/null || [ -d "$CODEX_DIR" ]; } && do_codex=1
    if ((!do_claude && !do_codex)); then echo "agentline: neither Claude Code nor Codex found; pass --claude or --codex" >&2; exit 1; fi
fi

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
same() { printf '  \033[2m· %s (unchanged)\033[0m\n' "$*"; }
note() { printf '  \033[33m!\033[0m %s\n' "$*"; }

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
    echo "Claude Code"
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
    echo "Claude Code"
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
    items=$(grep -v '^[[:space:]]*\(#\|$\)' "$SRC/codex/preset" | sed 's/.*/"&"/' | paste -sd, - | sed 's/,/, /g')
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
    echo "Codex"
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
    echo "Codex"
    [ -f "$CODEX_CONFIG" ] || { same "no config.toml"; return 0; }
    if codex_render uninstall < "$CODEX_CONFIG" | write_file "$CODEX_CONFIG" 600; then ok "tui.status_line restored"
    else same "tui.status_line (not agentline's)"; fi
}

# ── Configuration file ─────────────────────────────────────────────────────
config_apply() {
    mkdir -p "$CONF_DIR"
    if [ ! -f "$CONF" ]; then
        cat > "$CONF" <<'EOF'
# agentline configuration: shell syntax, read on every render.
# Values: see ./install.sh --help or the README. Environment variables with
# the same names override this file.
AGENTLINE_GLYPHS=unicode
AGENTLINE_BAR=blocks
AGENTLINE_BRANCH_ICON=auto
AGENTLINE_RESET_ICON=auto
EOF
        ok "config → $CONF"
    fi
    local k line changed=0
    for k in "${!SET[@]}"; do
        line="AGENTLINE_$k=${SET[$k]}"
        grep -qx "$line" "$CONF" && continue
        if grep -q "^AGENTLINE_$k=" "$CONF"; then sed -i.bak "s|^AGENTLINE_$k=.*|$line|" "$CONF" && rm -f "$CONF.bak"
        else echo "$line" >> "$CONF"; fi
        changed=1
    done
    if ((changed)); then ok "config updated: $(grep -h '^AGENTLINE_' "$CONF" | tr '\n' ' ')"
    else same "config ($(grep -h '^AGENTLINE_' "$CONF" | tr '\n' ' '))"; fi
}

if ((uninstall)); then
    ((do_claude)) && claude_uninstall
    ((do_codex)) && codex_uninstall
    rmdir "$DATA" 2>/dev/null || true
    ((purge)) && rm -rf "$CONF_DIR" && ok "config removed"
    exit 0
fi

config_apply
rc=0
((do_claude)) && { claude_install || rc=1; }
((do_codex)) && { codex_install || rc=1; }
if grep -q '^AGENTLINE_GLYPHS=nerd' "$CONF"; then
    echo "Nerd glyphs are on: use JuliaMono with Symbols Nerd Font Mono as fallback (see README)."
fi
exit $rc
