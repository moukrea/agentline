# shellcheck shell=bash disable=SC2034,SC2154  # shares state with install.sh, which sources it
# agentline setup assistant, sourced by install.sh.
#
# Full-screen: the real renderer (claude/statusline.sh) draws the preview at
# the terminal's width, from your last Claude Code session when there is one,
# re-rendered on every change, every second (animations) and on resize.
# Keys come from $TTY (the terminal, even under `curl | bash`); the result goes
# into the SET array of install.sh.

WIZ_ROWS=() WIZ_TYPE=() WIZ_KEY=() WIZ_OPTS=()   # parallel arrays, one entry per row
declare -A WIZ_VAL

wiz_row() { # wiz_row <type: choice|toggle|codex|header> <key> <label> [options...]
    WIZ_TYPE+=("$1"); WIZ_KEY+=("$2"); WIZ_ROWS+=("$3"); shift 3; WIZ_OPTS+=("$*")
}

wiz_setup_rows() {
    wiz_row choice SCENARIO "Preview as" session ultracode limits cold
    wiz_row header "" "Look"
    wiz_row choice GLYPHS "Glyphs" nerd unicode
    wiz_row choice BAR "Progress bars" capsule smooth blocks line segments braille
    wiz_row choice COMPACT_STYLE "Compact gauges (narrow)" ramp minibar pie braille percent
    wiz_row choice EFFORT_STYLE "Effort gauge" ramp dots bars squares text
    wiz_row choice ULTRA_EFFECT "Ultracode effect" rainbow violet plain
    wiz_row choice BRANCH_ICON "Branch icon" octicon powerline devicon unicode
    wiz_row choice RESET_ICON "Reset-time icon" octicon mdi-history mdi-progress-clock mdi-refresh unicode
    wiz_row choice AUTO_UPDATE "Automatic updates" 1 0
    wiz_row header "" "Claude Code: information shown"
    local seg
    for seg in "dir|Directory" "git|Git branch and status" "session|Session name" "meta|Output style, agent, vim mode" \
               "model|Model" "effort|Reasoning effort" "ctx|Context window" "5h|5-hour limit" "7d|7-day limit" \
               "cache|Prompt cache" "cost|Cost and duration" "lines|Lines edited"; do
        wiz_row toggle "${seg%%|*}" "${seg#*|}"
    done
    if ((do_codex)); then
        wiz_row header "" "Codex: items (Codex draws them itself, so no custom glyphs there)"
        for seg in $(sed -n '/^# Available:/,/^[^#]/p' "$SRC/codex/preset" | grep '^#' | sed 's/^# *//; s/^Available://' | tr ',' ' '); do
            wiz_row codex "$seg" "$seg"
        done
    fi
}

label_of() { # human label of an option value → REPLY
    case $1 in
        1) REPLY=on ;; 0) REPLY=off ;; session) REPLY="your last session" ;; ultracode) REPLY=ultracode ;;
        limits) REPLY="near the limits" ;; cold) REPLY="cold prompt cache" ;; ramp) REPLY="ramp ▁▂▄▆█" ;;
        minibar) REPLY="mini bar" ;; pie) REPLY="pie ◔" ;; braille) REPLY="braille ⣿" ;; percent) REPLY="percentage only" ;;
        dots) REPLY="dots ●●○" ;; bars) REPLY="bars ▰▰▱" ;; squares) REPLY="squares ■■□" ;; text) REPLY="word only" ;;
        capsule) REPLY="capsule (Nerd)" ;; blocks) REPLY="blocks █▒░" ;; line) REPLY="line ━╸─" ;;
        segments) REPLY="segments ■□" ;; smooth) REPLY="smooth" ;; nerd) REPLY="Nerd Font icons" ;;
        unicode) REPLY="Unicode" ;; rainbow) REPLY="rainbow" ;; violet) REPLY="Claude violet, sweeping highlight" ;;
        plain) REPLY="plain violet" ;; mdi-history) REPLY="Material history" ;; mdi-progress-clock) REPLY="Material clock" ;;
        mdi-refresh) REPLY="Material refresh" ;; *) REPLY=$1 ;;
    esac
}

# The session the preview renders: your last Claude Code session if any.
wiz_base() { # → WIZ_BASE, WIZ_DEMO, WIZ_SOURCE (not in a subshell)
    local base="${XDG_RUNTIME_DIR:-/tmp}/agentline-$UID/last-payload.json"
    WIZ_DEMO="" WIZ_SOURCE="your last Claude Code session"
    if [ ! -s "$base" ] || ! jq -e . "$base" >/dev/null 2>&1; then
        base="$WIZ_TMP/sample.json"
        jq --arg home "$HOME" --argjson n "$EPOCHSECONDS" '.cwd |= sub("^HOME"; $home) | .workspace.current_dir = .cwd
            | .prompt_cache.expires_at = $n + .prompt_cache.expires_at | (.rate_limits[].resets_at) |= $n + .' \
            "$SRC/lib/sample.json" > "$base"
        WIZ_DEMO="feat/billing-export 2 1 3 1 0 0" WIZ_SOURCE="sample session"
    fi
    WIZ_BASE=$base
}
wiz_payload() { # the session, adjusted to the "Preview as" scenario
    local base=$WIZ_BASE tr="$WIZ_TMP/ultra.jsonl"
    case ${WIZ_VAL[SCENARIO]} in
        ultracode) jq --arg tr "$tr" '.session_id = "agentline-wizard-ultra" | .effort.level = "xhigh" | .transcript_path = $tr' "$base" ;;
        limits) jq --argjson n "$EPOCHSECONDS" '.session_id = "agentline-wizard"
            | .context_window.context_window_size = (.context_window.context_window_size // 200000)
            | .context_window.current_usage = {input_tokens: (.context_window.context_window_size * 0.88 | floor)}
            | .rate_limits = {five_hour: {used_percentage: 64, resets_at: ($n + 9000)}, seven_day: {used_percentage: 81, resets_at: ($n + 200000)}}
            | .prompt_cache = {caching_observed: true, warm: true, expires_at: ($n + 200), ttl: "1h"}' "$base" ;;
        cold) jq '.session_id = "agentline-wizard" | .prompt_cache = {caching_observed: true, warm: false, expires_at: 0, ttl: "1h"}' "$base" ;;
        *) jq '.session_id = "agentline-wizard"' "$base" ;;
    esac
}

wiz_list() { # wiz_list <toggle|codex> → space-separated enabled keys
    local i out="" key
    for i in "${!WIZ_TYPE[@]}"; do
        [ "${WIZ_TYPE[i]}" = "$1" ] || continue
        key=${WIZ_KEY[i]}; [ "$1" = codex ] && key="codex:$key"
        [ "${WIZ_VAL[$key]}" = 1 ] && out+="${WIZ_KEY[i]} "
    done
    REPLY=${out% }
}

wiz_render_preview() { # → WIZ_PREVIEW (two lines)
    local k payload env
    wiz_base; payload=$(wiz_payload)
    wiz_list toggle
    env=(AGENTLINE_CONFIG=/dev/null COLUMNS="$WIZ_COLS" AGENTLINE_SEGMENTS="$REPLY")
    for k in GLYPHS BAR COMPACT_STYLE EFFORT_STYLE ULTRA_EFFECT BRANCH_ICON RESET_ICON; do env+=("AGENTLINE_$k=${WIZ_VAL[$k]}"); done
    [ -n "$WIZ_DEMO" ] && env+=("AGENTLINE_DEMO_GIT=$WIZ_DEMO")
    WIZ_PREVIEW=$(env "${env[@]}" bash "$SRC/claude/statusline.sh" <<<"$payload" 2>/dev/null)
}

wiz_draw() {
    local top row line val sel avail buf=$'\e[H'
    buf+=$'\e[1m agentline setup\e[0m\e[2m   ↑↓ move · ←→ change · space show/hide · enter save · q quit\e[K\e[0m\n\e[K\n'
    buf+=$'\e[2m Preview · '"$WIZ_SOURCE · $WIZ_COLS columns"$'\e[K\e[0m\n'
    buf+="  ${WIZ_PREVIEW%%$'\n'*}"$'\e[0m\e[K\n'"  ${WIZ_PREVIEW#*$'\n'}"$'\e[0m\e[K\n\e[K\n'
    # Scroll the settings so the cursor stays visible.
    avail=$((WIZ_LINES - 7)); ((avail < 5)) && avail=5
    top=$((WIZ_CUR - avail / 2)); ((top > ${#WIZ_ROWS[@]} - avail)) && top=$((${#WIZ_ROWS[@]} - avail)); ((top < 0)) && top=0
    for ((row = top; row < top + avail && row < ${#WIZ_ROWS[@]}; row++)); do
        sel=" "; ((row == WIZ_CUR)) && sel=$'\e[36m›\e[0m'
        case ${WIZ_TYPE[row]} in
            header) line=$'\e[1;2m  '"${WIZ_ROWS[row]}"$'\e[0m' ;;
            choice) label_of "${WIZ_VAL[${WIZ_KEY[row]}]}"
                    printf -v line ' %s %-26s \e[36m‹\e[0m %s \e[36m›\e[0m' "$sel" "${WIZ_ROWS[row]}" "$REPLY" ;;
            toggle|codex)
                    val=${WIZ_KEY[row]}; [ "${WIZ_TYPE[row]}" = codex ] && val="codex:$val"
                    [ "${WIZ_VAL[$val]}" = 1 ] && val=$'\e[32m■\e[0m' || val=$'\e[2m□\e[0m'
                    line=" $sel $val ${WIZ_ROWS[row]}" ;;
        esac
        ((row == WIZ_CUR)) && line=$'\e[1m'"$line"
        buf+="$line"$'\e[0m\e[K\n'
    done
    printf '%s\e[J' "$buf"
}

wiz_move() { # skip headers
    local d=$1 n=${#WIZ_ROWS[@]}
    WIZ_CUR=$(((WIZ_CUR + d + n) % n))
    [ "${WIZ_TYPE[WIZ_CUR]}" = header ] && WIZ_CUR=$(((WIZ_CUR + d + n) % n))
    return 0
}
wiz_change() { # cycle a choice or flip a toggle
    local d=$1 key=${WIZ_KEY[WIZ_CUR]} opts i n
    case ${WIZ_TYPE[WIZ_CUR]} in
        toggle) [ "${WIZ_VAL[$key]}" = 1 ] && WIZ_VAL[$key]=0 || WIZ_VAL[$key]=1 ;;
        codex) [ "${WIZ_VAL[codex:$key]}" = 1 ] && WIZ_VAL[codex:$key]=0 || WIZ_VAL[codex:$key]=1 ;;
        choice)
            read -ra opts <<<"${WIZ_OPTS[WIZ_CUR]}"; n=${#opts[@]}
            for i in "${!opts[@]}"; do [ "${opts[i]}" = "${WIZ_VAL[$key]}" ] && break; done
            WIZ_VAL[$key]=${opts[(i + d + n) % n]}
            # Nerd-only options follow the glyph set.
            if [ "${WIZ_VAL[GLYPHS]}" = unicode ]; then
                [ "${WIZ_VAL[BAR]}" = capsule ] && WIZ_VAL[BAR]=smooth
                WIZ_VAL[BRANCH_ICON]=unicode WIZ_VAL[RESET_ICON]=unicode
            elif [ "$key" = GLYPHS ]; then
                WIZ_VAL[BRANCH_ICON]=octicon WIZ_VAL[RESET_ICON]=octicon
            fi ;;
    esac
    return 0
}

wiz_size() {
    local s; s=$(stty size <"$TTY" 2>/dev/null) || s="40 110"
    WIZ_LINES=${s% *} WIZ_COLS=${s#* }
    [[ $WIZ_LINES =~ ^[0-9]+$ ]] || WIZ_LINES=40
    [[ $WIZ_COLS =~ ^[0-9]+$ ]] || WIZ_COLS=110
    WIZ_COLS=$((WIZ_COLS - 2))   # the preview is indented like Claude Code's own padding
}

wizard() {
    local k v key rest rc saved=0 resized=0 stty_saved=""
    WIZ_TMP=$(mktemp -d)
    printf '%s\n' '{"type":"attachment","attachment":{"type":"ultra_effort_enter"}}' > "$WIZ_TMP/ultra.jsonl"
    wiz_setup_rows
    # Defaults, then the saved configuration.
    WIZ_VAL=([SCENARIO]=session [GLYPHS]=unicode [BAR]=blocks [COMPACT_STYLE]=ramp [EFFORT_STYLE]=ramp
             [ULTRA_EFFECT]=rainbow [BRANCH_ICON]=unicode [RESET_ICON]=unicode [AUTO_UPDATE]=1)
    local AGENTLINE_SEGMENTS="dir git session meta model effort ctx 5h 7d cache cost lines" AGENTLINE_CODEX_ITEMS=""
    local AGENTLINE_GLYPHS="" AGENTLINE_BAR="" AGENTLINE_COMPACT_STYLE="" AGENTLINE_EFFORT_STYLE="" AGENTLINE_ULTRA_EFFECT=""
    local AGENTLINE_BRANCH_ICON="" AGENTLINE_RESET_ICON="" AGENTLINE_AUTO_UPDATE=""
    # shellcheck source=/dev/null
    [ -r "$CONF" ] && . "$CONF"
    for k in GLYPHS BAR COMPACT_STYLE EFFORT_STYLE ULTRA_EFFECT BRANCH_ICON RESET_ICON AUTO_UPDATE; do
        v="AGENTLINE_$k"; [ -n "${!v:-}" ] && WIZ_VAL[$k]=${!v}
    done
    for k in BRANCH_ICON RESET_ICON; do
        [ "${WIZ_VAL[$k]}" = auto ] && { [ "${WIZ_VAL[GLYPHS]}" = nerd ] && WIZ_VAL[$k]=octicon || WIZ_VAL[$k]=unicode; }
    done
    for k in dir git session meta model effort ctx 5h 7d cache cost lines; do
        [[ " $AGENTLINE_SEGMENTS " == *" $k "* ]] && WIZ_VAL[$k]=1 || WIZ_VAL[$k]=0
    done
    [ -n "$AGENTLINE_CODEX_ITEMS" ] || AGENTLINE_CODEX_ITEMS=$(grep -v '^[[:space:]]*\(#\|$\)' "$SRC/codex/preset" | tr '\n' ' ')
    for k in "${!WIZ_TYPE[@]}"; do
        [ "${WIZ_TYPE[k]}" = codex ] || continue
        [[ " $AGENTLINE_CODEX_ITEMS " == *" ${WIZ_KEY[k]} "* ]] && WIZ_VAL[codex:${WIZ_KEY[k]}]=1 || WIZ_VAL[codex:${WIZ_KEY[k]}]=0
    done

    exec 3<"$TTY"
    stty_saved=$(stty -g <"$TTY" 2>/dev/null) && stty -echo -icanon <"$TTY" 2>/dev/null
    printf '\e[?1049h\e[?25l'
    trap 'resized=1' WINCH
    WIZ_CUR=0
    wiz_size; wiz_render_preview; wiz_draw
    while :; do
        key=""
        if IFS= read -rsn1 -t 1 -u 3 key; then :
        else
            rc=$?
            ((rc > 128)) || break   # end of input: cancel
            # Timeout or resize: follow the new width and let animations run.
            ((resized)) && { resized=0; wiz_size; }
            wiz_render_preview; wiz_draw; continue
        fi
        case $key in
            $'\e') rest=""; IFS= read -rsn2 -t 0.05 -u 3 rest || true
                   case $rest in '[A') wiz_move -1 ;; '[B') wiz_move 1 ;; '[C') wiz_change 1 ;; '[D') wiz_change -1 ;; '') break ;; esac ;;
            k) wiz_move -1 ;; j) wiz_move 1 ;; l) wiz_change 1 ;; h) wiz_change -1 ;;
            ' ') wiz_change 1 ;;
            q|Q) break ;;
            '') saved=1; break ;;
        esac
        wiz_render_preview; wiz_draw
    done
    trap - WINCH
    printf '\e[?25h\e[?1049l'
    [ -n "$stty_saved" ] && stty "$stty_saved" <"$TTY" 2>/dev/null
    exec 3<&-
    rm -rf "$WIZ_TMP"
    if ((!saved)); then echo "agentline: setup cancelled, nothing changed." >&2; exit 1; fi
    # shellcheck disable=SC2034  # SET belongs to install.sh
    for k in GLYPHS BAR COMPACT_STYLE EFFORT_STYLE ULTRA_EFFECT BRANCH_ICON RESET_ICON AUTO_UPDATE; do SET[$k]=${WIZ_VAL[$k]}; done
    wiz_list toggle; SET[SEGMENTS]=$REPLY
    if ((do_codex)); then wiz_list codex; SET[CODEX_ITEMS]=$REPLY; fi
    return 0
}
