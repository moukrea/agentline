# shellcheck shell=bash disable=SC2034,SC2154  # shares state with install.sh, which sources it
# agentline setup assistant, sourced by install.sh.
#
# Full-screen: the real renderer (claude/statusline.sh) draws the preview at
# the terminal's width, from your last Claude Code session when there is one,
# re-rendered on every change, every second (animations) and on resize.
# Keys come from $TTY (the terminal, even under `curl | bash`); the result goes
# into the SET array of install.sh.
#
# Previews never call automodel (it would run once a second, for a session id
# it does not know): the "automodel" scenario passes a sample answer in
# AGENTLINE_AUTOMODEL_JSON, every other scenario shows the session as not
# routed. Previews also keep their caches in a directory of their own, so the
# renderer's "last session" stays the real one.

WIZ_ROWS=() WIZ_TYPE=() WIZ_KEY=() WIZ_OPTS=()   # parallel arrays, one entry per row
declare -A WIZ_VAL

wiz_row() { # wiz_row <type: choice|toggle|codex|fold|header|note> <key> <label> [options...]
    WIZ_TYPE+=("$1"); WIZ_KEY+=("$2"); WIZ_ROWS+=("$3"); shift 3; WIZ_OPTS+=("$*")
}

wiz_setup_rows() {
    wiz_row choice SCENARIO "Preview as" session ultracode limits cold automodel
    wiz_row header "" "Look"
    wiz_row choice GLYPHS "Glyphs" nerd unicode
    if ((!WIZ_HAVE_NERD)); then
        wiz_row note "" "No Nerd Font found on this machine: Nerd icons need one. "$'\e]8;;'"$FONTS_URL"$'\e\\'"Font guide"$'\e]8;;\e\\'" ($FONTS_URL)"
    fi
    wiz_row choice THEME "Theme" dark light
    if [ -n "$WIZ_LAYOUT_CUSTOM" ]; then wiz_row choice LAYOUT "Layout" two one custom
    else wiz_row choice LAYOUT "Layout" two one; fi
    wiz_row choice BAR "Bars (context, 5h, 7d)" capsule smooth blocks line segments braille ramp dots bars squares pie none
    wiz_row choice COMPACT_STYLE "Compact gauges (narrow)" capsule smooth blocks line segments braille ramp dots bars squares pie none
    wiz_row choice EFFORT_STYLE "Effort gauge" auto capsule smooth blocks line segments braille ramp dots bars squares pie none
    wiz_row choice ULTRA_EFFECT "Ultracode effect" rainbow violet plain
    wiz_row choice BRANCH_ICON "Branch icon" octicon powerline devicon unicode
    wiz_row choice RESET_ICON "Reset-time icon" octicon mdi-history mdi-progress-clock mdi-refresh unicode
    wiz_row choice AUTO_UPDATE "Automatic updates" 1 0
    wiz_row header "" "Claude Code: information shown"
    local seg
    for seg in "dir|Directory" "git|Git branch and status" "session|Session name" "meta|Output style, agent, vim mode" \
               "model|Model" "effort|Reasoning effort" "route|Routing details (automodel)" \
               "ctx|Context window" "5h|5-hour limit" "7d|7-day limit" \
               "cache|Prompt cache" "cost|Cost and duration" "lines|Lines edited"; do
        wiz_row toggle "${seg%%|*}" "${seg#*|}"
    done
    wiz_row header "" "automodel (picks the model and effort of each prompt)"
    wiz_row choice AUTOMODEL "automodel routing" auto off
    wiz_row note "" "$WIZ_AM_NOTE" "$WIZ_AM_NOTE_KIND"
    if ((do_codex)); then
        wiz_row header "" "Codex (it draws its own line: only its items can be chosen)"
        wiz_row choice CODEX_MIRROR "Mirror Claude Code" 1 0
        wiz_row fold CODEX_OPEN "Items"
        for seg in $(sed -n '/^# Available:/,/^[^#]/p' "$SRC/codex/preset" | grep '^#' | sed 's/^# *//; s/^Available://' | tr ',' ' '); do
            wiz_row codex "$seg" "$seg"
        done
    fi
}

label_of() { # label_of <value> [key]: human label of an option value → REPLY
    case ${2:-}:$1 in
        THEME:dark) REPLY="dark background"; return ;; THEME:light) REPLY="light background"; return ;;
        LAYOUT:two) REPLY="two lines"; return ;; LAYOUT:one) REPLY="one line"; return ;;
        LAYOUT:custom) REPLY="custom (from config): $WIZ_LAYOUT_CUSTOM"; ((${#REPLY} > 60)) && REPLY="${REPLY:0:59}…"; return 0 ;;
        AUTOMODEL:auto) REPLY="shown when it routes the session"; return ;; AUTOMODEL:off) REPLY=off; return ;;
    esac
    case $1 in
        1) REPLY=on ;; 0) REPLY=off ;; auto) REPLY="same as the bars" ;; session) REPLY="your last session" ;; ultracode) REPLY=ultracode ;;
        limits) REPLY="near the limits" ;; cold) REPLY="cold prompt cache" ;; automodel) REPLY="routed by automodel (sample)" ;; ramp) REPLY="ramp ▁▂▄▆█" ;;
        pie) REPLY="pie ◔" ;; braille) REPLY="braille ⣿⣶⣀" ;; none) REPLY="none (value only)" ;;
        dots) REPLY="dots ●●○" ;; bars) REPLY="bars ▰▰▱" ;; squares) REPLY="squares ■■□" ;;
        capsule) REPLY="capsule (Nerd)" ;; blocks) REPLY="blocks █▒░" ;; line) REPLY="line ━╸─" ;;
        segments) REPLY="segments ■□" ;; smooth) REPLY="smooth" ;; nerd) REPLY="Nerd Font icons" ;;
        unicode) REPLY="Unicode" ;; rainbow) REPLY="rainbow" ;; violet) REPLY="Claude violet, sweeping highlight" ;;
        plain) REPLY="plain violet" ;; mdi-history) REPLY="Material history" ;; mdi-progress-clock) REPLY="Material clock" ;;
        mdi-refresh) REPLY="Material refresh" ;; *) REPLY=$1 ;;
    esac
}

# The session the preview renders, taken once when the assistant opens (so only
# the animation moves): your last Claude Code session if any, else a sample. The
# directory is the one you run the assistant from, with its real git state, or a
# simulated repository when it is not one.
wiz_snapshot() {
    local last="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"   # the renderer's cache directory
    last="${last%/}/agentline-$UID/last-payload.json"
    WIZ_BASE="$WIZ_TMP/base.json" WIZ_SOURCE="your last Claude Code session"
    if [ -s "$last" ] && [ -O "$last" ] && [ ! -L "$last" ] && jq -e . "$last" >/dev/null 2>&1; then cp "$last" "$WIZ_BASE"
    else
        WIZ_SOURCE="sample session"
        jq --argjson n "$EPOCHSECONDS" '.prompt_cache.expires_at = $n + .prompt_cache.expires_at
            | (.rate_limits[].resets_at) |= $n + .' "$SRC/lib/sample.json" > "$WIZ_BASE"
    fi
    jq --arg d "$PWD" '.cwd = $d | .workspace.current_dir = $d | .workspace.project_dir = $d' "$WIZ_BASE" > "$WIZ_BASE.tmp" && mv "$WIZ_BASE.tmp" "$WIZ_BASE"
    if git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1; then WIZ_DEMO=""
    else WIZ_DEMO="feat/billing-export 2 1 3 1 0 0"; WIZ_SOURCE+=", simulated git"; fi
}
wiz_payload() { # the session, adjusted to the scenario → stdout
    local base=$WIZ_BASE tr="$WIZ_TMP/ultra.jsonl"
    case $WIZ_SCENARIO in
        ultracode) jq --arg tr "$tr" '.session_id = "agentline-wizard-ultra" | .effort.level = "xhigh" | .transcript_path = $tr' "$base" ;;
        limits) jq --argjson n "$EPOCHSECONDS" '.session_id = "agentline-wizard"
            | .context_window.context_window_size = (.context_window.context_window_size // 200000)
            | .context_window.current_usage = {input_tokens: (.context_window.context_window_size * 0.88 | floor)}
            | .rate_limits = {five_hour: {used_percentage: 64, resets_at: ($n + 9000)}, seven_day: {used_percentage: 81, resets_at: ($n + 200000)}}
            | .prompt_cache = {caching_observed: true, warm: true, expires_at: ($n + 200), ttl: "1h"}' "$base" ;;
        cold) jq '.session_id = "agentline-wizard" | .prompt_cache = {caching_observed: true, warm: false, expires_at: 0, ttl: "1h"}' "$base" ;;
        automodel) jq '.session_id = "agentline-wizard-am" | .model = {id: "jev", display_name: "Jev (auto)"}
            | .effort.level = "medium" | .transcript_path = null' "$base" ;;
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

# The renderer's environment for a preview → WIZ_ENV.
WIZ_AM_SAMPLE='{"v":1,"routed":true,"alias":"jev","model":"opus-5.5","label":"Opus 5.5","effort":"xhigh","mode":"","state":"routed","confidence":0.86,"pin":"","issue":"","flash":"switched","text":"jev → opus-5.5·xhigh 0.86"}'
wiz_env() {
    local k layout=${WIZ_VAL[LAYOUT]}
    [ "$layout" = custom ] && layout=$WIZ_LAYOUT_CUSTOM
    wiz_list toggle
    WIZ_ENV=(AGENTLINE_CONFIG=/dev/null XDG_RUNTIME_DIR="$WIZ_TMP/run" AGENTLINE_SEGMENTS="$REPLY" AGENTLINE_LAYOUT="$layout")
    for k in GLYPHS BAR COMPACT_STYLE EFFORT_STYLE ULTRA_EFFECT BRANCH_ICON RESET_ICON THEME AUTOMODEL; do
        WIZ_ENV+=("AGENTLINE_$k=${WIZ_VAL[$k]}")
    done
    if [ "$WIZ_SCENARIO" = automodel ]; then WIZ_ENV+=("AGENTLINE_AUTOMODEL_JSON=$WIZ_AM_SAMPLE")
    else WIZ_ENV+=('AGENTLINE_AUTOMODEL_JSON={"v":1,"routed":false}'); fi
    [ -n "$WIZ_DEMO" ] && WIZ_ENV+=("AGENTLINE_DEMO_GIT=$WIZ_DEMO")
    return 0
}

# Widest width at which this session switches to compact gauges (found by
# rendering with and without them, on a pinned clock), cached per situation.
wiz_compact_width() {
    local payload=$1 key a b
    wiz_env; WIZ_ENV+=("AGENTLINE_NOW=$EPOCHSECONDS")
    key="$WIZ_COLS|$WIZ_SCENARIO|${WIZ_ENV[*]:0:${#WIZ_ENV[@]}-1}"
    if [ "$key" != "${WIZ_CW_KEY:-}" ]; then
        WIZ_CW_KEY=$key WIZ_CW=$WIZ_COLS
        differs() { # does <width> show compact gauges?
            a=$(env "${WIZ_ENV[@]}" COLUMNS="$1" AGENTLINE_COMPACT_STYLE=none "$BASH" "$SRC/claude/statusline.sh" <<<"$payload" 2>/dev/null)
            b=$(env "${WIZ_ENV[@]}" COLUMNS="$1" AGENTLINE_COMPACT_STYLE=dots "$BASH" "$SRC/claude/statusline.sh" <<<"$payload" 2>/dev/null)
            [ "$a" != "$b" ]
        }
        if differs 40; then   # binary search for the widest such width
            local lo=40 hi=$WIZ_COLS mid
            while ((lo < hi)); do mid=$(((lo + hi + 1) / 2)); if differs "$mid"; then lo=$mid; else hi=$((mid - 1)); fi; done
            WIZ_CW=$lo
        fi
    fi
    REPLY=$WIZ_CW
}

wiz_render_preview() { # → WIZ_PREVIEW (one line per status line)
    local payload
    # The row under the cursor can call for a situation: ultracode for its
    # effect, automodel's routing for its rows, a narrow terminal for the
    # compact gauges.
    WIZ_SCENARIO=${WIZ_VAL[SCENARIO]} WIZ_WIDTH=$WIZ_COLS WIZ_NOTE=""
    case ${WIZ_KEY[WIZ_CUR]} in
        ULTRA_EFFECT) WIZ_SCENARIO=ultracode; WIZ_NOTE=" · showing ultracode" ;;
        AUTOMODEL|route) WIZ_SCENARIO=automodel; WIZ_NOTE=" · showing a session routed by automodel (sample)" ;;
        COMPACT_STYLE) WIZ_WIDTH=-1 ;;
    esac
    payload=$(wiz_payload)
    if ((WIZ_WIDTH < 0)); then wiz_compact_width "$payload"; WIZ_WIDTH=$REPLY
        ((WIZ_WIDTH < WIZ_COLS)) && WIZ_NOTE=" · narrowed to show the compact gauges"; fi
    wiz_env
    WIZ_PREVIEW=$(env "${WIZ_ENV[@]}" COLUMNS="$WIZ_WIDTH" "$BASH" "$SRC/claude/statusline.sh" <<<"$payload" 2>/dev/null)
}

wiz_draw() {
    local top row line val sel avail k n=0 buf=$'\e[H'
    buf+=$'\e[1m agentline setup\e[0m\e[2m   ↑↓ move · ←→ change · space show/hide · enter save · q quit\e[K\e[0m\n\e[K\n'
    buf+=$'\e[2m Preview · '"$WIZ_SOURCE · $WIZ_WIDTH columns$WIZ_NOTE"$'\e[K\e[0m\n'
    while IFS= read -r line; do buf+="  $line"$'\e[0m\e[K\n'; n=$((n + 1)); done <<<"$WIZ_PREVIEW"
    if ((do_codex)); then wiz_list codex; buf+=$'\e[2m  Codex: '"${REPLY// / · }"$'\e[0m\e[K\n'; fi
    buf+=$'\e[K\n'
    # Scroll the visible settings so the cursor stays on screen.
    local vis=() pos=0 j
    for row in "${!WIZ_ROWS[@]}"; do wiz_visible "$row" && { ((row == WIZ_CUR)) && pos=${#vis[@]}; vis+=("$row"); }; done
    avail=$((WIZ_LINES - 6 - n)); ((avail < 5)) && avail=5
    top=$((pos - avail / 2)); ((top > ${#vis[@]} - avail)) && top=$((${#vis[@]} - avail)); ((top < 0)) && top=0
    for ((j = top; j < top + avail && j < ${#vis[@]}; j++)); do
        row=${vis[j]}
        sel=" "; ((row == WIZ_CUR)) && sel=$'\e[36m›\e[0m'
        case ${WIZ_TYPE[row]} in
            header) line=$'\e[1;2m  '"${WIZ_ROWS[row]}"$'\e[0m' ;;
            note)   [ "${WIZ_OPTS[row]}" = dim ] && k=$'\e[2m' || k=$'\e[33m'
                    line="   $k${WIZ_ROWS[row]}"$'\e[0m' ;;
            fold)   wiz_list codex; val=$REPLY; ((${#val} > 60)) && val="${val:0:59}…"
                    [ "${WIZ_VAL[CODEX_OPEN]}" = 1 ] && k="▾" || k="▸"
                    line=" $sel $k ${WIZ_ROWS[row]}  "$'\e[2m'"${val// / · }"$'\e[0m' ;;
            choice) label_of "${WIZ_VAL[${WIZ_KEY[row]}]}" "${WIZ_KEY[row]}"
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

wiz_visible() { # wiz_visible <row>: Codex items only when their fold is open
    [ "${WIZ_TYPE[$1]}" != codex ] || [ "${WIZ_VAL[CODEX_OPEN]}" = 1 ]
}
wiz_move() { # to the next visible, selectable row
    local d=$1 n=${#WIZ_ROWS[@]} i
    for ((i = 0; i < n; i++)); do
        WIZ_CUR=$(((WIZ_CUR + d + n) % n))
        case ${WIZ_TYPE[WIZ_CUR]} in header|note) continue ;; esac
        wiz_visible "$WIZ_CUR" && break
    done
    return 0
}
wiz_mirror() { # tick the Codex items closest to the Claude Code parts shown
    local i items
    wiz_list toggle; items=" $(mirror_items "$REPLY") "
    for i in "${!WIZ_TYPE[@]}"; do
        [ "${WIZ_TYPE[i]}" = codex ] || continue
        [[ $items == *" ${WIZ_KEY[i]} "* ]] && WIZ_VAL[codex:${WIZ_KEY[i]}]=1 || WIZ_VAL[codex:${WIZ_KEY[i]}]=0
    done
}
wiz_change() { # cycle a choice or flip a toggle
    local d=$1 key=${WIZ_KEY[WIZ_CUR]} opts i n k
    case ${WIZ_TYPE[WIZ_CUR]} in
        toggle) [ "${WIZ_VAL[$key]}" = 1 ] && WIZ_VAL[$key]=0 || WIZ_VAL[$key]=1 ;;
        codex) [ "${WIZ_VAL[codex:$key]}" = 1 ] && WIZ_VAL[codex:$key]=0 || WIZ_VAL[codex:$key]=1
               WIZ_VAL[CODEX_MIRROR]=0 ;;   # picking items by hand ends mirroring
        fold) [ "${WIZ_VAL[$key]}" = 1 ] && WIZ_VAL[$key]=0 || WIZ_VAL[$key]=1 ;;
        choice)
            read -ra opts <<<"${WIZ_OPTS[WIZ_CUR]}"; n=${#opts[@]}
            for i in "${!opts[@]}"; do [ "${opts[i]}" = "${WIZ_VAL[$key]}" ] && break; done
            WIZ_VAL[$key]=${opts[(i + d + n) % n]}
            # Nerd-only options follow the glyph set.
            # Back to Nerd glyphs, capsules made smooth by Unicode come back.
            if [ "${WIZ_VAL[GLYPHS]}" = unicode ]; then
                for k in BAR COMPACT_STYLE EFFORT_STYLE; do
                    [ "${WIZ_VAL[$k]}" = capsule ] && WIZ_VAL[$k]=smooth WIZ_VAL[nerd:$k]=capsule
                done
                WIZ_VAL[BRANCH_ICON]=unicode WIZ_VAL[RESET_ICON]=unicode
            elif [ "$key" = GLYPHS ]; then
                for k in BAR COMPACT_STYLE EFFORT_STYLE; do
                    [ "${WIZ_VAL[nerd:$k]:-}" = capsule ] && [ "${WIZ_VAL[$k]}" = smooth ] && WIZ_VAL[$k]=capsule
                    WIZ_VAL[nerd:$k]=""
                done
                WIZ_VAL[BRANCH_ICON]=octicon WIZ_VAL[RESET_ICON]=octicon
            fi ;;
    esac
    [ "${WIZ_VAL[CODEX_MIRROR]:-0}" = 1 ] && wiz_mirror
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
    local k v key rest rc saved=0 resized=0
    WIZ_TMP=$(mktemp -d); mkdir -p "$WIZ_TMP/run"
    printf '%s\n' '{"type":"attachment","attachment":{"type":"ultra_effort_enter"}}' > "$WIZ_TMP/ultra.jsonl"
    # Defaults, then the saved configuration.
    # The maintainer's setup when a Nerd Font is installed, safe glyphs otherwise.
    WIZ_HAVE_NERD=0; have_nerd_font && WIZ_HAVE_NERD=1
    if ((WIZ_HAVE_NERD)); then
        WIZ_VAL=([GLYPHS]=nerd [BAR]=capsule [BRANCH_ICON]=octicon [RESET_ICON]=octicon)
    else
        WIZ_VAL=([GLYPHS]=unicode [BAR]=smooth [BRANCH_ICON]=unicode [RESET_ICON]=unicode)
    fi
    WIZ_VAL+=([SCENARIO]=session [COMPACT_STYLE]=pie [EFFORT_STYLE]=dots [ULTRA_EFFECT]=violet
              [AUTO_UPDATE]=1 [CODEX_MIRROR]=1 [CODEX_OPEN]=0 [THEME]=dark [LAYOUT]=two [AUTOMODEL]=auto)
    local AGENTLINE_SEGMENTS=$ALL_SEGMENTS AGENTLINE_CODEX_ITEMS="" AGENTLINE_CONFIG_VERSION=2
    local AGENTLINE_GLYPHS="" AGENTLINE_BAR="" AGENTLINE_COMPACT_STYLE="" AGENTLINE_EFFORT_STYLE="" AGENTLINE_ULTRA_EFFECT=""
    local AGENTLINE_BRANCH_ICON="" AGENTLINE_RESET_ICON="" AGENTLINE_AUTO_UPDATE="" AGENTLINE_CODEX_MIRROR=""
    local AGENTLINE_THEME="" AGENTLINE_LAYOUT="" AGENTLINE_AUTOMODEL=""
    # shellcheck source=/dev/null
    [ -r "$CONF" ] && { AGENTLINE_CONFIG_VERSION=""; . "$CONF"; }
    for k in GLYPHS BAR COMPACT_STYLE EFFORT_STYLE ULTRA_EFFECT BRANCH_ICON RESET_ICON AUTO_UPDATE CODEX_MIRROR; do
        v="AGENTLINE_$k"; [ -n "${!v:-}" ] && WIZ_VAL[$k]=${!v}
    done
    [ "$AGENTLINE_THEME" = light ] && WIZ_VAL[THEME]=light
    case $AGENTLINE_AUTOMODEL in off|0) WIZ_VAL[AUTOMODEL]=off ;; esac
    WIZ_LAYOUT_CUSTOM=""
    case $AGENTLINE_LAYOUT in
        ""|two) ;; one) WIZ_VAL[LAYOUT]=one ;;
        *) WIZ_VAL[LAYOUT]=custom WIZ_LAYOUT_CUSTOM=$AGENTLINE_LAYOUT ;;   # kept as is unless changed
    esac
    # A config from before version 2 gets the route part, as config_apply does.
    [ "$AGENTLINE_CONFIG_VERSION" = 2 ] || { with_route "$AGENTLINE_SEGMENTS"; AGENTLINE_SEGMENTS=$REPLY; }
    # Is automodel there (found the way the renderer finds it)?
    WIZ_AM_NOTE_KIND=dim
    if am_find; then
        if am_has_json; then WIZ_AM_NOTE="automodel found: routed sessions show the model and effort it chose, and how"
        else WIZ_AM_NOTE="automodel found, but this release has no \`statusline --json\`: update it (automodel update)" WIZ_AM_NOTE_KIND=""; fi
    else
        WIZ_AM_NOTE="automodel not found in $CLAUDE_SETTINGS: nothing to show without it"
    fi
    wiz_setup_rows
    [ "${WIZ_VAL[COMPACT_STYLE]}" = minibar ] && WIZ_VAL[COMPACT_STYLE]=${WIZ_VAL[BAR]}
    for k in BAR COMPACT_STYLE EFFORT_STYLE; do case ${WIZ_VAL[$k]} in text|percent) WIZ_VAL[$k]=none ;; esac; done
    for k in BRANCH_ICON RESET_ICON; do
        [ "${WIZ_VAL[$k]}" = auto ] && { [ "${WIZ_VAL[GLYPHS]}" = nerd ] && WIZ_VAL[$k]=octicon || WIZ_VAL[$k]=unicode; }
    done
    for k in $ALL_SEGMENTS; do
        [[ " $AGENTLINE_SEGMENTS " == *" $k "* ]] && WIZ_VAL[$k]=1 || WIZ_VAL[$k]=0
    done
    [ -n "$AGENTLINE_CODEX_ITEMS" ] || AGENTLINE_CODEX_ITEMS=$(grep -Ev '^[[:space:]]*(#|$)' "$SRC/codex/preset" | tr '\n' ' ')
    [ "${WIZ_VAL[CODEX_MIRROR]}" = 1 ] && AGENTLINE_CODEX_ITEMS=$(mirror_items "$AGENTLINE_SEGMENTS")
    for k in "${!WIZ_TYPE[@]}"; do
        [ "${WIZ_TYPE[k]}" = codex ] || continue
        [[ " $AGENTLINE_CODEX_ITEMS " == *" ${WIZ_KEY[k]} "* ]] && WIZ_VAL[codex:${WIZ_KEY[k]}]=1 || WIZ_VAL[codex:${WIZ_KEY[k]}]=0
    done

    exec 3<"$TTY"
    WIZ_STTY=$(stty -g <"$TTY" 2>/dev/null) && stty -echo -icanon <"$TTY" 2>/dev/null
    # Whatever happens (an error, Ctrl-C), the terminal is given back as it was.
    trap 'printf "\e[?25h\e[?1049l"; [ -z "$WIZ_STTY" ] || stty "$WIZ_STTY" <"$TTY" 2>/dev/null; rm -rf "$WIZ_TMP"' EXIT
    printf '\e[?1049h\e[?25l'
    trap 'resized=1' WINCH
    WIZ_CUR=0
    wiz_snapshot; wiz_size; wiz_render_preview; wiz_draw
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
    trap - WINCH EXIT
    printf '\e[?25h\e[?1049l'
    [ -n "$WIZ_STTY" ] && stty "$WIZ_STTY" <"$TTY" 2>/dev/null
    exec 3<&-
    rm -rf "$WIZ_TMP"
    if ((!saved)); then echo "agentline: setup cancelled, nothing changed." >&2; exit 1; fi
    # shellcheck disable=SC2034  # SET belongs to install.sh
    for k in GLYPHS BAR COMPACT_STYLE EFFORT_STYLE ULTRA_EFFECT BRANCH_ICON RESET_ICON AUTO_UPDATE THEME AUTOMODEL; do SET[$k]=${WIZ_VAL[$k]}; done
    if [ "${WIZ_VAL[LAYOUT]}" = custom ]; then SET[LAYOUT]=$WIZ_LAYOUT_CUSTOM; else SET[LAYOUT]=${WIZ_VAL[LAYOUT]}; fi
    ((do_codex)) && SET[CODEX_MIRROR]=${WIZ_VAL[CODEX_MIRROR]}
    wiz_list toggle; SET[SEGMENTS]=$REPLY
    if ((do_codex)); then wiz_list codex; SET[CODEX_ITEMS]=$REPLY; fi
    return 0
}
