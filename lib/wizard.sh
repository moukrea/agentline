# shellcheck shell=bash
# agentline setup assistant, sourced by install.sh. Every choice is previewed
# with the real renderer (claude/statusline.sh) on a sample session.
# Reads answers from $TTY (the terminal, even when the installer is piped from
# curl); writes the choices into the SET array of install.sh.

# preview <line: 1|2|both> [VAR=value ...]: render the sample status line.
preview() {
    local which=$1; shift
    local payload out
    payload=$(jq --arg home "$HOME" --argjson n "$EPOCHSECONDS" '
        .cwd |= sub("^HOME"; $home) | .workspace.current_dir = .cwd
        | .prompt_cache.expires_at = $n + .prompt_cache.expires_at
        | (.rate_limits[].resets_at) |= $n + .' "$SRC/lib/sample.json")
    out=$(env AGENTLINE_CONFIG=/dev/null AGENTLINE_DEMO_GIT="feat/billing-export 2 1 3 1 0 0" \
          COLUMNS=$((WIZ_COLS - 5)) "$@" bash "$SRC/claude/statusline.sh" <<<"$payload")
    case $which in
        1) printf '     %s\n' "${out%%$'\n'*}" ;;
        2) printf '     %s\n' "${out#*$'\n'}" ;;
        *) printf '     %s\n' "${out%%$'\n'*}" "${out#*$'\n'}" ;;
    esac
}

# ask <prompt> <default> → REPLY
ask() {
    printf '\n  %s \033[2m[%s]\033[0m ' "$1" "$2"
    read -r -u 3 REPLY || REPLY=""
    REPLY=${REPLY:-$2}
}

# menu <title> <default-index> <option>... : options are "value|label"; the
# caller prints previews through MENU_PREVIEW <value> (optional).
menu() {
    local title=$1 def=$2 i=1 opt; shift 2
    printf '\n\033[1m%s\033[0m\n' "$title"
    for opt in "$@"; do
        printf '\n  \033[36m%d)\033[0m %s\n' "$i" "${opt#*|}"
        declare -F MENU_PREVIEW >/dev/null && MENU_PREVIEW "${opt%%|*}"
        i=$((i + 1))
    done
    while :; do
        ask "Choice (1-$#)" "$def"
        [[ $REPLY =~ ^[0-9]+$ ]] && ((REPLY >= 1 && REPLY <= $#)) && break
        printf '  Type a number between 1 and %d.\n' "$#"
    done
    opt=${*:REPLY:1}; REPLY=${opt%%|*}
}

index_of() { # index_of <value> <option>... → 1-based position, 1 if absent
    local v=$1 i=1 o; shift
    for o in "$@"; do [ "${o%%|*}" = "$v" ] && { echo "$i"; return; }; i=$((i + 1)); done
    echo 1
}

wizard() {
    exec 3<"$TTY"
    local w; w=$(stty size <"$TTY" 2>/dev/null) && w=${w#* } || w=100
    [[ $w =~ ^[0-9]+$ ]] || w=100
    ((w < 70)) && w=70; ((w > 150)) && w=150
    WIZ_COLS=$w

    # Current values are the defaults.
    local glyphs=unicode bar=blocks branch=auto reset=auto auto=1
    if [ -r "$CONF" ]; then
        glyphs=$(sed -n 's/^AGENTLINE_GLYPHS=//p' "$CONF"); bar=$(sed -n 's/^AGENTLINE_BAR=//p' "$CONF")
        branch=$(sed -n 's/^AGENTLINE_BRANCH_ICON=//p' "$CONF"); reset=$(sed -n 's/^AGENTLINE_RESET_ICON=//p' "$CONF")
        auto=$(sed -n 's/^AGENTLINE_AUTO_UPDATE=//p' "$CONF")
    fi

    while :; do
        printf '\n\033[1magentline setup\033[0m  \033[2m(Enter keeps the value in brackets)\033[0m\n'

        printf '\n\033[1mGlyphs\033[0m\n  Nerd Font icons look like this on your terminal: \033[36m%s\033[0m\n' $'\uf418  \uf464  \uf457  \uf459'
        printf '  If you see icons rather than empty boxes or question marks, your font has them.\n'
        printf '  Recommended font: JuliaMono, with Symbols Nerd Font Mono as fallback (see README).\n'
        local G=("nerd|Nerd Font icons" "unicode|Unicode only (works with any font)")
        unset -f MENU_PREVIEW
        menu "Which glyphs?" "$(index_of "${glyphs:-unicode}" "${G[@]}")" "${G[@]}"; glyphs=$REPLY

        local B=("capsule|Capsule, rounded ends (Nerd)" "smooth|Smooth, eighth-cell on a solid rail" "blocks|Blocks █▒░" \
                 "line|Line ━╸─" "segments|Segments ■□" "braille|Braille ⣿⣀")
        [ "$glyphs" = nerd ] || B=("${B[@]:1}")
        MENU_PREVIEW() { preview 2 AGENTLINE_GLYPHS="$glyphs" AGENTLINE_BAR="$1"; }
        menu "Progress bars" "$(index_of "${bar:-blocks}" "${B[@]}")" "${B[@]}"; bar=$REPLY

        if [ "$glyphs" = nerd ]; then
            local BR=("octicon|Octicon git-branch" "powerline|Powerline branch" "devicon|Devicon git-branch" "unicode|Unicode ⎇")
            MENU_PREVIEW() { preview 1 AGENTLINE_GLYPHS=nerd AGENTLINE_BAR="$bar" AGENTLINE_BRANCH_ICON="$1"; }
            menu "Branch icon" "$(index_of "${branch/auto/octicon}" "${BR[@]}")" "${BR[@]}"; branch=$REPLY
            local RS=("octicon|Octicon history" "mdi-history|Material history" "mdi-progress-clock|Material progress clock" \
                      "mdi-refresh|Material refresh" "unicode|Unicode ↻")
            MENU_PREVIEW() { preview 2 AGENTLINE_GLYPHS=nerd AGENTLINE_BAR="$bar" AGENTLINE_RESET_ICON="$1"; }
            menu "Reset-time icon (5h / 7d limits)" "$(index_of "${reset/auto/octicon}" "${RS[@]}")" "${RS[@]}"; reset=$REPLY
        else
            branch=unicode reset=unicode
        fi
        unset -f MENU_PREVIEW

        ask "Update agentline automatically (one background check a day)? (y/n)" "$([ "${auto:-1}" = 1 ] && echo y || echo n)"
        [[ $REPLY =~ ^[Yy] ]] && auto=1 || auto=0

        printf '\n\033[1mResult\033[0m\n'
        preview both AGENTLINE_GLYPHS="$glyphs" AGENTLINE_BAR="$bar" AGENTLINE_BRANCH_ICON="$branch" AGENTLINE_RESET_ICON="$reset"
        ask "Keep these settings? (y = install, n = start over)" y
        [[ $REPLY =~ ^[Nn] ]] || break
    done
    exec 3<&-
    # shellcheck disable=SC2034  # SET belongs to install.sh
    SET[GLYPHS]=$glyphs SET[BAR]=$bar SET[BRANCH_ICON]=$branch SET[RESET_ICON]=$reset SET[AUTO_UPDATE]=$auto
    echo
}
