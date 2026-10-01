#!/usr/bin/env bash
# agentline — Claude Code status line.
#
# Two aligned lines by default (AGENTLINE_LAYOUT): where/what (dir, git,
# session) … who (style, model, effort, automodel route) then budgets
# (context, 5h, 7d) … session stats (prompt cache, cost, edits).
# Reads the JSON Claude Code pipes on stdin. Single jq pass, git status cached
# 2 s per directory, tty lookup cached per session: ~40 ms per render, so a
# 1-second refreshInterval is cheap. With automodel routing the session, its
# answer is fetched while the rest renders.
#
# Configuration: ${XDG_CONFIG_HOME:-~/.config}/agentline/config (shell syntax),
# overridable by the same AGENTLINE_* variables in the environment.
# shellcheck disable=SC2154  # payload variables are assigned by the jq eval below
set -f   # no pathname expansion anywhere: unquoted expansions only split words
# A UTF-8 locale, for ${#s} and ${s:i:1} to count characters: macOS has no
# C.UTF-8 (bash then silently falls back to C, and cuts characters in half).
case $OSTYPE in darwin*) export LC_ALL=en_US.UTF-8 ;; *) export LC_ALL=C.UTF-8 ;; esac
umask 077   # what this script writes is for this user only

input=$(cat)
now=${AGENTLINE_NOW:-$EPOCHSECONDS}   # AGENTLINE_NOW pins the clock (demo recording)
# Claude Code re-renders at most once per second (refreshInterval >= 1), so the
# animation advances one small step per second; AGENTLINE_FRAME pins it.
frame=${AGENTLINE_FRAME:-$now}

# ── Cache directory ───────────────────────────────────────────────────────
# Some cache files are sourced, so the directory must be this user's alone: a
# real directory (not a symlink), ours, whose mode we set to 700. The sticky
# bit records that we did (only the owner can set it), so checking the
# directory costs no process. XDG_RUNTIME_DIR is private and so is macOS's
# TMPDIR, but /tmp is shared: another user can create agentline-<uid> there
# first. Then nothing is cached (no file there is read or written): git status
# and the automodel lookup run at each render.
CACHE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"; CACHE_DIR="${CACHE_DIR%/}/agentline-$UID"
cache_ours() { [ -d "$CACHE_DIR" ] && [ ! -L "$CACHE_DIR" ] && [ -O "$CACHE_DIR" ]; }
# Windows (Git Bash, MSYS2, Cygwin): no Unix modes to rely on, but TMPDIR is
# the user's own %TEMP%, so ownership is enough.
WIN=0; case $OSTYPE in msys*|cygwin*) WIN=1 ;; esac
# shellcheck disable=SC2174  # the parents, if any, get the umask's 700
[ -e "$CACHE_DIR" ] || [ -L "$CACHE_DIR" ] || mkdir -p -m 1700 "$CACHE_DIR" 2>/dev/null
if ((!WIN)) && cache_ours && [ ! -k "$CACHE_DIR" ]; then
    # Made by agentline before 0.5.0, with the umask's mode: made private once;
    # if others could write in it, it may hold their files: started afresh.
    cache_mode=$(ls -ld "$CACHE_DIR" 2>/dev/null)
    case ${cache_mode:5:1}${cache_mode:8:1} in
        --) chmod 1700 "$CACHE_DIR" 2>/dev/null ;;
        *) rm -rf "$CACHE_DIR" 2>/dev/null && mkdir -m 1700 "$CACHE_DIR" 2>/dev/null ;;
    esac
fi
cache_ours && { ((WIN)) || [ -k "$CACHE_DIR" ]; } || CACHE_DIR=""
mine() { # mine <file>: a cache file we may read (in the cache directory, ours, not a symlink)
    [ -n "$CACHE_DIR" ] && [ -n "$1" ] && [ -f "$1" ] && [ -O "$1" ] && [ ! -L "$1" ]
}
cache_file() { # cache_file <prefix> <key> → REPLY: "<dir>/<prefix><key, / as %>", or "" (no cache,
    # or a name too long for the file system: 255 bytes, with room for ".<pid>")
    local LC_ALL=C
    REPLY=""; [ -n "$CACHE_DIR" ] || return 0
    REPLY="$1${2//\//%}"; ((${#REPLY} <= 240)) && REPLY="$CACHE_DIR/$REPLY" || REPLY=""
    return 0
}
[ -n "$CACHE_DIR" ] && [ -z "${AGENTLINE_DEMO_GIT:-}" ] && [ -n "$input" ] && printf '%s' "$input" > "$CACHE_DIR/last-payload.json"

# ── Configuration ─────────────────────────────────────────────────────────
# Environment wins over the config file, which wins over the defaults.
declare -A ENV_OVERRIDE
for k in GLYPHS BAR BRANCH_ICON RESET_ICON PATH_COLOR ICON_GAP AUTO_UPDATE SEGMENTS EFFORT_STYLE COMPACT_STYLE ULTRA_EFFECT \
         THEME LAYOUT AUTOMODEL; do
    v="AGENTLINE_$k"; [ -n "${!v+x}" ] && ENV_OVERRIDE[$k]=${!v}
done
CONFIG_FILE="${AGENTLINE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/agentline/config}"
# shellcheck source=/dev/null
[ -r "$CONFIG_FILE" ] && . "$CONFIG_FILE"
for k in "${!ENV_OVERRIDE[@]}"; do printf -v "AGENTLINE_$k" '%s' "${ENV_OVERRIDE[$k]}"; done
GLYPHS=${AGENTLINE_GLYPHS:-nerd}              # nerd | unicode
# Gauge styles, the same catalogue for bars, compact gauges and effort:
# capsule | smooth | blocks | line | segments | braille | ramp | dots | bars | squares | pie | none
BAR_STYLE=${AGENTLINE_BAR:-capsule}            # context / 5h / 7d bars
BRANCH_ICON=${AGENTLINE_BRANCH_ICON:-auto}     # auto | unicode | octicon | powerline | devicon
RESET_ICON=${AGENTLINE_RESET_ICON:-auto}       # auto | unicode | octicon | mdi-history | mdi-progress-clock | mdi-refresh
PATH_COLOR=${AGENTLINE_PATH_COLOR:-215;119;87} # Claude Code's spinner colour
ICON_GAP=${AGENTLINE_ICON_GAP:-auto}           # auto | 0 | 1: space after Nerd icons
SEGMENTS=${AGENTLINE_SEGMENTS:-dir git session meta model effort route ctx 5h 7d cache cost lines}
EFFORT_STYLE=${AGENTLINE_EFFORT_STYLE:-dots}   # effort gauge; auto = the bar style
COMPACT_STYLE=${AGENTLINE_COMPACT_STYLE:-pie}  # gauges on narrow terminals
# Older names: minibar = the bar style, 5 cells wide; text / percent = none.
[ "$COMPACT_STYLE" = minibar ] && COMPACT_STYLE=$BAR_STYLE
[ "$EFFORT_STYLE" = auto ] && EFFORT_STYLE=$BAR_STYLE
for v in BAR_STYLE COMPACT_STYLE EFFORT_STYLE; do
    case ${!v} in text|percent) printf -v "$v" none ;; esac
done
ULTRA_EFFECT=${AGENTLINE_ULTRA_EFFECT:-violet} # violet | rainbow | plain
THEME=${AGENTLINE_THEME:-dark}                 # dark | light: the terminal's background
LAYOUT=${AGENTLINE_LAYOUT:-two}                # two | one | "left | right; left | right"
AUTOMODEL=${AGENTLINE_AUTOMODEL:-auto}         # auto | off: show automodel's routing
declare -A ON; for k in $SEGMENTS; do ON[$k]=1; done

# ── automodel (routes each prompt of a "Jev" session to a model and effort) ─
# `automodel statusline --json` says what the current session was routed to.
# automodel is found through the UserPromptSubmit hook it installs in
# settings.json ("<exe> --config <cfg> hook decide"), together with a probe of
# `automodel help`: releases without --json would run their chained status line
# (maybe agentline itself). Both are cached until settings.json or the binary
# changes: without automodel, a render costs a few file tests and no process.
# The call runs while the rest renders; its answer is read at the last moment,
# and anything but a valid answer within 0.8 s means "not routed".
#   AGENTLINE_AUTOMODEL=off: never ask.
#   AGENTLINE_AUTOMODEL_JSON: an answer to use instead (previews, tests);
#     '{"v":1,"routed":false}' shows the session as not routed.
#   AUTOMODEL_CHAINED=1: automodel runs agentline and prints its own segment.
am_fd="" am_pid="" am_routed=0
AM_JQ='def s: (. // "" | tostring | explode | map(select(. >= 32 and . != 127)) | implode);   # no control characters
  if type == "object" and .v == 1 and .routed == true then
    @sh "am_alias=\(.alias | s) am_model=\(.model | s) am_label=\(.label | s) am_effort=\(.effort | s) am_mode=\(.mode | s) am_state=\(.state | s) am_conf=\(.confidence | if type == "number" then [[., 0] | max, 1] | min * 100 | round else 0 end) am_pin=\(.pin | s) am_issue=\(.issue | s) am_flash=\(.flash | s) am_budget=\(.budget | s) am_ceffort=\(.claude_effort | s) am_why=\(.why | s) am_whyp=\(.why_p | if type == "number" then [[., 0] | max, 1] | min * 100 | round else -1 end) am_from=\(.from | s) am_text=\(.text | s) am_routed=1"
  else "am_routed=0" end'
am_discover() { # find automodel in settings.json and probe it → cache
    local cmd="" line fd pid rc=0 v val
    am_exe="" am_cfg="" am_ok=0
    [ -r "$am_settings" ] && cmd=$(jq -r 'first((.hooks.UserPromptSubmit? // [])[]?.hooks[]?.command? | strings
        | select(contains("automodel") and endswith(" hook decide"))) // empty' "$am_settings" 2>/dev/null)
    cmd=${cmd% hook decide}
    if [ -n "$cmd" ]; then
        case $cmd in *" --config "*) am_exe=${cmd%% --config *} am_cfg=${cmd#* --config } ;; *) am_exe=$cmd ;; esac
        for v in am_exe am_cfg; do   # as a shell would read them: quotes, ~/
            val=${!v}
            case $val in \"*\"|\'*\') val=${val:1:${#val}-2} ;; esac
            case $val in \~/*) val=$HOME/${val#\~/} ;; esac
            printf -v "$v" '%s' "$val"
        done
        [[ $am_exe == */* ]] || am_exe=$(type -P "$am_exe")
    fi
    if [ -n "$am_exe" ] && [ -x "$am_exe" ]; then
        exec {fd}< <(exec "$am_exe" help </dev/null 2>/dev/null)
        pid=$!
        while :; do
            line=""; IFS= read -r -t 1 -u "$fd" line; rc=$?
            [[ $line == *statusline*--json* ]] && { am_ok=1; break; }
            ((rc == 0)) || break
        done
        exec {fd}<&-
        # Too slow (a cold start, macOS checking a new binary): asked again
        # next time rather than taken for a release without --json.
        ((rc > 128)) && { kill "$pid" 2>/dev/null; return 0; }
    fi
    [ -n "$am_cache" ] && { printf 'am_exe=%q am_cfg=%q am_ok=%d\n' "$am_exe" "$am_cfg" "$am_ok" > "$am_cache.$$" \
        && mv -f "$am_cache.$$" "$am_cache"; } 2>/dev/null
    return 0
}
case $AUTOMODEL in
    off|0) ;;
    *)
        if [ -n "${AGENTLINE_AUTOMODEL_JSON:-}" ]; then
            exec {am_fd}< <(jq -r "$AM_JQ" <<<"$AGENTLINE_AUTOMODEL_JSON" 2>/dev/null)
        elif [ "${AUTOMODEL_CHAINED:-}" != 1 ]; then
            am_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
            cache_file automodel- "$am_settings"; am_cache=$REPLY
            am_exe="" am_cfg="" am_ok=0
            # shellcheck source=/dev/null
            if mine "$am_cache"; then . "$am_cache"; fi
            if ! mine "$am_cache" || [ "$am_settings" -nt "$am_cache" ] || [ "$am_exe" -nt "$am_cache" ]; then am_discover; fi
            if ((am_ok)); then
                exec {am_fd}< <(exec 2>/dev/null
                    "$am_exe" ${am_cfg:+--config "$am_cfg"} statusline --json <<<"$input" | jq -r "$AM_JQ")
                am_pid=$!
            fi
        fi ;;
esac
am_read() { # the answer, waited for 0.8 s at most → am_* variables
    local line="" rc
    [ -n "$am_fd" ] || return 0
    IFS= read -r -t 0.8 -u "$am_fd" line; rc=$?
    ((rc == 0)) && [[ $line == am_* ]] && eval "$line"
    # Too slow: stop it rather than leave it running at every refresh.
    ((rc > 128)) && [ -n "$am_pid" ] && { pkill -P "$am_pid"; kill "$am_pid"; } 2>/dev/null
    exec {am_fd}<&-
    return 0
}

# ── Glyph sets ────────────────────────────────────────────────────────────
# Nerd Font icons are often drawn wider than their cell and overlap the next
# character, so they are followed by a space (ICON_GAP).
[ "$ICON_GAP" = auto ] && { [ "$GLYPHS" = nerd ] && ICON_GAP=1 || ICON_GAP=0; }
G=""; ((ICON_GAP)) && G=" "
[ "$BRANCH_ICON" = auto ] && { [ "$GLYPHS" = nerd ] && BRANCH_ICON=octicon || BRANCH_ICON=unicode; }
[ "$RESET_ICON" = auto ] && { [ "$GLYPHS" = nerd ] && RESET_ICON=octicon || RESET_ICON=unicode; }
case $BRANCH_ICON in
    octicon) I_BRANCH=$'\uf418'"$G" ;; powerline) I_BRANCH=$'\ue0a0'"$G" ;; devicon) I_BRANCH=$'\ue725'"$G" ;;
    *) I_BRANCH="⎇ " ;;
esac
case $RESET_ICON in
    octicon) I_RESET=$'\uf464'"$G" ;; mdi-history) I_RESET=$'\U000f02da'"$G" ;;
    mdi-progress-clock) I_RESET=$'\U000f0996'"$G" ;; mdi-refresh) I_RESET=$'\U000f0450'"$G" ;;
    *) I_RESET="↻" ;;
esac
if [ "$GLYPHS" = nerd ]; then
    # Octicons: diff-added, diff-modified, question, alert, stack, arrows, check, git-compare
    I_STAGED=$'\uf457'"$G" I_MODIFIED=$'\uf459'"$G" I_UNTRACKED=$'\uf420'"$G" I_CONFLICT=$'\uf421'"$G"
    I_STASH=$'\uf51e'"$G" I_AHEAD=$'\uf431'"$G" I_BEHIND=$'\uf433'"$G" I_CLEAN=$'\uf42e' I_WORKTREE=$'\uf47f'"$G"
else
    # Starship's conventions: + staged, ! modified, ? untracked, = conflicted, $ stashed
    I_STAGED="+" I_MODIFIED="!" I_UNTRACKED="?" I_CONFLICT="=" I_STASH="\$"
    I_AHEAD="↑" I_BEHIND="↓" I_CLEAN="✓" I_WORKTREE="◈ "
fi

# ── Parse everything in one jq pass ───────────────────────────────────────
eval "$(jq -r '
  def i: (. // 0 | if type == "number" then floor else 0 end);
  def s: (. // "" | tostring);
  @sh "cwd=\(.cwd // .workspace.current_dir | s)",
  @sh "project_dir=\(.workspace.project_dir | s)",
  @sh "worktree=\(.workspace.git_worktree | s)",
  @sh "model=\(.model.display_name // .model.id // "?" | s)",
  @sh "effort=\(.effort.level | s)",
  @sh "session_id=\(.session_id | s)",
  @sh "session_name=\(.session_name | s)",
  @sh "transcript=\(.transcript_path | s)",
  @sh "style=\(.output_style.name | s)",
  @sh "agent=\(.agent.name | s)",
  @sh "vim_mode=\(.vim.mode | s)",
  @sh "fast=\(.fast_mode // false)",
  @sh "ctx_size=\(.context_window.context_window_size | i)",
  @sh "ctx_used=\(.context_window.current_usage // {} | (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))",
  @sh "cost_c=\((.cost.total_cost_usd // 0) * 100 | round)",
  @sh "dur_ms=\(.cost.total_duration_ms | i)",
  @sh "l_add=\(.cost.total_lines_added | i)",
  @sh "l_del=\(.cost.total_lines_removed | i)",
  @sh "rl5=\(.rate_limits.five_hour.used_percentage // -1 | round)",
  @sh "rl5_reset=\(.rate_limits.five_hour.resets_at | i)",
  @sh "rl7=\(.rate_limits.seven_day.used_percentage // -1 | round)",
  @sh "rl7_reset=\(.rate_limits.seven_day.resets_at | i)",
  @sh "cache_seen=\(.prompt_cache.caching_observed // false)",
  @sh "cache_warm=\(.prompt_cache.warm // false)",
  @sh "cache_exp=\(.prompt_cache.expires_at | i)",
  @sh "cache_ttl=\(.prompt_cache.ttl | s)"
' <<<"$input" 2>/dev/null)"
sid=${session_id//\//%}   # in cache file names

# ── Palette & helpers (no subshells: results go through REPLY) ────────────
RST=$'\e[0m'; BOLD=$'\e[1m'; ITAL=$'\e[3m'
fg() { printf -v REPLY '\e[38;2;%d;%d;%dm' "$1" "$2" "$3"; }
PATHC=$'\e[38;2;'"${PATH_COLOR}m"
# Heat gradient green → yellow → red for p in 0..100
grad() {
    local p=$1 r g b
    ((p < 0)) && p=0; ((p > 100)) && p=100
    if ((p < 50)); then r=$((80 + 160 * p / 50)); g=$((200 - 20 * p / 50)); b=$((120 - 70 * p / 50))
    else r=240; g=$((180 - 100 * (p - 50) / 50)); b=$((50 + 30 * (p - 50) / 50)); fi
    printf -v REPLY '\e[38;2;%d;%d;%dm' "$r" "$g" "$b"
}
if [ "$THEME" = light ]; then
    # Darker inks for a light background; tracks and rails fade into it.
    fg 195 95 55;   ORANGE=$REPLY
    fg 0 110 190;   CYAN=$REPLY
    fg 20 140 60;   GREEN=$REPLY
    fg 175 115 0;   YELLOW=$REPLY
    fg 200 40 40;   RED=$REPLY
    fg 235 80 80;   RED_HI=$REPLY
    fg 130 70 210;  VIOLET=$REPLY
    fg 40 40 50;    TEXT=$REPLY
    fg 20 120 190;  ICE=$REPLY
    fg 200 200 210; TRACK=$REPLY
    fg 110 110 125; LABEL=$REPLY
    RAIL_RGB="226;228;232"
    EFFORT_RGB=("" "120 120 140" "40 110 220" "185 135 0" "215 100 20" "210 40 70")   # low … max
    ULTRA_RGB=("60;10;140" "85;35;170" "105;55;195" "125;75;215")   # sweep highlight … base
    HUE_HI=205 HUE_LO=30   # rainbow: HSV value/floor
    grad() {
        local p=$1 r g b
        ((p < 0)) && p=0; ((p > 100)) && p=100
        if ((p < 50)); then r=$((20 + 170 * p / 50)); g=$((150 - 10 * p / 50)); b=$((70 - 70 * p / 50))
        else r=$((190 + 15 * (p - 50) / 50)); g=$((140 - 100 * (p - 50) / 50)); b=$((40 * (p - 50) / 50)); fi
        printf -v REPLY '\e[38;2;%d;%d;%dm' "$r" "$g" "$b"
    }
else
    fg 215 119 87;  ORANGE=$REPLY
    fg 100 180 255; CYAN=$REPLY
    fg 80 200 120;  GREEN=$REPLY
    fg 240 180 50;  YELLOW=$REPLY
    fg 240 80 80;   RED=$REPLY
    fg 255 120 120; RED_HI=$REPLY
    fg 190 130 255; VIOLET=$REPLY
    fg 205 205 215; TEXT=$REPLY
    fg 120 200 255; ICE=$REPLY
    fg 75 75 90;    TRACK=$REPLY
    fg 125 125 140; LABEL=$REPLY
    RAIL_RGB="38;42;46"
    EFFORT_RGB=("" "150 150 170" "100 160 255" "240 190 60" "245 130 50" "240 70 90")
    ULTRA_RGB=("240;232;255" "215;195;255" "195;165;255" "175;135;255")
    HUE_HI=255 HUE_LO=77
fi
# hue <degrees> → REPLY "r;g;b" (HSV, saturation 0.7)
hue() {
    local h=$(( ($1 % 360 + 360) % 360 )) x c=$HUE_HI m=$HUE_LO r g b
    x=$(( (c - m) * (60 - ( h % 120 - 60 < 0 ? 60 - h % 120 : h % 120 - 60 )) / 60 + m ))
    case $((h / 60)) in
        0) r=$c g=$x b=$m ;; 1) r=$x g=$c b=$m ;; 2) r=$m g=$c b=$x ;;
        3) r=$m g=$x b=$c ;; 4) r=$x g=$m b=$c ;; *) r=$c g=$m b=$x ;;
    esac
    REPLY="$r;$g;$b"
}

# Display width: the text between escape sequences (all of them "\e[…m").
# shellcheck disable=SC2206  # split on ESC, globbing is off
vis() { local IFS=$'\e' a t; a=($1); t=${a[0]}; a[0]=; printf -v t '%s' "$t" "${a[@]#*m}"; REPLY=${#t}; }

# gauge <style> <permille> <width> <colour> → REPLY
#   colour: "heat" (green → red along the gauge), an escape sequence (lit
#   cells in that colour), or "plain" (no colour, for the ultracode effect).
EIGHTHS=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
SHADE=(' ' '░' '░' '▒' '▒' '▒' '▓' '▓')
BRAILLE=('⣀' '⣀' '⣄' '⣤' '⣦' '⣶' '⣷' '⣿')
RAMP=(▁ ▂ ▄ ▆ █)
PIE_NERD=($'\U000f0766' $'\U000f0a9e' $'\U000f0a9f' $'\U000f0aa0' $'\U000f0aa1' $'\U000f0aa2' $'\U000f0aa3' $'\U000f0aa4' $'\U000f0aa5')
PIE_UNI=(○ ◔ ◑ ◕ ●)
RAIL=$'\e[48;2;'"${RAIL_RGB}m"; RAILFG=$'\e[38;2;'"${RAIL_RGB}m"
cell_colour() { # cell_colour <colour> <position 0-100> → REPLY
    case $1 in heat) grad "$2" ;; plain) REPLY="" ;; *) REPLY=$1 ;; esac
}
gauge() {
    local style=$1 pm=$2 w=$3 col=$4 out="" i units lit first="" last="" on off
    ((pm > 1000)) && pm=1000; ((pm < 0)) && pm=0
    # Rounded caps are Nerd glyphs; without them a capsule is a smooth bar.
    [ "$style" = capsule ] && [ "$GLYPHS" != nerd ] && style=smooth
    case $style in
        none|"") REPLY=""; return ;;
        pie)
            cell_colour "$col" $((pm / 10))
            if [ "$GLYPHS" = nerd ]; then REPLY="$REPLY${PIE_NERD[(pm * 8 + 999) / 1000]}$G"
            else REPLY="$REPLY${PIE_UNI[(pm * 4 + 999) / 1000]}"; fi
            [ "$col" = plain ] || REPLY+=$RST; return ;;
        ramp|dots|bars|squares)
            [ "$style" = ramp ] && w=5   # a ramp is five steps, whatever the room
            lit=$(((pm * w + 500) / 1000)); ((pm > 0 && lit == 0)) && lit=1
            for ((i = 0; i < w; i++)); do
                case $style in
                    ramp) on=${RAMP[i]} off=$on ;; dots) on=● off=○ ;;
                    bars) on=▰ off=▱ ;; squares) on=■ off=□ ;;
                esac
                if ((i < lit)); then cell_colour "$col" $(((i * 100 + 50) / w)); out+="$REPLY$on"
                elif [ "$col" = plain ]; then out+=$off
                else out+="$TRACK$off"; fi
            done
            [ "$col" = plain ] && REPLY=$out || REPLY="$out$RST"; return ;;
    esac
    # Bar styles, with sub-cell precision.
    [ "$style" = capsule ] && w=$((w - 2))
    ((w < 1)) && w=1
    units=$((pm * w * 8 / 1000))
    ((pm > 0 && units == 0)) && units=1
    for ((i = 0; i < w; i++)); do
        cell_colour "$col" $(((i * 100 + 50) / w))
        ((i == 0)) && first=$REPLY
        if ((units >= 8)); then
            case $style in
                line) out+="${REPLY}━" ;; segments) out+="${REPLY}■" ;; braille) out+="${REPLY}⣿" ;;
                *) out+="${REPLY}█" ;;
            esac
            units=$((units - 8)); last=$REPLY
        elif ((units > 0)); then
            case $style in
                smooth|capsule) [ "$col" = plain ] && out+="${EIGHTHS[units]}" || out+="$RAIL$REPLY${EIGHTHS[units]}$RST" ;;
                line) ((units >= 4)) && out+="${REPLY}╸" || out+="${TRACK}─" ;;
                segments) ((units >= 4)) && out+="${REPLY}■" || out+="${TRACK}□" ;;
                braille) out+="$REPLY${BRAILLE[units]}" ;;
                *) out+="$REPLY${SHADE[units]}" ;;
            esac
            units=0
        elif [ "$col" = plain ]; then
            case $style in line) out+="─" ;; segments) out+="□" ;; braille) out+="⣀" ;; blocks) out+="░" ;; *) out+=" " ;; esac
        else
            case $style in
                smooth|capsule) out+="$RAIL $RST" ;; line) out+="${TRACK}─" ;; segments) out+="${TRACK}□" ;;
                braille) out+="${TRACK}⣀" ;; *) out+="${TRACK}░" ;;
            esac
        fi
    done
    if [ "$style" = capsule ]; then
        # Rounded caps (U+E0B6 / U+E0B4), coloured like the cell they touch.
        local lc=$RAILFG rc=$RAILFG
        ((pm > 0)) && lc=$first; ((pm >= 1000)) && rc=$last
        if [ "$col" = plain ]; then out=$'\ue0b6'"$out"$'\ue0b4'
        else out="$lc"$'\ue0b6'"$RST$out$rc"$'\ue0b4'; fi
    fi
    [ "$col" = plain ] && REPLY=$out || REPLY="$out$RST"
}

pct_color() { # pct_color <pct> [force-red]
    if [ -n "$2" ] || (($1 >= 70)); then REPLY=$RED
    elif (($1 >= 40)); then REPLY=$YELLOW
    else REPLY=$GREEN; fi
}

fmt_dur() {
    local s=$1; ((s < 0)) && s=0
    if ((s >= 86400)); then REPLY="$((s / 86400))d$((s % 86400 / 3600))h"
    elif ((s >= 3600)); then printf -v REPLY '%dh%02d' $((s / 3600)) $((s % 3600 / 60))
    elif ((s >= 60)); then REPLY="$((s / 60))m"
    else REPLY="${s}s"; fi
}

# Rainbow gradient across the text (18° per character) drifting 15° per
# second: at one frame per second the colours flow instead of jumping.
shimmer() {
    local t=$1 out="" i ch
    for ((i = 0; i < ${#t}; i++)); do
        ch=${t:i:1}
        [[ $ch == ' ' ]] && { out+=' '; continue; }
        hue $((i * 18 - frame * 15))
        out+=$'\e[1;38;2;'"${REPLY}m$ch"
    done
    REPLY="$out$RST"
}

# Claude Code's ultracode violet with a highlight sweeping across the text,
# three characters per second.
violet() {
    local t=$1 out="" i ch d pos
    pos=$(((frame * 3) % (${#t} + 8) - 4))
    for ((i = 0; i < ${#t}; i++)); do
        ch=${t:i:1}
        [[ $ch == ' ' ]] && { out+=' '; continue; }
        d=$((i - pos)); ((d < 0)) && d=$((-d)); ((d > 3)) && d=3
        out+=$'\e[1;38;2;'"${ULTRA_RGB[d]}m$ch"
    done
    REPLY="$out$RST"
}
ultra_fx() { # ultra_fx <text> → REPLY
    case $ULTRA_EFFECT in
        violet) violet "$1" ;;
        plain) REPLY=$'\e[1;38;2;'"${ULTRA_RGB[3]}m$1$RST" ;;
        *) shimmer "$1" ;;
    esac
}

# ── Terminal width (Claude Code gives us no TTY: use an ancestor's) ───────
term_width() {
    if [[ $COLUMNS -gt 0 ]] 2>/dev/null; then REPLY=$COLUMNS; return; fi
    if ((WIN)); then win_width; return; fi
    local f="" tty="" pid=$PPID w t pp
    [ -n "$CACHE_DIR" ] && f="$CACHE_DIR/tty-${sid:-$PPID}"
    mine "$f" && read -r tty < "$f"
    if [ -z "$tty" ] || [ ! -e "/dev/$tty" ]; then
        tty=""
        while [ -n "$pid" ] && [ "$pid" != 0 ] && [ "$pid" != 1 ]; do
            read -r t pp < <(ps -o tty=,ppid= -p "$pid" 2>/dev/null)
            if [ -n "$t" ] && [ "$t" != "?" ]; then tty=$t; break; fi
            pid=$pp
        done
        [ -n "$tty" ] && [ -n "$f" ] && echo "$tty" > "$f"
    fi
    if [ -n "$tty" ]; then w=$(stty size < "/dev/$tty" 2>/dev/null); w=${w#* }; fi
    [[ $w -gt 0 ]] 2>/dev/null && REPLY=$w || REPLY=120
}
# Windows: no ps/stty to reach the terminal. The console Claude Code runs in
# is asked by PowerShell, in the background (it takes a few hundred ms), and
# the answer is cached for 5 s; until the first one, 120 columns.
win_width() {
    local f="" at=0 w=0
    [ -n "$CACHE_DIR" ] && f="$CACHE_DIR/cols"
    mine "$f" && read -r at w < "$f"
    if [ -n "$f" ] && ((now - ${at:-0} >= 5)); then
        printf '%s %s\n' "$now" "${w:-0}" > "$f"   # one refresh at a time
        (w=$(powershell.exe -NoProfile -NonInteractive -Command '[Console]::WindowWidth' 2>/dev/null | tr -dc 0-9)
         [[ $w -gt 0 ]] 2>/dev/null && printf '%s %s\n' "$now" "$w" > "$f") </dev/null >/dev/null 2>&1 &
    fi
    [[ $w -gt 0 ]] 2>/dev/null && REPLY=$w || REPLY=120
}
term_width; tw=$((REPLY - 4))   # Claude Code pads the status line

# ── Git (porcelain v2, cached 2 s per directory) ──────────────────────────
is_git=0 head="" oid="" ahead=0 behind=0 stash=0 staged=0 unstaged=0 untracked=0 conflicts=0 in_wt=0
cache_file git- "$cwd"; gcache=$REPLY
gts=0
# shellcheck source=/dev/null
mine "$gcache" && . "$gcache"
if [ -n "${AGENTLINE_DEMO_GIT:-}" ]; then
    # Previews (installer, docs): "branch staged modified untracked ahead behind stash"
    read -r head staged unstaged untracked ahead behind stash <<<"$AGENTLINE_DEMO_GIT"
    is_git=1 conflicts=0 in_wt=0 gts=$now
elif ((now - gts >= 2)); then
    if dirs=$(git -C "$cwd" --no-optional-locks rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null); then
        is_git=1 head="" oid="" ahead=0 behind=0 stash=0 staged=0 unstaged=0 untracked=0 conflicts=0 in_wt=0
        [ "${dirs%%$'\n'*}" != "${dirs##*$'\n'}" ] && in_wt=1
        while IFS= read -r l; do
            case $l in
                '# branch.oid '*)  oid=${l#\# branch.oid } ;;
                '# branch.head '*) head=${l#\# branch.head } ;;
                '# branch.ab '*)   l=${l#\# branch.ab +}; ahead=${l%% *}; behind=${l##*-} ;;
                '# stash '*)       stash=${l#\# stash } ;;
                [12]' '*)          [[ ${l:2:1} != . ]] && ((staged++)); [[ ${l:3:1} != . ]] && ((unstaged++)) ;;
                'u '*)             ((conflicts++)) ;;
                '? '*)             ((untracked++)) ;;
            esac
        done < <(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch --show-stash 2>/dev/null)
    else
        is_git=0
    fi
    if [ -n "$gcache" ]; then
        declare -p is_git head oid ahead behind stash staged unstaged untracked conflicts in_wt \
            | sed 's/^declare -- //' > "$gcache.$$" 2>/dev/null
        echo "gts=$now" >> "$gcache.$$"; mv -f "$gcache.$$" "$gcache"
    fi
fi
[ -n "$worktree" ] && in_wt=1

# ── Segments: SEG[name:variant] = rendered string; higher variants are more
#    compact, a missing variant means "dropped" ─────────────────────────────
declare -A SEG W NV
put() { [ -n "${ON[$1]:-}" ] || return 0; SEG[$1:$2]=$3; vis "$3"; W[$1:$2]=$((REPLY + ${4:-0})); NV[$1]=$(($2 + 1)); }  # [4] = extra cells (wide emoji)

# ── Line 1 left: where (dir, git) and what (session name) ─────────────────
short="${cwd/#$HOME/\~}"
# shellcheck disable=SC2088  # a literal "~" is displayed, not expanded
if [[ $short == */*/*/* ]]; then p=${cwd%/*}; short="~/…/${p##*/}/${cwd##*/}"; fi
put dir 0 "${PATHC}${short}${RST}"
put dir 1 "${PATHC}${cwd##*/}${RST}"

if ((is_git)); then
    if [ "$head" = "(detached)" ]; then branch="➦${oid:0:7}"; else branch=$head; fi
    icon="${CYAN}${I_BRANCH}${RST}"; ((in_wt)) && icon="${VIOLET}${I_WORKTREE}${RST}${icon}"
    sync=""; ((ahead)) && sync+="${VIOLET}${I_AHEAD}${ahead}"; ((behind)) && sync+="${sync:+ }${VIOLET}${I_BEHIND}${behind}"
    [ -n "$sync" ] && sync=" $sync$RST"
    st_full=""
    ((conflicts)) && st_full+=" ${RED}${I_CONFLICT}${conflicts}"
    ((staged))    && st_full+=" ${GREEN}${I_STAGED}${staged}"
    ((unstaged))  && st_full+=" ${YELLOW}${I_MODIFIED}${unstaged}"
    st_short=$st_full
    ((untracked)) && st_full+=" ${LABEL}${I_UNTRACKED}${untracked}"
    ((stash))     && st_full+=" ${CYAN}${I_STASH}${stash}"
    dirty=$((conflicts + staged + unstaged + untracked))
    ((dirty == 0)) && st_full+=" ${GREEN}${I_CLEAN}" && st_short=$st_full
    mark=""; ((dirty)) && mark="${YELLOW}*"; ((conflicts)) && mark="${RED}${I_CONFLICT}"
    trunc() { if ((${#branch} > $1)); then REPLY="${branch:0:$(($1 - 1))}…"; else REPLY=$branch; fi; }
    put git 0 "${icon}${CYAN}${branch}${RST}${sync}${st_full}${RST}"
    trunc 28; put git 1 "${icon}${CYAN}${REPLY}${RST}${sync}${st_full}${RST}"
    trunc 20; put git 2 "${icon}${CYAN}${REPLY}${RST}${sync}${st_short}${RST}"
    trunc 12; put git 3 "${CYAN}${REPLY}${RST}${mark}${RST}"
fi

if [ -n "$session_name" ]; then
    for v in 0:40 1:20; do
        n=${v#*:}; sn=$session_name
        ((${#sn} > n)) && sn="${sn:0:$((n - 1))}…"
        # shellcheck disable=SC1111  # typographic quotes are displayed
        put session "${v%:*}" "${LABEL}${ITAL}“${sn}”${RST}"
    done
fi

# ── Line 2 left: budgets (context, 5h, 7d) ────────────────────────────────
if ((ctx_size > 0)); then
    pm=$((ctx_used * 1000 / ctx_size)); pct=$((pm / 10))
    grad "$pct"; pc=$REPLY
    if ((pct >= 85)); then ((frame % 2)) && pc="$BOLD$RED_HI" || pc="$BOLD$RED"; fi
    printf -v ptxt '%s%d%%%s' "$pc" "$pct" "$RST"
    gauge "$BAR_STYLE" "$pm" 10 heat; put ctx 0 "${LABEL}context${RST}${REPLY:+ $REPLY} $ptxt"
    gauge "$BAR_STYLE" "$pm" 10 heat; put ctx 1 "${LABEL}ctx${RST}${REPLY:+ $REPLY} $ptxt"
    gauge "$COMPACT_STYLE" "$pm" 5 heat; put ctx 2 "${LABEL}ctx${RST}${REPLY:+ $REPLY} ${pc}${pct}%${RST}"
fi

# Rate limits with burn-rate projection (⚠ = limit hit before reset at this pace).
rate_seg() { # rate_seg <name> <used> <resets_at> <window-secs>
    local name=$1 used=$2 reset=$3 win=$4 left el eta=-1 tail tail_m tail_s pcol ptx rp day="" warn="" warn_m=""
    ((used < 0)) && return
    # Claude Code sends the limits it got with its last request: once the reset
    # time has passed, they are stale. The window has reset since: nothing used.
    # The 7-day window rolls on by whole weeks; a new 5-hour window only starts
    # with the next message, so it has no reset time yet.
    if ((reset <= now)); then
        used=0
        if ((win == 604800)); then reset=$((reset + ((now - reset) / win + 1) * win)); else reset=0; fi
    fi
    left=$((reset - now)); el=$((now - (reset - win)))
    if ((used >= 100)); then eta=0
    elif ((reset > 0 && used > 0 && el > win / 20)); then
        local t=$(((100 - used) * el / used)); ((t < left)) && eta=$t
    fi
    # The reset time is always shown. When, at the pace so far, the limit is
    # reached before it, a red warning follows: "↻3d18h ⚠ full in 3d4h".
    tail="" tail_m="" tail_s=""
    if ((reset > 0)); then
        fmt_dur "$left"; tail=" ${LABEL}${I_RESET}${REPLY}${RST}"; tail_m=$tail
        # A reset on another day also says which one, in local time: "↻23h19
        # (Tue 9:00)", so a reset tomorrow morning is not read as this morning.
        local d t0 t1
        printf -v t0 '%(%Y%m%d)T' "$now"; printf -v t1 '%(%Y%m%d)T' "$reset"
        if [ "$t0" != "$t1" ]; then
            printf -v d '%(%a %H:%M)T' "$reset"; d=${d/ 0/ }
            day=" ${LABEL}(${d})${RST}"
        fi
    fi
    if ((eta >= 0)); then
        fmt_dur "$eta"
        if ((eta == 0)); then warn=" ${RED}⚠ full${RST}" warn_m=" ${RED}⚠${RST}"
        else warn=" ${RED}⚠ full in ${REPLY}${RST}" warn_m=" ${RED}⚠${REPLY}${RST}"; fi
        tail_s="${RED}⚠${RST}"; pct_color "$used" 1
    else
        pct_color "$used"
    fi
    pcol=$REPLY
    printf -v ptx '%s%d%%%s' "$pcol" "$used" "$RST"
    gauge "$BAR_STYLE" $((used * 10)) 10 heat; rp=${REPLY:+ $REPLY}   # put() reuses REPLY
    # Variant 0 with the day (the same as 1 without one: the step that gives
    # up the day then changes nothing).
    put "$name" 0 "${LABEL}${name}${RST}$rp ${ptx}${tail}${day}${warn}"
    put "$name" "${NV[$name]:-0}" "${LABEL}${name}${RST}$rp ${ptx}${tail}${warn}"
    gauge "$COMPACT_STYLE" $((used * 10)) 5 heat; rp=${REPLY:+ $REPLY}
    put "$name" "${NV[$name]}" "${LABEL}${name}${RST}$rp ${ptx}${tail_m}${warn_m}"
    put "$name" "${NV[$name]}" "${LABEL}${name}${RST}$rp ${ptx}${tail_s:+ $tail_s}"
}
((rl5_reset > 0)) && rate_seg 5h "$rl5" "$rl5_reset" 18000
((rl7_reset > 0)) && rate_seg 7d "$rl7" "$rl7_reset" 604800

# ── Line 2 right: session stats (prompt cache, cost/time, edits) ──────────
# Prompt cache: 🔥 warm, ⏳ expiring soon (last sixth of the TTL), 🧊 cold
if [ "$cache_seen" = true ]; then
    rem=$((cache_exp - now))
    case $cache_ttl in *h) ttl_s=$((${cache_ttl%h} * 3600)) ;; *m) ttl_s=$((${cache_ttl%m} * 60)) ;; *) ttl_s=3600 ;; esac
    if [ "$cache_warm" = true ] && ((rem > 0)); then
        fmt_dur "$rem"; ttl=$REPLY
        if ((rem * 6 > ttl_s)); then
            put cache 0 "${LABEL}cache${RST} 🔥 ${ORANGE}${ttl}${RST}" 1
            put cache 1 "🔥${ORANGE}${ttl}${RST}" 1
        else
            ((frame % 2)) && c="$BOLD$YELLOW" || c=$YELLOW
            put cache 0 "${LABEL}cache${RST} ⏳ ${c}${ttl}${RST}" 1
            put cache 1 "⏳${c}${ttl}${RST}" 1
        fi
    else
        put cache 0 "${LABEL}cache${RST} 🧊 ${ICE}cold${RST}" 1
        put cache 1 "🧊" 1
    fi
fi

if ((cost_c > 0 || dur_ms > 0)); then
    if ((cost_c >= 10000)); then cs="\$$((cost_c / 100))"; else printf -v cs '$%d.%02d' $((cost_c / 100)) $((cost_c % 100)); fi
    fmt_dur $((dur_ms / 1000))
    put cost 0 "${TEXT}${cs}${RST} ${LABEL}in ${REPLY}${RST}"
    put cost 1 "${TEXT}${cs}${RST}"
fi

if ((l_add || l_del)); then
    d=""; ((l_add)) && d+="${GREEN}+${l_add}${RST}"; ((l_del)) && d+="${d:+ }${RED}−${l_del}${RST}"
    put lines 0 "${LABEL}edits${RST} $d"
    put lines 1 "$d"
fi

uc_on() { # Is Claude Code in ultracode? (its payload says effort "xhigh")
    # Ultracode: the payload reports it as effort "xhigh"; the real signal is in
    # the transcript (the "/effort ultracode" output, then ultra_effort_enter/exit
    # attachments) or the `ultracode: true` settings key. The transcript is
    # scanned incrementally.
    ucache="" off=0 st=""; [ -n "$CACHE_DIR" ] && ucache="$CACHE_DIR/uc-$sid"
    mine "$ucache" && read -r off st < "$ucache"
    case $off in ""|*[!0-9]*|0?*) off=0 st="" ;; esac   # a plain number, before any arithmetic
    if [ -r "$transcript" ]; then
        size=$(stat -c %s "$transcript" 2>/dev/null || stat -f %z "$transcript" 2>/dev/null || echo 0)
        ((size < off)) && off=0 st=""
        if ((size > off)); then
            # Latest of: the /effort command output (written at once) or the
            # ultra_effort_enter/exit attachment (written with the next turn).
            last=$(tail -c +$((off + 1)) "$transcript" \
                | grep -oE '"type":"ultra_effort_e[a-z]*"|<local-command-stdout>Set effort level to [a-z]+' | tail -n 1)
            case $last in *enter*|*"to ultracode") st=on ;; *exit*|*"Set effort level to "*) st=off ;; esac
            [ -n "$ucache" ] && echo "$size $st" > "$ucache"
        fi
    fi
    if [ "$st" = on ]; then return 0
    elif [ -z "$st" ] && grep -qs '"ultracode"[[:space:]]*:[[:space:]]*true' \
            "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" "$project_dir/.claude/settings.json" "$project_dir/.claude/settings.local.json"; then
        return 0
    fi
    return 1
}

# ── Model and effort: routed by automodel, else Claude Code's own ─────────
am_read
ultra=0 arrow=""
# automodel names its model by the catalog label ("Opus 5.5"). Its "model" is
# the catalog key, never shown: without a label, the short name its text shows
# ("jev → opus-5.5·xhigh 0.86"); without either, Claude Code's model and effort.
am_name=${am_label:-}
if ((am_routed)) && [ -z "$am_name" ] && [ -n "${am_model:-}" ] && [[ ${am_text:-} == *"→ "* ]]; then
    am_name=${am_text#*→ }; am_name=${am_name%%·*}; am_name=${am_name%% *}
fi
if ((am_routed)) && [ -n "$am_name" ]; then
    # "jev → Opus 5.5" with the effort (and mode) automodel chose.
    model=$am_name effort=$am_effort
    arrow="${LABEL}${am_alias:+$am_alias }→${RST} "
    [ "$am_mode" = ultracode ] && ultra=1
    # Claude Code's own effort, "xhigh" in its payload, is ultracode then.
    [ "${am_ceffort:-}" = xhigh ] && uc_on && am_ceffort=ultracode
elif [ "$effort" = xhigh ] && uc_on; then
    ultra=1
fi

# ── Line 1 right: who (output style, agent, vim, model + effort, route) ───
meta=""
[ -n "$style" ] && [ "$style" != default ] && meta+="${LABEL}◇ ${style}${RST}  "
[ -n "$agent" ] && meta+="${VIOLET}@${agent}${RST}  "
[ -n "$vim_mode" ] && meta+="${BOLD}${vim_mode}${RST}  "
[ -n "$meta" ] && put meta 0 "${meta%  }"

m="${model/ context/}"; m="${m/1 Million/1M}"
case $effort in low) lvl=1 ;; medium) lvl=2 ;; high) lvl=3 ;; xhigh) lvl=4 ;; max) lvl=5 ;; *) lvl=0 ;; esac
REPLY=""
# shellcheck disable=SC2086  # "r g b" → three arguments
((lvl)) && fg ${EFFORT_RGB[lvl]}
ecol=$REPLY
fastm="" fasts=""; [ "$fast" = true ] && fastm=" ${YELLOW}» fast${RST}" fasts=" ${YELLOW}»${RST}"
show_model=${ON[model]:-}; show_effort=${ON[effort]:-}
[ -n "$show_model$show_effort" ] && ON[model]=1
mname=""; [ -n "$show_model" ] && mname=$m
mt=""; [ -n "$mname" ] && mt="${arrow}${TEXT}${mname}${RST}"
if ((ultra)); then
    # The effect covers the effort part only (gauge + word), not the model.
    g=""; [ -n "$show_effort" ] && { gauge "$EFFORT_STYLE" 1000 5 plain; g=$REPLY; }
    for v in 0:ultracode 1:ultra 2: 3:; do
        word=${v#*:}; [ -n "$show_effort" ] || word=""
        e="$g${word:+${g:+ }$word}"
        if [ -n "$e" ]; then ultra_fx "$e"; e=$REPLY; fi
        case ${v%%:*} in
            0|1) t="$mt${e:+${mt:+ }$e}" ;;
            2) t="${mname:+${TEXT}${mname%% *}${RST}}${e:+${mname:+ }$e}" ;;
            3) t=$e ;;
        esac
        [ -n "$t" ] && put model "${v%%:*}" "$t$([ "${v%%:*}" = 0 ] && echo "$fastm" || echo "$fasts")"
    done
else
    g=""; ((lvl)) && [ -n "$show_effort" ] && { gauge "$EFFORT_STYLE" $((lvl * 200)) 5 "$ecol"; g=${REPLY:+ $REPLY}; }
    etxt=""; ((lvl)) && [ -n "$show_effort" ] && etxt=" ${ecol}${effort}${RST}"
    t="$mt$g$etxt$fastm"; put model 0 "${t# }"
    t="$mt$g$fasts"; [ -n "$g$mt" ] || t="$mt$etxt$fasts"; put model 1 "${t# }"
    t="${mname:+${TEXT}${mname%% *}${RST}}$g$fasts"; [ -n "$g$mname" ] || t="$etxt"; put model 2 "${t# }"
    [ -n "$g" ] && put model 3 "${g# }"
fi

# Route: how automodel decided its last turn. 0 all text, 1 without the effort
# it left, 2 the confidence only, 3 warnings only.
if ((am_routed)); then
    r0="" r1="" r2="" warn="" why=""
    # Claude Code shows its own effort (spinner, /effort); automodel may run
    # another one per turn over that base to keep the cache. Right after the
    # real effort, the shown one struck through, in red.
    if [ -n "${am_ceffort:-}" ] && [ -n "$am_effort" ]; then
        r0=$RED$'\e[9m'"${am_ceffort}${RST}" r1=$r0 r2=$r0
    fi
    # The effort the decision left (when it changed it) and why: the prompt's
    # relation to the last one (extend, aside, new task…), or asked, kept…
    if [ "$am_state" = routed ]; then
        [ -n "${am_from:-}" ] && [ -n "$am_effort" ] && why="${am_from}→${am_effort}"
        [ -n "${am_why:-}" ] && r1+="${r1:+ }${LABEL}${am_why}${RST}" why+="${why:+ · }${am_why}"
        [ -n "$why" ] && r0+="${r0:+ }${LABEL}${why}${RST}"
    fi
    ((${#am_issue} > 24)) && am_issue="${am_issue:0:23}…"
    case $am_state in
        routed)
            # The number: how likely the relation named by why (automodel
            # 0.19.2), else Jev's confidence in the effort (for new, no why, or
            # older releases); none for a why that is no relation (asked, kept…).
            if ((${am_whyp:--1} > 0)); then am_conf=$am_whyp
            elif ((${am_whyp:--1} == 0)) && [ -n "${am_why:-}" ] && [ "$am_why" != new ]; then am_conf=-1; fi
            if ((am_conf >= 80)); then c=$GREEN; elif ((am_conf >= 60)); then c=$YELLOW; else c=$RED; fi
            printf -v c '%s%d.%02d%s' "$c" $((am_conf / 100)) $((am_conf % 100)) "$RST"; t=$c
            ((am_conf < 0)) && t="" ;;
        default)  t="${LABEL}default${RST}" ;;
        pinned)   t="${CYAN}pinned${RST}" ;;
        fallback) t="${RED}⚠ fallback${RST}" r1+="${r1:+ }${RED}⚠${RST}" r2+="${r2:+ }${RED}⚠${RST}" warn=1 ;;
        error)    t="${RED}⚠ ${am_issue:-catalog}${RST}" r1+="${r1:+ }${RED}⚠${RST}" r2+="${r2:+ }${RED}⚠${RST}" warn=1 am_issue="" ;;
        *)        t="" ;;
    esac
    r0+="${t:+${r0:+ }$t}"
    [ -z "$warn" ] && { r1+="${t:+${r1:+ }$t}"; r2+="${t:+${r2:+ }$t}"; }
    if [ -n "${am_budget:-}" ]; then   # over automodel's spending cap
        r0+="${r0:+ }${YELLOW}⚠ budget${RST}"
        [ -n "$warn" ] || { r1+="${r1:+ }${YELLOW}⚠${RST}"; r2+="${r2:+ }${YELLOW}⚠${RST}"; }
        warn=1
    fi
    if [ -n "$am_issue" ]; then
        r0+="${r0:+ }${RED}⚠ jev: ${am_issue}${RST}"
        [ -n "$warn" ] || { r1+="${r1:+ }${RED}⚠${RST}"; r2+="${r2:+ }${RED}⚠${RST}"; }
        warn=1
    fi
    if [ -n "$am_flash" ]; then r0+="${r0:+ }${VIOLET}↻ ${am_flash}${RST}"; r1+="${r1:+ }${VIOLET}↻${RST}"; r2+="${r2:+ }${VIOLET}↻${RST}"; fi
    if [ -n "$r0" ]; then
        put route 0 "$r0"; put route 1 "$r1"; put route 2 "$r2"
        [ -n "$warn" ] && put route 3 "${RED}⚠${RST}"
    fi
fi

# ── Layout: each line = left block … right block, right-aligned so the right
#    blocks of all lines line up. Each line degrades step by step. ──────────
GAP="  "; GAPW=2
declare -A V
join() { # join <seg...> → REPLY, RW
    local out="" w=0 n k
    for n in "$@"; do
        k="$n:${V[$n]:-0}"
        [ -z "${SEG[$k]}" ] && continue
        [ -n "$out" ] && { out+=$GAP; w=$((w + GAPW)); }
        out+=${SEG[$k]}; w=$((w + W[$k]))
    done
    REPLY=$out RW=$w
}
compose() { # compose "<left segs>" "<right segs>" → REPLY, RW
    local l lw r rw pad
    # shellcheck disable=SC2086  # word-splitting the segment lists is intended
    join $1; l=$REPLY lw=$RW
    # shellcheck disable=SC2086
    join $2; r=$REPLY rw=$RW
    if ((rw == 0)); then REPLY=$l RW=$lw; return; fi
    if ((lw == 0)); then pad=$((tw - rw)); ((pad < 0)) && pad=0
    else pad=$((tw - lw - rw)); ((pad < 3)) && pad=3; fi
    printf -v REPLY '%s%*s%s' "$l" "$pad" "" "$r"
    RW=$((lw + pad + rw))
}
# What to give up first, least useful first, whatever the layout: each line
# follows this order restricted to its own segments; a step naming several
# segments advances them together.
PRIORITY=(session lines route lines "5h 7d" meta cost model session ctx git cache git route "ctx 5h 7d" model cost dir git cache
          model route "5h 7d" git 7d model)
declare -A KNOWN=([dir]=1 [git]=1 [session]=1 [meta]=1 [model]=1 [route]=1 [ctx]=1 [5h]=1 [7d]=1 [cache]=1 [cost]=1 [lines]=1)
fit_line() { # fit_line "<left segs>" "<right segs>" → REPLY, the most detailed line that fits
    local left=$1 right=$2 step s moved
    local -A IN
    V=()
    compose "$left" "$right"; ((RW <= tw)) && return
    for s in $left $right; do IN[$s]=1; done
    for step in "${PRIORITY[@]}"; do
        moved=0
        for s in $step; do
            [ -n "${IN[$s]:-}" ] && ((${V[$s]:-0} < ${NV[$s]:-0})) && { V[$s]=$((${V[$s]:-0} + 1)); moved=1; }
        done
        ((moved)) && { compose "$left" "$right"; ((RW <= tw)) && return; }
    done
    return 0
}
render_layout() { # render_layout "<left | right; left | right…>" → OUT, one entry per line
    local IFS=';' specs spec l r L R s
    # shellcheck disable=SC2206  # split on ";", globbing is off
    specs=($1); IFS=$' \t\n'
    OUT=()
    for spec in "${specs[@]}"; do
        l=${spec%%|*} r=""; [ "$l" = "$spec" ] || r=${spec#*|}
        L="" R=""   # known segments only
        for s in $l; do [ -n "${KNOWN[$s]:-}" ] && L+="$s "; done
        for s in ${r//|/ }; do [ -n "${KNOWN[$s]:-}" ] && R+="$s "; done
        [ -n "$L$R" ] || continue
        fit_line "$L" "$R"; OUT+=("$REPLY")
    done
}
case $LAYOUT in
    one) LAYOUT="dir git | model route ctx 5h 7d cache" ;;
    two) LAYOUT="dir git session | meta model route; ctx 5h 7d | cache cost lines" ;;
esac
render_layout "$LAYOUT"
((${#OUT[@]})) || render_layout "dir git session | meta model route; ctx 5h 7d | cache cost lines"
printf '%s\n' "${OUT[@]}"

# ── Auto-update: at most one background check a day, never blocking ──────
if [ "${AGENTLINE_AUTO_UPDATE:-0}" = 1 ] && [ -z "${AGENTLINE_DEMO_GIT:-}" ]; then
    data="${XDG_DATA_HOME:-$HOME/.local/share}/agentline" last=0
    [ -r "$data/last-update-check" ] && read -r last < "$data/last-update-check"
    if ((now - ${last:-0} > 86400)) && [ -x "$data/current/bin/agentline" ]; then
        echo "$now" > "$data/last-update-check"
        # In a session of its own where setsid exists (not on macOS).
        detach=(); command -v setsid >/dev/null && detach=(setsid)
        ("${detach[@]}" "$data/current/bin/agentline" update --quiet </dev/null >/dev/null 2>&1 &)
    fi
fi
