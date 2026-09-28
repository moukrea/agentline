#!/usr/bin/env bash
# agentline installer for Claude Code and Codex.
#
#   curl -fsSL https://raw.githubusercontent.com/moukrea/agentline/main/install.sh | bash
#
# Piped like this it downloads the latest release first. Idempotent: re-run it
# any time, it only rewrites what differs. Each config file it edits is backed
# up once, before its first change; a status line you had before is kept aside
# and restored by --uninstall.

# bash 5 first: macOS ships bash 3.2. Everything up to "esac" runs in any bash
# (and in any sh from a file); the first bash 5 found runs this script instead:
# this file again, or, piped (curl | bash), the rest of stdin, which bash reads
# byte by byte and so leaves for the next one.
case ${BASH_VERSION:-} in
    [5-9].*|[1-9][0-9]*) ;;
    *)  s=${BASH_SOURCE:-}   # empty when piped
        if [ -z "${BASH_VERSION:-}" ]; then   # another sh: $0, if it is a script
            s=$0 l=""; [ -f "$s" ] && IFS= read -r l < "$s"
            case $l in '#!'*) ;; *) echo "agentline: run the installer with bash (curl … | bash)" >&2; exit 1 ;; esac
        fi
        for b in /opt/homebrew/bin/bash /usr/local/bin/bash /home/linuxbrew/.linuxbrew/bin/bash /opt/local/bin/bash "$(command -v bash)"; do
            [ -x "$b" ] && "$b" -c '((BASH_VERSINFO[0] >= 5))' 2>/dev/null || continue
            [ -n "$s" ] && exec "$b" "$s" "$@"
            # bash -c "$(curl …)": the script is that string, not stdin.
            [ -n "${BASH_EXECUTION_STRING:-}" ] && exec "$b" -c "$BASH_EXECUTION_STRING" "$0" "$@"
            # shellcheck disable=SC2093  # piped: bash 5 reads the rest of stdin
            exec "$b" -s -- "$@"
        done
        echo "agentline needs bash 5 (macOS: brew install bash jq)" >&2; exit 1 ;;
esac
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
WIN=0; case $OSTYPE in msys*|cygwin*) WIN=1 ;; esac   # Git Bash on Windows (install.ps1)
die() { echo "agentline: $*" >&2; exit 1; }

# Is a Nerd Font installed? (AGENTLINE_ASSUME_NERD=1/0 overrides, for tests.)
have_nerd_font() {
    if [ -n "${AGENTLINE_ASSUME_NERD:-}" ]; then [ "$AGENTLINE_ASSUME_NERD" = 1 ]; return; fi
    if command -v fc-list >/dev/null 2>&1 && fc-list : family 2>/dev/null | grep -qi 'nerd font'; then return 0; fi
    local d
    local win=()
    ((WIN)) && win=("${LOCALAPPDATA:-$HOME/AppData/Local}/Microsoft/Windows/Fonts" "${WINDIR:-C:/Windows}/Fonts")
    for d in "$HOME/Library/Fonts" /Library/Fonts "$HOME/.local/share/fonts" "$HOME/.fonts" "${win[@]}"; do
        [ -d "$d" ] && [ -n "$(find "$d" -iname '*nerd*' -print -quit 2>/dev/null)" ] && return 0
    done
    return 1
}

# Parts (segments) and layout names, as the renderer knows them.
ALL_SEGMENTS="dir git session meta model effort route ctx 5h 7d cache cost lines"
LAYOUT_SEGMENTS=" dir git session meta model effort route ctx 5h 7d cache cost lines "

# Configs before version 2 may list their parts without "route" (the setup
# assistant always saved the full list): it goes right after the effort, else
# after the model, else nowhere.
with_route() { # with_route "<segments>" → REPLY
    local s out="" w=model words
    read -ra words <<<"$1"
    for s in "${words[@]}"; do
        [ "$s" = route ] && { REPLY=$1; return; }
        [ "$s" = effort ] && w=effort
    done
    for s in "${words[@]}"; do out+="$s "; [ "$s" = "$w" ] && out+="route "; done
    REPLY=${out% }
}

# automodel, found like the renderer finds it: its UserPromptSubmit hook
# "<exe> --config <cfg> hook decide" in settings.json. → AM_CMD ("<exe> --config
# <cfg>", as written there), AM_EXE, AM_CFG; returns 1 when absent.
# shellcheck disable=SC2120  # the argument is optional
am_find() { # am_find [settings.json]
    local f=${1:-$CLAUDE_SETTINGS} cmd="" v val
    AM_CMD="" AM_EXE="" AM_CFG=""
    [ -r "$f" ] && command -v jq >/dev/null || return 1
    cmd=$(jq -r 'first((.hooks.UserPromptSubmit? // [])[]?.hooks[]?.command? | strings
        | select(contains("automodel") and endswith(" hook decide"))) // empty' "$f" 2>/dev/null) || cmd=""
    [ -n "$cmd" ] || return 1
    AM_CMD=${cmd% hook decide}
    case $AM_CMD in *" --config "*) AM_EXE=${AM_CMD%% --config *} AM_CFG=${AM_CMD#* --config } ;; *) AM_EXE=$AM_CMD ;; esac
    for v in AM_EXE AM_CFG; do   # as a shell would read them: quotes, ~/
        val=${!v}
        case $val in \"*\"|\'*\') val=${val:1:${#val}-2} ;; esac
        case $val in \~/*) val=$HOME/${val#\~/} ;; esac
        printf -v "$v" '%s' "$val"
    done
    [[ $AM_EXE == */* ]] || AM_EXE=$(type -P "$AM_EXE" || echo "$AM_EXE")
    return 0
}
# Does this automodel release have `statusline --json`? Older ones would run
# their chained status line instead, so agentline never calls them.
am_has_json() {
    [ -x "$AM_EXE" ] || return 1
    local t=(); command -v timeout >/dev/null && t=(timeout 3)
    "${t[@]}" "$AM_EXE" help </dev/null 2>/dev/null | grep -q 'statusline.*--json'
}
is_am_statusline() { # is_am_statusline "<command>": automodel's own status line?
    [[ $1 == *automodel* && $1 == *" statusline" ]]
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

# latest_tag: the tag of the latest release (vX.Y.Z) → REPLY. From where
# github.com/<repo>/releases/latest redirects (no API rate limit), else from the
# API; returns 1 when neither names one.
latest_tag() {
    local tag
    tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null) || tag=""
    tag=${tag##*/}
    if [[ ! $tag =~ ^v[0-9][0-9A-Za-z.+-]*$ ]]; then
        tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
            | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1) || tag=""
        [[ $tag =~ ^v[0-9][0-9A-Za-z.+-]*$ ]] || return 1
    fi
    REPLY=$tag
}

# release_ref: what to install → REPLY: $AGENTLINE_REF, else the latest
# release's tag. Never the unreleased main branch, unless AGENTLINE_REF=main
# asks for it: says why and returns 1 when no release is found.
release_ref() {
    REPLY=${AGENTLINE_REF:-}
    [ -n "$REPLY" ] && return 0
    command -v curl >/dev/null || die "curl is required"
    latest_tag && return 0
    echo "agentline: no release found at github.com/$REPO (network, or GitHub's rate limit); AGENTLINE_REF=vX.Y.Z picks one" >&2
    return 1
}

# fetch_source <dir> [ref]: put the agentline sources in <dir>: those of
# $AGENTLINE_SOURCE (a directory or .tar.gz) when set, else <ref>'s, by default
# release_ref's.
fetch_source() {
    local dest=$1 ref=${2:-}
    mkdir -p "$dest"
    if [ -n "${AGENTLINE_SOURCE:-}" ]; then
        if [ -d "$AGENTLINE_SOURCE" ]; then cp -R "$AGENTLINE_SOURCE/." "$dest/"
        else tar xzf "$AGENTLINE_SOURCE" -C "$dest" --strip-components=1; fi
        return
    fi
    command -v curl >/dev/null || die "curl is required"
    if [ -z "$ref" ]; then release_ref || return 1; ref=$REPLY; fi
    curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$ref" | tar xz -C "$dest" --strip-components=1 && [ -f "$dest/install.sh" ]
}

# Piped from curl (no sources next to this script): fetch them, then run the
# installer they contain with the same arguments. Piped, there is no script
# file: never the current directory, which may hold another claude/statusline.sh.
SRC=""
[ -n "${BASH_SOURCE[0]:-}" ] && SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
if [ -z "$SRC" ] || [ ! -f "$SRC/claude/statusline.sh" ]; then
    tmp=$(mktemp -d)
    fetch_source "$tmp" || { rm -rf "$tmp"; die "could not download agentline from github.com/$REPO"; }
    AGENTLINE_FETCHED="$tmp" exec "$BASH" "$tmp/install.sh" "$@"
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
  --effort-style STYLE  effort gauge, same styles, or auto = like the bars (default: dots)
  --compact-style STYLE gauges on narrow terminals, same styles (default: pie)
  --ultra-effect E      rainbow | violet | plain
  --segments "LIST"     Shown parts, among: dir git session meta model effort route ctx 5h 7d cache cost lines
  --theme THEME         dark (default) | light: the terminal's background
  --layout LAYOUT       two (default) | one | a custom "left | right; left | right" spec
                        (lines separated by ";", parts from the list above)
  --automodel auto|off  auto (default): when automodel routes the session, show the
                        model and effort it chose and how (the route part) | off
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
safe() { # safe <flag> <value>: written between double quotes in the config
    case $2 in *[\"\\\$\`]*|*$'\n'*) echo "agentline: $1 cannot contain \", \\, \$, \` or a newline" >&2; exit 2 ;; esac
}
layout_ok() { # two, one, or a spec naming at least one known part
    local s known="" words
    case $1 in two|one) return 0 ;; esac
    safe --layout "$1"
    read -ra words <<<"${1//[|;]/ }"
    for s in "${words[@]}"; do [[ $LAYOUT_SEGMENTS == *" $s "* ]] && known=1; done
    [ -n "$known" ] && return 0
    echo "agentline: invalid --layout '$1': two, one, or lines like \"dir git | model route; ctx 5h 7d | cost\"" >&2
    echo "  (parts: $ALL_SEGMENTS)" >&2; exit 2
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
        --segments) safe "$1" "${2-}"; SET[SEGMENTS]=$2; shift ;;
        --theme) choice "$1" "${2-}" dark light; SET[THEME]=$2; shift ;;
        --layout) layout_ok "${2-}"; SET[LAYOUT]=$2; shift ;;
        --automodel) choice "$1" "${2-}" auto off; SET[AUTOMODEL]=$2; shift ;;
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
    installed=$(cat "$DATA/current/VERSION" 2>/dev/null || echo none)
    ref=""
    if [ -z "${AGENTLINE_SOURCE:-}" ]; then
        release_ref || exit 1
        ref=$REPLY
        # Already the installed release: nothing to download.
        if [ "${ref#v}" = "$installed" ] && ((!force)); then say "agentline $installed is up to date."; exit 0; fi
    fi
    tmp=$(mktemp -d)
    fetch_source "$tmp" "$ref" || { rm -rf "$tmp"; die "update failed: could not download agentline${ref:+ $ref} from github.com/$REPO"; }
    new=$(cat "$tmp/VERSION" 2>/dev/null || echo "?")
    if [ "$new" = "$installed" ] && ((!force)); then
        rm -rf "$tmp"; say "agentline $installed is up to date."; exit 0
    fi
    say "agentline $installed → $new"
    args=(--yes); ((quiet)) && args+=(--quiet)
    AGENTLINE_FETCHED="$tmp" exec "$BASH" "$tmp/install.sh" "${args[@]}"
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
# The command Claude Code runs: bash 5 by its absolute path, as Claude Code's
# PATH may find an older bash first (macOS: /bin/bash 3.2), and a bare `bash`
# from older releases is replaced. A bash 5 the current command already names
# is kept, so running the installer from another PATH changes nothing.
statusline_cmd() { # statusline_cmd "<current command>" → REPLY
    local script="\"$DATA/claude-statusline.sh\"" b=""
    if ((WIN)); then
        # Windows: C:/… paths, which Git Bash and cmd.exe both run, and Git's
        # bin/bash.exe, which sets up the PATH (jq, git) whoever starts it.
        b="$(cygpath -m /)"; b="${b%/}/bin/bash.exe"; [ -x "$b" ] || b=$(cygpath -m "$BASH")
        REPLY="\"$b\" \"$(cygpath -m "$DATA/claude-statusline.sh")\""
        return
    fi
    [[ $1 == *" $script" ]] && b=${1%" $script"} && b=${b#\"} && b=${b%\"}
    [[ $b == /* && -x $b ]] && "$b" -c '((BASH_VERSINFO[0] >= 5))' 2>/dev/null || b=$BASH
    [[ $b =~ ^[A-Za-z0-9_./+-]+$ ]] || b="\"$b\""
    REPLY="$b $script"
}
claude_install() {
    say "Claude Code"
    command -v jq >/dev/null || { note "jq is required (apt install jq / brew install jq / winget install jqlang.jq)"; return 1; }
    mkdir -p "$DATA" "$CLAUDE_DIR"
    if write_file "$DATA/claude-statusline.sh" 755 < "$SRC/claude/statusline.sh"; then ok "script → $DATA/claude-statusline.sh"
    else same "script"; fi

    local desired current current_cmd
    [ -f "$CLAUDE_SETTINGS" ] || echo '{}' > "$CLAUDE_SETTINGS"
    current=$(jq -c '.statusLine // null' "$CLAUDE_SETTINGS")
    current_cmd=$(jq -r '.statusLine.command? // empty' "$CLAUDE_SETTINGS" 2>/dev/null) || current_cmd=""
    statusline_cmd "$current_cmd"
    desired=$(jq -cn --arg c "$REPLY" '{type: "command", command: $c, refreshInterval: 1}')
    if [ "$current" = "$desired" ]; then same "statusLine in $CLAUDE_SETTINGS"; return 0; fi
    if [ "$current" != null ] && [[ $current != *agentline* ]] && [ ! -e "$DATA/claude-previous-statusline.json" ]; then
        printf '%s\n' "$current" > "$DATA/claude-previous-statusline.json"
        ok "previous statusLine kept for --uninstall"
    fi
    backup_once "$CLAUDE_SETTINGS"
    jq --argjson d "$desired" '.statusLine = $d' "$CLAUDE_SETTINGS" | write_file "$CLAUDE_SETTINGS" 600 || true
    ok "statusLine in $CLAUDE_SETTINGS (refreshInterval 1 s)"
    # automodel's own status line: agentline takes over and shows its routing
    # (the model and effort it chose, and the route part) by asking automodel.
    if is_am_statusline "$current_cmd"; then
        note "the status line was automodel's: agentline now shows automodel's routing itself"
        if grep -qx 'AGENTLINE_AUTOMODEL=\(off\|0\)' "$CONF" 2>/dev/null; then
            note "AGENTLINE_AUTOMODEL=off hides it: agentline install --automodel auto"
        elif am_find && ! am_has_json; then
            note "this automodel release has no \`statusline --json\`: update it (automodel update) to see its routing here"
        fi
    fi
}

claude_uninstall() {
    say "Claude Code"
    local current restored="" prev="$DATA/claude-previous-statusline.json"
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
            # automodel still installed: its own status line shows its routing
            # again. A status line of yours can run behind it, as its chained command.
            restored=$(jq -r '.statusLine.command? // empty' "$CLAUDE_SETTINGS" 2>/dev/null) || restored=""
            if ! am_find; then
                # automodel's status line, but automodel was uninstalled since.
                if is_am_statusline "$restored"; then
                    jq 'del(.statusLine)' "$CLAUDE_SETTINGS" | write_file "$CLAUDE_SETTINGS" 600 || true
                    ok "statusLine removed: the previous one was automodel's, which is no longer installed"
                fi
            elif ! is_am_statusline "$restored"; then
                jq --arg c "$AM_CMD statusline" '.statusLine = {type: "command", command: $c}' "$CLAUDE_SETTINGS" \
                    | write_file "$CLAUDE_SETTINGS" 600 || true
                ok "statusLine → automodel's ($AM_CMD statusline): it shows its routing again"
                if [ -n "$restored" ]; then
                    note "your status line ($restored) gave way to automodel's; to show it before automodel's segment, add"
                    note "  statusline_command = $(jq -n --arg c "$restored" '$c')"
                    note "at the top of ${AM_CFG:-the automodel config.toml}"
                fi
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
        [ -n "$list" ] || grep -q '^AGENTLINE_SEGMENTS=' "$CONF" || list=$(mirror_items "$ALL_SEGMENTS")
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
        for f in install.sh VERSION README.md CHANGELOG.md LICENSE claude codex lib bin; do
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
    if ((WIN)); then   # no symlinks without developer mode: a two-line wrapper
        if printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$DATA/current/bin/agentline" | write_file "$BIN_DIR/agentline" 755; then
            ok "command $BIN_DIR/agentline"; else same "command $BIN_DIR/agentline"; fi
    elif [ "$(readlink "$BIN_DIR/agentline" 2>/dev/null)" = "$DATA/current/bin/agentline" ]; then same "command $BIN_DIR/agentline"
    else ln -sfn "$DATA/current/bin/agentline" "$BIN_DIR/agentline"; ok "command $BIN_DIR/agentline"; fi
    case ":$PATH:" in *":$BIN_DIR:"*) ;; *) ((quiet)) || note "$BIN_DIR is not in your PATH: add it to use the agentline command" ;; esac
}

# conf_set <KEY> <value>: set AGENTLINE_KEY in the config, in place, quoted
# when needed (values never hold " \ $ `). Returns 1 when it already is.
conf_set() {
    local line="AGENTLINE_$1=$2" tmp
    [[ $2 =~ ^[A-Za-z0-9_.,:/+%@=-]+$ ]] || line="AGENTLINE_$1=\"$2\""
    grep -qxF -- "$line" "$CONF" && return 1
    tmp=$(mktemp "$CONF.XXXXXX")
    if grep -q "^AGENTLINE_$1=" "$CONF"; then
        K="AGENTLINE_$1=" L=$line awk 'index($0, ENVIRON["K"]) == 1 { if (!done) print ENVIRON["L"]; done = 1; next } { print }' "$CONF" > "$tmp"
    else cat "$CONF" > "$tmp"; printf '%s\n' "$line" >> "$tmp"; fi
    cat "$tmp" > "$CONF"; rm -f "$tmp"
}
conf_get() { # conf_get <KEY> → REPLY, unquoted; returns 1 when not set
    local line
    line=$(grep "^AGENTLINE_$1=" "$CONF" | tail -n 1) || return 1
    REPLY=${line#*=}
    case $REPLY in \"*\"|\'*\') REPLY=${REPLY:1:${#REPLY}-2} ;; esac
}

config_apply() {
    mkdir -p "$CONF_DIR"
    local changed=0 k
    if [ ! -f "$CONF" ]; then
        local glyphs=unicode bar=smooth
        have_nerd_font && glyphs=nerd bar=capsule
        cat > "$CONF" <<EOF
# agentline configuration: shell syntax, read on every render.
# Change it with \`agentline configure\`, or edit it (values: \`agentline --help\`).
# Environment variables with the same names override this file.
AGENTLINE_CONFIG_VERSION=2
AGENTLINE_GLYPHS=$glyphs
AGENTLINE_BAR=$bar
AGENTLINE_BRANCH_ICON=auto
AGENTLINE_RESET_ICON=auto
AGENTLINE_CODEX_MIRROR=1
AGENTLINE_AUTO_UPDATE=1
EOF
        ok "config → $CONF"
    elif ! grep -qx 'AGENTLINE_CONFIG_VERSION=2' "$CONF"; then
        # Version 2 (agentline 0.5.0) adds the route part: a saved list of
        # parts gets it next to the effort, like the default list.
        if conf_get SEGMENTS; then
            with_route "$REPLY"
            conf_set SEGMENTS "$REPLY" && ok "config: route (automodel) added to AGENTLINE_SEGMENTS"
        fi
        conf_set CONFIG_VERSION 2 || true
        changed=1
    fi
    for k in "${!SET[@]}"; do conf_set "$k" "${SET[$k]}" && changed=1; done
    if ((changed)); then ok "config: $(grep -h '^AGENTLINE_' "$CONF" | tr '\n' ' ')"
    else same "config ($(grep -h '^AGENTLINE_' "$CONF" | tr '\n' ' '))"; fi
}

if ((uninstall)); then
    ((do_claude)) && claude_uninstall
    ((do_codex)) && codex_uninstall
    { [ "$(readlink "$BIN_DIR/agentline" 2>/dev/null)" = "$DATA/current/bin/agentline" ] \
        || { ((WIN)) && grep -qs "$DATA/current/bin/agentline" "$BIN_DIR/agentline"; }; } && rm -f "$BIN_DIR/agentline"
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
