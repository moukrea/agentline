#!/usr/bin/env bash
# agentline test suite: rendering at every width/style, and idempotent
# install/uninstall for Claude Code and Codex in a throwaway HOME.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fail=0 pass=0
SHA=(sha256sum); command -v sha256sum >/dev/null || SHA=(shasum -a 256)   # macOS
check() { if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: ${CHECK_NAME:-$*}"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" XDG_DATA_HOME="$TMP/home/.local/share" XDG_RUNTIME_DIR="$TMP/run"
unset CLAUDE_CONFIG_DIR CODEX_HOME
export AGENTLINE_ASSUME_NERD=1   # font detection is tested on its own below
export AGENTLINE_AUTO_UPDATE=0     # the real background update from GitHub raced the checks
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"

# A git repository with staged, modified and untracked files for the fixtures.
REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b feat/a-rather-long-branch-name-for-truncation
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo a > "$REPO/staged"; git -C "$REPO" add staged; echo b > "$REPO/untracked"

# Display width of a line: ANSI stripped, East Asian wide/fullwidth = 2 cells.
width() { python3 -c '
import re, sys, unicodedata
for line in sys.stdin:
    s = re.sub(r"\x1b\[[0-9;]*m", "", line.rstrip("\n"))
    print(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s))'; }

# macOS's libc takes bytes >= 0x80 for letters in UTF-8 locales, so bash reads
# "$REPLY█" as the variable REPLY█: a name right before a non-ASCII character
# must be braced ("${REPLY}█").
bad=$(LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$ROOT"/claude/statusline.sh "$ROOT"/install.sh "$ROOT"/lib/wizard.sh "$ROOT"/bin/agentline | grep -v '^\s*#')
CHECK_NAME="no unbraced \$name before a non-ASCII character: $bad"; check test -z "$bad"

# ── Rendering ───────────────────────────────────────────────────────────────
echo "rendering"
now=$(date +%s)
for fx in "$ROOT"/tests/fixtures/*.json; do
    payload=$(jq --arg cwd "$REPO" --arg tr "$ROOT/tests/fixtures/ultra-transcript.jsonl" --argjson n "$now" '.cwd = $cwd | .workspace.current_dir = $cwd
        | (.transcript_path |= (if . == "ULTRA_TRANSCRIPT" then $tr else . end))
        | (.prompt_cache.expires_at |= (if . then $n + . else . end))
        | (.rate_limits[]?.resets_at |= $n + .)' "$fx")
    for glyphs in unicode nerd; do
        for bar in blocks smooth line segments braille capsule; do
            for cols in 40 50 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200; do
                out=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_GLYPHS=$glyphs AGENTLINE_BAR=$bar COLUMNS=$cols \
                      bash "$ROOT/claude/statusline.sh" <<<"$payload" 2>"$TMP/err")
                CHECK_NAME="$(basename "$fx") $glyphs/$bar @$cols: exit and no stderr"
                check test -z "$(cat "$TMP/err")"
                CHECK_NAME="$(basename "$fx") $glyphs/$bar @$cols: two lines"
                check test "$(printf '%s\n' "$out" | wc -l)" -eq 2
                max=$(printf '%s\n' "$out" | width | sort -n | tail -1)
                CHECK_NAME="$(basename "$fx") $glyphs/$bar @$cols: width $max > $((cols - 4))"
                # Below ~60 columns the most compact layout can still be wider than
                # the terminal; that is the only accepted overflow.
                ((cols >= 60)) && check test "$max" -le $((cols - 4))
            done
        done
    done
done

for cs in ramp capsule pie braille dots none; do
    for es in ramp dots capsule segments pie none; do
        for ue in rainbow violet plain; do
            for cols in 60 100 160; do
                out=$(jq --arg tr "$ROOT/tests/fixtures/ultra-transcript.jsonl" '.transcript_path = $tr' "$ROOT/tests/fixtures/ultra.json" \
                    | AGENTLINE_CONFIG=/dev/null AGENTLINE_GLYPHS=nerd AGENTLINE_COMPACT_STYLE=$cs AGENTLINE_EFFORT_STYLE=$es \
                      AGENTLINE_ULTRA_EFFECT=$ue COLUMNS=$cols bash "$ROOT/claude/statusline.sh" 2>"$TMP/err")
                max=$(printf '%s\n' "$out" | width | sort -n | tail -1)
                CHECK_NAME="styles $cs/$es/$ue @$cols: clean and fits ($max)"
                check test -z "$(cat "$TMP/err")" -a "$max" -le $((cols - 4))
            done
        done
    done
done
# A reset on another day says which one (local time); a reset today does not.
rs=$(jq --argjson n 1790000000 '.rate_limits.five_hour.resets_at = $n + 83940 | .rate_limits.seven_day.resets_at = $n + 3600' "$ROOT/tests/fixtures/session.json" \
    | TZ=UTC AGENTLINE_NOW=1790000000 AGENTLINE_CONFIG=/dev/null AGENTLINE_GLYPHS=unicode COLUMNS=200 bash "$ROOT/claude/statusline.sh" | tail -1 | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="reset tomorrow: the day and time"; check grep -q '5h ██▋ *27% ↻23h19 (Tue 13:32)' <<<"$rs"
CHECK_NAME="reset today: no day"; check grep -q '↻1h00  ' <<<"$rs"
# Narrower: the day goes first, the bar stays a bar.
rs=$(jq --argjson n 1790000000 '.rate_limits.five_hour.resets_at = $n + 83940' "$ROOT/tests/fixtures/session.json" \
    | TZ=UTC AGENTLINE_NOW=1790000000 AGENTLINE_CONFIG=/dev/null AGENTLINE_GLYPHS=unicode COLUMNS=112 bash "$ROOT/claude/statusline.sh" | tail -1 | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="reset day given up: 5h keeps its bar ($rs)"; check grep -Eq '5h ██▋ +27% ↻23h19  ' <<<"$rs"
seg=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_SEGMENTS="dir ctx" COLUMNS=160 bash "$ROOT/claude/statusline.sh" < "$ROOT/tests/fixtures/session.json" | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="segments: hidden parts are gone"; check test "$(grep -Ec 'Opus|5h|cache' <<<"$seg")" -eq 0
CHECK_NAME="segments: shown parts stay"; check grep -q 'context' <<<"$seg"

ultra=$(jq --arg tr "$ROOT/tests/fixtures/ultra-transcript.jsonl" '.transcript_path = $tr' "$ROOT/tests/fixtures/ultra.json" \
    | AGENTLINE_CONFIG=/dev/null COLUMNS=200 bash "$ROOT/claude/statusline.sh" | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="ultracode detected from the transcript"; check grep -q 'ultracode' <<<"$ultra"
# Right after "/effort ultracode" only the command output is in the transcript.
printf '%s\n' '{"type":"user","message":{"content":"<local-command-stdout>Set effort level to ultracode (this session only): xhigh + dynamic workflow orchestration</local-command-stdout>"}}' > "$TMP/effort-on.jsonl"
cmd_on=$(jq --arg tr "$TMP/effort-on.jsonl" '.session_id = "fx-cmd" | .transcript_path = $tr' "$ROOT/tests/fixtures/ultra.json" \
    | AGENTLINE_CONFIG=/dev/null COLUMNS=200 bash "$ROOT/claude/statusline.sh" | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="ultracode detected from the /effort command output"; check grep -q 'ultracode' <<<"$cmd_on"
printf '%s\n' '{"type":"user","message":{"content":"<local-command-stdout>Set effort level to xhigh</local-command-stdout>"}}' >> "$TMP/effort-on.jsonl"
cmd_off=$(jq --arg tr "$TMP/effort-on.jsonl" '.session_id = "fx-cmd" | .transcript_path = $tr' "$ROOT/tests/fixtures/ultra.json" \
    | AGENTLINE_CONFIG=/dev/null COLUMNS=200 bash "$ROOT/claude/statusline.sh" | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="plain xhigh after leaving ultracode"; check grep -q 'xhigh' <<<"$cmd_off"
CHECK_NAME="no ultracode after leaving it"; check test "$(grep -c 'ultracode' <<<"$cmd_off")" -eq 0
plain=$(AGENTLINE_CONFIG=/dev/null COLUMNS=200 bash "$ROOT/claude/statusline.sh" < "$ROOT/tests/fixtures/session.json" | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="medium effort shown without ultracode"; check grep -q 'medium' <<<"$plain"
# The daily update check, also where there is no setsid (macOS).
UP="$TMP/upd"; mkdir -p "$UP/share/agentline/current/bin" "$TMP/nosetsid"
printf '#!/bin/sh\necho "$*" > %q\n' "$TMP/update-ran" > "$UP/share/agentline/current/bin/agentline"
chmod +x "$UP/share/agentline/current/bin/agentline"
for t in cat jq git ps stty sed mkdir mv; do ln -sf "$(command -v "$t")" "$TMP/nosetsid/$t"; done
env PATH="$TMP/nosetsid" XDG_DATA_HOME="$UP/share" AGENTLINE_CONFIG=/dev/null AGENTLINE_AUTO_UPDATE=1 COLUMNS=100 \
    "$BASH" "$ROOT/claude/statusline.sh" < "$ROOT/tests/fixtures/session.json" > /dev/null 2>&1
for _ in $(seq 50); do [ -s "$TMP/update-ran" ] && break; sleep 0.1; done
CHECK_NAME="auto-update: runs without setsid"; check grep -qx 'update --quiet' "$TMP/update-ran"
CHECK_NAME="auto-update: once a day"; check test -s "$UP/share/agentline/last-update-check"
# A directory whose cache file name would pass 255 bytes: no cache, no error.
LONG="$TMP/$(printf 'a%.0s' {1..120})/$(printf 'b%.0s' {1..120})"; mkdir -p "$LONG"; git -C "$LONG" init -q -b long-path
out=$(jq --arg c "$LONG" '.cwd = $c | .workspace.current_dir = $c' "$ROOT/tests/fixtures/session.json" \
    | AGENTLINE_CONFIG=/dev/null AGENTLINE_GLYPHS=unicode COLUMNS=200 bash "$ROOT/claude/statusline.sh" 2>"$TMP/err" | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="long directory: git shown, no error"; check test ! -s "$TMP/err" -a "$(grep -c '⎇ long-path' <<<"$out")" -eq 1

# Layouts and themes.
for fx in "$ROOT"/tests/fixtures/*.json; do
    payload=$(jq --arg cwd "$REPO" --argjson n "$now" '.cwd = $cwd | .workspace.current_dir = $cwd | .transcript_path = null
        | (.prompt_cache.expires_at |= (if . then $n + . else . end)) | (.rate_limits[]?.resets_at |= $n + .)' "$fx")
    for am in "" "$(jq -c . "$ROOT/tests/fixtures/automodel/routed.json")" "$(jq -c . "$ROOT/tests/fixtures/automodel/fallback.json")"; do
        for cols in 80 90 100 120 140 160 200; do
            out=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_LAYOUT=one AGENTLINE_AUTOMODEL_JSON=$am COLUMNS=$cols \
                  bash "$ROOT/claude/statusline.sh" <<<"$payload" 2>"$TMP/err")
            max=$(printf '%s\n' "$out" | width | sort -n | tail -1)
            CHECK_NAME="layout one: $(basename "$fx") ${am:+routed }@$cols: one clean line that fits ($max)"
            check test -z "$(cat "$TMP/err")" -a "$(printf '%s\n' "$out" | wc -l)" -eq 1 -a "$max" -le $((cols - 4))
        done
    done
    for glyphs in unicode nerd; do
        for cols in 60 100 160; do
            out=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_THEME=light AGENTLINE_GLYPHS=$glyphs COLUMNS=$cols \
                  bash "$ROOT/claude/statusline.sh" <<<"$payload" 2>"$TMP/err")
            max=$(printf '%s\n' "$out" | width | sort -n | tail -1)
            CHECK_NAME="theme light: $(basename "$fx") $glyphs @$cols: two clean lines that fit ($max)"
            check test -z "$(cat "$TMP/err")" -a "$(printf '%s\n' "$out" | wc -l)" -eq 2 -a "$max" -le $((cols - 4))
        done
    done
done
light=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_THEME=light COLUMNS=160 bash "$ROOT/claude/statusline.sh" < "$ROOT/tests/fixtures/session.json")
CHECK_NAME="theme light: dark text for the model"; check grep -q $'\e\\[38;2;40;40;50mOpus' <<<"$light"
custom=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_LAYOUT='model route | dir; ctx 5h bogus | cost; nothing here' COLUMNS=160 \
    AGENTLINE_AUTOMODEL_JSON="$(jq -c . "$ROOT/tests/fixtures/automodel/routed.json")" \
    bash "$ROOT/claude/statusline.sh" < "$ROOT/tests/fixtures/session.json" 2>"$TMP/err" | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="layout custom: clean, lines without known parts skipped"
check test -z "$(cat "$TMP/err")" -a "$(printf '%s\n' "$custom" | wc -l)" -eq 2
CHECK_NAME="layout custom: parts where asked"
check grep -q '^jev → Opus 5.5.* 0.86 .*/tmp$' <<<"$(head -1 <<<"$custom")"
CHECK_NAME="layout custom: second line"; check grep -q '^context .*5h .*\$10.28 in' <<<"$(tail -1 <<<"$custom")"
CHECK_NAME="layout custom: parts left out stay out"; check test "$(grep -Ec '7d|cache|edits|Refactor' <<<"$custom")" -eq 0
three=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_LAYOUT='dir; model; ctx | cost' COLUMNS=100 bash "$ROOT/claude/statusline.sh" < "$ROOT/tests/fixtures/session.json")
CHECK_NAME="layout custom: three lines"; check test "$(printf '%s\n' "$three" | wc -l)" -eq 3
none=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_LAYOUT='bogus | nothing' COLUMNS=100 bash "$ROOT/claude/statusline.sh" < "$ROOT/tests/fixtures/session.json")
CHECK_NAME="layout custom: nothing known falls back to two lines"; check test "$(printf '%s\n' "$none" | wc -l)" -eq 2
pies=$(for u in 0 50000 300000 600000 950000; do
    jq --argjson u "$u" '.context_window.current_usage = {input_tokens: $u}' "$ROOT/tests/fixtures/session.json" \
        | AGENTLINE_CONFIG=/dev/null AGENTLINE_GLYPHS=unicode AGENTLINE_BAR=pie AGENTLINE_SEGMENTS=ctx COLUMNS=100 \
          bash "$ROOT/claude/statusline.sh" | tail -n 1 | sed 's/\x1b\[[0-9;]*m//g'
done | paste -sd'|' -)
CHECK_NAME="pie, unicode: a slice per quarter ($pies)"
check test "$pies" = "context ○ 0%|context ◔ 5%|context ◑ 30%|context ◕ 60%|context ● 95%"

# ── automodel routing ──────────────────────────────────────────────────────
echo "automodel"
# A session on automodel's custom model, with each answer of `automodel statusline --json`.
jev=$(jq --arg cwd "$REPO" --argjson n "$now" '.cwd = $cwd | .workspace.current_dir = $cwd | .model = {id: "jev", display_name: "Jev (auto)"}
    | (.prompt_cache.expires_at |= (if . then $n + . else . end)) | (.rate_limits[]?.resets_at |= $n + .)' "$ROOT/tests/fixtures/session.json")
for am in "$ROOT"/tests/fixtures/automodel/*.json; do
    amj=$(jq -c . "$am")
    for glyphs in unicode nerd; do
        for bar in capsule line; do
            for cols in 60 70 80 90 100 110 120 130 140 150 160 170 180 190 200; do
                out=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_AUTOMODEL_JSON=$amj AGENTLINE_GLYPHS=$glyphs AGENTLINE_BAR=$bar COLUMNS=$cols \
                      bash "$ROOT/claude/statusline.sh" <<<"$jev" 2>"$TMP/err")
                max=$(printf '%s\n' "$out" | width | sort -n | tail -1)
                CHECK_NAME="routed $(basename "$am") $glyphs/$bar @$cols: two clean lines that fit ($max)"
                check test -z "$(cat "$TMP/err")" -a "$(printf '%s\n' "$out" | wc -l)" -eq 2 -a "$max" -le $((cols - 4))
            done
        done
    done
done
routed() { # routed <answer> [env...] → the first line, plain text, at 200 columns
    local a; a=$(jq -c . "$ROOT/tests/fixtures/automodel/$1.json"); shift
    env AGENTLINE_CONFIG=/dev/null AGENTLINE_AUTOMODEL_JSON="$a" COLUMNS=200 "$@" bash "$ROOT/claude/statusline.sh" <<<"$jev" \
        | head -1 | sed 's/\x1b\[[0-9;]*m//g'
}
out=$(routed routed)
CHECK_NAME="routed: model and routed effort"; check grep -q 'jev → Opus 5.5 ●●●●○ xhigh  0.86 ↻ switched$' <<<"$out"
CHECK_NAME="routed: Claude Code's model and effort replaced"; check test "$(grep -Ec 'Jev \(auto\)|medium' <<<"$out")" -eq 0
CHECK_NAME="routed: pinned, issue"; check grep -q 'jev → Sonnet 5 ●●●○○ high  pinned ⚠ jev: no OpenRouter key$' <<<"$(routed pinned)"
CHECK_NAME="routed: fallback, flash"; check grep -q 'Opus 5.5 ●●○○○ medium  ⚠ fallback ⚠ jev: timeout ↻ cold$' <<<"$(routed fallback)"
CHECK_NAME="routed: default, model key, issue truncated"; check grep -q 'jev → haiku-5 ●○○○○ low  default ⚠ jev: OpenRouter key rejected…$' <<<"$(routed default)"
CHECK_NAME="routed: catalog error keeps Claude Code's model"; check grep -q 'Jev (auto) ●●○○○ medium  ⚠ catalog$' <<<"$(routed error)"
CHECK_NAME="routed: ultracode from the mode"; check grep -q 'jev → Opus 5.5 ●●●●● ultracode  0.62 ↻ compact$' <<<"$(routed ultracode)"
out=$(jq -c . "$ROOT/tests/fixtures/automodel/ultracode.json" | { read -r a; AGENTLINE_CONFIG=/dev/null AGENTLINE_AUTOMODEL_JSON=$a \
    AGENTLINE_ULTRA_EFFECT=plain COLUMNS=200 bash "$ROOT/claude/statusline.sh" <<<"$jev"; })
CHECK_NAME="routed: ultracode effect drawn"; check grep -q $'\e\\[1;38;2;175;135;255m●●●●● ultracode' <<<"$out"
out=$(routed routed AGENTLINE_SEGMENTS="dir model effort ctx")
CHECK_NAME="routed: route hidden when not in the segments"; check test "$(grep -Ec '0.86|↻' <<<"$out")" -eq 0
CHECK_NAME="routed: model still routed without the route"; check grep -q 'jev → Opus 5.5 ●●●●○ xhigh$' <<<"$out"
out=$(env AGENTLINE_CONFIG=/dev/null AGENTLINE_AUTOMODEL_JSON='{"v":1,"routed":false}' COLUMNS=200 bash "$ROOT/claude/statusline.sh" <<<"$jev" | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="not routed: Claude Code's model"; check grep -q 'Jev (auto) ●●○○○ medium$' <<<"$(head -1 <<<"$out")"
for junk in 'not json' '{"v":2,"routed":true}' '[1,2]' '{"v":1,"routed":true,"label":"x'; do
    out=$(env AGENTLINE_CONFIG=/dev/null AGENTLINE_AUTOMODEL_JSON="$junk" COLUMNS=200 bash "$ROOT/claude/statusline.sh" <<<"$jev" 2>"$TMP/err" | sed 's/\x1b\[[0-9;]*m//g')
    CHECK_NAME="garbage answer ($junk): not routed, no error"
    check test -z "$(cat "$TMP/err")" -a "$(grep -c 'Jev (auto) ●●○○○ medium$' <<<"$out")" -eq 1
done
out=$(env AGENTLINE_CONFIG=/dev/null COLUMNS=200 \
    AGENTLINE_AUTOMODEL_JSON='{"v":1,"routed":true,"alias":"jev","label":"X","effort":"high","state":"routed","confidence":1e300}' \
    bash "$ROOT/claude/statusline.sh" <<<"$jev" 2>"$TMP/err" | head -1 | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="routed: a confidence out of range is clamped, no error"
check test ! -s "$TMP/err" -a "$(grep -c 'jev → X ●●●○○ high  1.00$' <<<"$out")" -eq 1

# A fake automodel, found through the UserPromptSubmit hook of a throwaway
# settings.json; it records its arguments. kind: new, old (no --json), hang.
fake_am() {
    local d="$TMP/am-$1"; mkdir -p "$d/bin" "$d/claude"
    { printf '#!/usr/bin/env bash\nkind=%q log=%q answer=%q\n' "$1" "$d/argv" "$(jq -c . "$ROOT/tests/fixtures/automodel/routed.json")"
      cat <<'EOF'
echo "$*" >> "$log"
case " $* " in
    *" help "*)
        echo "  automodel statusline                 render the statusline segment"
        [ "$kind" = old ] || echo "  automodel statusline --json          the routing state, as JSON" ;;
    *" statusline --json "*) cat > /dev/null; [ "$kind" = hang ] && { echo $$ > "$log.pid"; exec sleep 30; }; echo "$answer" ;;
    *" statusline "*) cat > /dev/null; echo "jev → opus-5.5·xhigh 0.86" ;;
esac
EOF
    } > "$d/bin/automodel"; chmod +x "$d/bin/automodel"
    jq -n --arg c "$d/bin/automodel --config $d/config.toml hook decide" \
        '{hooks: {SessionStart: [{hooks: [{type: "command", command: "echo"}]}], UserPromptSubmit: [{hooks: [{type: "command", command: $c}]}]}}' \
        > "$d/claude/settings.json"
}
am_render() { # am_render <kind> [env...] → the first line, plain text
    local k=$1; shift
    env CLAUDE_CONFIG_DIR="$TMP/am-$k/claude" AGENTLINE_CONFIG=/dev/null COLUMNS=200 "$@" bash "$ROOT/claude/statusline.sh" <<<"$jev" 2>"$TMP/err" \
        | head -1 | sed 's/\x1b\[[0-9;]*m//g'
}
fake_am new; fake_am old; fake_am hang
out=$(am_render new)
CHECK_NAME="automodel: called with statusline --json"; check grep -qx -- "--config $TMP/am-new/config.toml statusline --json" "$TMP/am-new/argv"
CHECK_NAME="automodel: its answer is shown"; check grep -q 'jev → Opus 5.5 ●●●●○ xhigh  0.86 ↻ switched$' <<<"$out"
CHECK_NAME="automodel: no stderr"; check test ! -s "$TMP/err"
am_render new > /dev/null
CHECK_NAME="automodel: probed once, then cached"; check test "$(grep -cx help "$TMP/am-new/argv")" -eq 1
touch "$TMP/am-new/claude/settings.json"; am_render new > /dev/null
CHECK_NAME="automodel: probed again after settings.json changes"; check test "$(grep -cx help "$TMP/am-new/argv")" -eq 2
: > "$TMP/am-new/argv"
out=$(am_render new AUTOMODEL_CHAINED=1)
CHECK_NAME="automodel: not called when it chains agentline"; check test ! -s "$TMP/am-new/argv"
CHECK_NAME="automodel: chained, not routed"; check grep -q 'Jev (auto) ●●○○○ medium$' <<<"$out"
out=$(am_render new AGENTLINE_AUTOMODEL=off)
CHECK_NAME="automodel: not called when off"; check test ! -s "$TMP/am-new/argv"
out=$(am_render old)
CHECK_NAME="automodel: an old release is probed"; check grep -qx help "$TMP/am-old/argv"
CHECK_NAME="automodel: an old release is never called for its status line"; check test "$(grep -c statusline "$TMP/am-old/argv")" -eq 0
CHECK_NAME="automodel: an old release, not routed"; check grep -q 'Jev (auto) ●●○○○ medium$' <<<"$out"
t0=${EPOCHREALTIME//[.,]/}; out=$(am_render hang); t1=${EPOCHREALTIME//[.,]/}
CHECK_NAME="automodel: a hanging call gives up ($(((t1 - t0) / 1000)) ms)"; check test $((t1 - t0)) -lt 2000000
CHECK_NAME="automodel: hanging, not routed, no stderr"; check test ! -s "$TMP/err" -a "$(grep -c 'Jev (auto) ●●○○○ medium$' <<<"$out")" -eq 1
sleep 0.2
stopped() { local p; p=$(cat "$1" 2>/dev/null) && [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; }
CHECK_NAME="automodel: the hanging call is stopped"; check stopped "$TMP/am-hang/argv.pid"
mkdir -p "$TMP/am-none/claude"; echo '{"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "other hook decide"}]}]}}' > "$TMP/am-none/claude/settings.json"
out=$(am_render none)
CHECK_NAME="automodel: absent from settings.json, not routed"; check test ! -s "$TMP/err" -a "$(grep -c 'Jev (auto) ●●○○○ medium$' <<<"$out")" -eq 1
out=$(am_render missing)
CHECK_NAME="automodel: no settings.json, not routed"; check test ! -s "$TMP/err" -a "$(grep -c 'Jev (auto) ●●○○○ medium$' <<<"$out")" -eq 1
# A first probe too slow to answer (a cold start) is asked again, not cached as "old".
mkdir -p "$TMP/am-slow/claude"
{ printf '#!/usr/bin/env bash\nwarm=%q answer=%q\n' "$TMP/am-slow/warm" "$(jq -c . "$ROOT/tests/fixtures/automodel/routed.json")"
  cat <<'EOF'
case " $* " in
    *" help "*) [ -e "$warm" ] || { : > "$warm"; sleep 1.5; }; echo "  automodel statusline --json" ;;
    *" statusline --json "*) cat > /dev/null; echo "$answer" ;;
esac
EOF
} > "$TMP/am-slow/automodel"; chmod +x "$TMP/am-slow/automodel"
jq -n --arg c "$TMP/am-slow/automodel hook decide" '{hooks: {UserPromptSubmit: [{hooks: [{type: "command", command: $c}]}]}}' \
    > "$TMP/am-slow/claude/settings.json"
am_render slow > /dev/null; out=$(am_render slow)
CHECK_NAME="automodel: a slow first probe is asked again"; check grep -q 'jev → Opus 5.5 ●●●●○ xhigh' <<<"$out"

# automodel's "model" is its catalog key: the label is shown, else the name in its text.
amx='{"v":1,"routed":true,"alias":"jev","model":"claude-opus-5-5","label":"Opus 5.5","effort":"xhigh","mode":"","state":"routed","confidence":0.86,"pin":"","issue":"","flash":"","text":"jev → opus-5.5·xhigh 0.86"}'
labelled() { # labelled <jq edit of the answer> → the first line, plain text
    env AGENTLINE_CONFIG=/dev/null AGENTLINE_AUTOMODEL_JSON="$(jq -c "$1" <<<"$amx")" COLUMNS=200 bash "$ROOT/claude/statusline.sh" <<<"$jev" 2>"$TMP/err" \
        | head -1 | sed 's/\x1b\[[0-9;]*m//g'
}
out=$(labelled .)
CHECK_NAME="routed: the label, not the catalog key"; check grep -q 'jev → Opus 5.5 ●●●●○ xhigh  0.86$' <<<"$out"
out=$(labelled '.budget = "over"')
CHECK_NAME="routed: over automodel's spending cap"; check grep -q 'jev → Opus 5.5 ●●●●○ xhigh  0.86 ⚠ budget$' <<<"$out"
out=$(labelled '.effort = "low" | .claude_effort = "xhigh"')
CHECK_NAME="routed: the real effort when Claude Code shows another"; check grep -q 'jev → Opus 5.5 ●○○○○ low  not xhigh 0.86$' <<<"$out"
out=$(labelled '.label = ""')
CHECK_NAME="routed, no label: the name in its text"; check grep -q 'jev → opus-5.5 ●●●●○ xhigh  0.86$' <<<"$out"
out=$(labelled '.label = "" | .effort = "" | .state = "default" | .text = "jev → opus-5.5 (default)"')
CHECK_NAME="routed, no label nor effort: the name in its text"; check grep -q 'jev → opus-5.5  default$' <<<"$out"
out=$(labelled '.label = null | del(.text)')
CHECK_NAME="routed, no label nor text: Claude Code's model"; check grep -q 'Jev (auto) ●●○○○ medium  0.86$' <<<"$out"
CHECK_NAME="routed: the catalog key never shown, no stderr"
check test -z "$(for e in . '.label = ""' '.label = null | del(.text)'; do labelled "$e"; done | grep claude-opus)" -a ! -s "$TMP/err"

# The cache directory (some of its files are sourced) must be ours alone: in a
# shared /tmp another user can create agentline-<uid> first. A directory that
# isn't ours is simulated by a symlink (no chown here). Then nothing there is
# read or written, and the render is the same as with a private cache.
secp=$(jq -c '.effort.level = "xhigh"' <<<"$jev")   # xhigh: the ultracode cache is read too
sec_render() { # sec_render <runtime dir> → both lines, plain text
    env XDG_RUNTIME_DIR="$1" CLAUDE_CONFIG_DIR="$TMP/sec-claude" AGENTLINE_CONFIG=/dev/null AGENTLINE_NOW="$now" COLUMNS=200 \
        bash "$ROOT/claude/statusline.sh" <<<"$secp" 2>"$TMP/err" | sed 's/\x1b\[[0-9;]*m//g'
}
mode() { ls -ld "$1" | cut -c1-10; }
snap() { ls -A "$1"; cat "$1"/* 2>/dev/null; }
mkdir -p "$TMP/sec-ok"; ref=$(sec_render "$TMP/sec-ok")
CHECK_NAME="cache: created private (700, sticky)"; check test "$(mode "$TMP/sec-ok/agentline-$UID")" = "drwx-----T"
CHECK_NAME="cache: its files private"; check test "$(mode "$TMP/sec-ok/agentline-$UID/last-payload.json")" = "-rw-------"
# Files planted as another user would: each runs `touch pwned` if sourced or evaluated.
P="$TMP/sec-planted"; mkdir -p "$P"; chmod 1700 "$P"
printf 'is_git=1 head=planted staged=9 gts=%s\ntouch %q\n' "$now" "$TMP/pwned-git" > "$P/git-${REPO//\//%}"
printf '#!/bin/sh\ntouch %q\n' "$TMP/pwned-exe" > "$TMP/sec-evil"; chmod +x "$TMP/sec-evil"
sset="$TMP/sec-claude/settings.json"
printf 'am_exe=%q am_ok=1\ntouch %q\n' "$TMP/sec-evil" "$TMP/pwned-am" > "$P/automodel-${sset//\//%}"
printf 'x[$(touch %q)] on\n' "$TMP/pwned-uc" > "$P/uc-fx-session"
p0=$(snap "$P")
pwned() { ls "$TMP"/pwned-* 2>/dev/null; }
mkdir -p "$TMP/sec-a"; ln -s "$P" "$TMP/sec-a/agentline-$UID"
out=$(sec_render "$TMP/sec-a")
CHECK_NAME="cache, symlinked directory: nothing planted runs"; check test -z "$(pwned)"
CHECK_NAME="cache, symlinked directory: nothing read (same render), no stderr"; check test "$out" = "$ref" -a ! -s "$TMP/err"
CHECK_NAME="cache, symlinked directory: nothing written"; check test "$(snap "$P")" = "$p0"
mkdir -p "$TMP/sec-b"; : > "$TMP/sec-b/agentline-$UID"
out=$(sec_render "$TMP/sec-b")
CHECK_NAME="cache, a file in the way: same render, no stderr"; check test "$out" = "$ref" -a ! -s "$TMP/err" -a -f "$TMP/sec-b/agentline-$UID"
mkdir -p "$TMP/sec-c"; ln -s "$TMP/sec-c-target" "$TMP/sec-c/agentline-$UID"
out=$(sec_render "$TMP/sec-c")
CHECK_NAME="cache, dangling symlink: not followed, same render"; check test "$out" = "$ref" -a ! -s "$TMP/err" -a ! -e "$TMP/sec-c-target"
# Inside our directory, a cache file that is a symlink is not read either.
ln -sf "$P/git-${REPO//\//%}" "$TMP/sec-ok/agentline-$UID/git-${REPO//\//%}"
ln -sf "$P/uc-fx-session" "$TMP/sec-ok/agentline-$UID/uc-fx-session"
out=$(sec_render "$TMP/sec-ok")
CHECK_NAME="cache, symlinked files: not read, targets untouched"; check test "$out" = "$ref" -a -z "$(pwned)" -a "$(snap "$P")" = "$p0"
# Made by an older release: private once (kept) if only we could write in it,
# else started afresh (it may hold others' files, like a symlink to overwrite).
mkdir -p "$TMP/sec-d/agentline-$UID"; chmod 755 "$TMP/sec-d/agentline-$UID"; echo 1 > "$TMP/sec-d/agentline-$UID/kept"
out=$(sec_render "$TMP/sec-d")
CHECK_NAME="cache, from an older release: made private, kept"
check test "$(mode "$TMP/sec-d/agentline-$UID")" = "drwx-----T" -a -f "$TMP/sec-d/agentline-$UID/kept" -a "$out" = "$ref"
mkdir -p "$TMP/sec-e/agentline-$UID"; chmod 777 "$TMP/sec-e/agentline-$UID"; echo keep > "$TMP/sec-victim"
ln -s "$TMP/sec-victim" "$TMP/sec-e/agentline-$UID/last-payload.json"; cp "$P/git-${REPO//\//%}" "$TMP/sec-e/agentline-$UID/"
out=$(sec_render "$TMP/sec-e")
CHECK_NAME="cache, world-writable: started afresh, private"; check test "$(mode "$TMP/sec-e/agentline-$UID")" = "drwx-----T" -a "$out" = "$ref"
CHECK_NAME="cache, world-writable: planted symlink not followed, nothing run"
check test "$(cat "$TMP/sec-victim")" = keep -a ! -L "$TMP/sec-e/agentline-$UID/last-payload.json" -a -z "$(pwned)"

# ── Claude Code ────────────────────────────────────────────────────────────
echo "claude code"
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "model": "opus",
  "statusLine": { "type": "command", "command": "~/.claude/old-statusline.sh" },
  "permissions": { "allow": ["Bash(ls:*)"] }
}
EOF
cp "$HOME/.claude/settings.json" "$TMP/claude-orig.json"
"$ROOT/install.sh" --claude --glyphs nerd --bar capsule >/dev/null
sum1=$(cd "$HOME" && find . -type f -exec "${SHA[@]}" {} + | sort)
CHECK_NAME="claude: statusLine points to agentline"
check grep -q 'agentline/claude-statusline.sh' "$HOME/.claude/settings.json"
CHECK_NAME="claude: other settings kept"
check test "$(jq -S 'del(.statusLine)' "$HOME/.claude/settings.json")" = "$(jq -S 'del(.statusLine)' "$TMP/claude-orig.json")"
CHECK_NAME="claude: config carries the chosen options"
check grep -qx 'AGENTLINE_BAR=capsule' "$XDG_CONFIG_HOME/agentline/config"
"$ROOT/install.sh" --claude --glyphs nerd --bar capsule > "$TMP/second.txt"
sum2=$(cd "$HOME" && find . -type f -exec "${SHA[@]}" {} + | sort)
CHECK_NAME="claude: second install changes nothing"
check test "$sum1" = "$sum2"
CHECK_NAME="claude: second install reports unchanged"
check test "$(grep -c '✓' "$TMP/second.txt")" -eq 0
CHECK_NAME="claude: statusLine runs bash 5 by its absolute path"
check bash -c 'b=$(jq -r .statusLine.command "$1"); b=${b%% *}; [[ $b == /* ]] && "$b" -c "((BASH_VERSINFO[0] >= 5))"' _ "$HOME/.claude/settings.json"
# Releases before 0.5.0 ran a bare `bash` (on macOS, maybe /bin/bash 3.2): the
# next install names bash 5, and still knows the status line is agentline's.
jq --arg d "$XDG_DATA_HOME/agentline" '.statusLine.command = "bash \"" + $d + "/claude-statusline.sh\""' \
    "$HOME/.claude/settings.json" > "$TMP/s.json" && cat "$TMP/s.json" > "$HOME/.claude/settings.json"
"$ROOT/install.sh" --claude > /dev/null
CHECK_NAME="claude: a bare bash statusLine is migrated, nothing else changes"
check test "$(cd "$HOME" && find . -type f -exec "${SHA[@]}" {} + | sort)" = "$sum2"
"$ROOT/install.sh" --claude --uninstall >/dev/null
CHECK_NAME="claude: uninstall restores the previous statusLine and settings"
check test "$(jq -S . "$HOME/.claude/settings.json")" = "$(jq -S . "$TMP/claude-orig.json")"

# ── Options, config migration, automodel's status line ─────────────────────
echo "options and automodel install"
AH="$TMP/amh"; mkdir -p "$AH/home/.claude"
aenv=(env HOME="$AH/home" XDG_CONFIG_HOME="$AH/home/.config" XDG_DATA_HOME="$AH/home/.local/share" XDG_RUNTIME_DIR="$TMP/amrun")
aconf="$AH/home/.config/agentline/config" asettings="$AH/home/.claude/settings.json"
am_cmd="$TMP/am-new/bin/automodel --config $TMP/am-new/config.toml"
with_am() { # with_am <statusLine JSON or null> → settings.json with automodel's hooks
    jq -n --arg d "$am_cmd hook decide" --argjson s "$1" '{model: "opus", permissions: {allow: ["Workflow"]}}
        + (if $s then {statusLine: $s} else {} end)
        + {hooks: {UserPromptSubmit: [{hooks: [{type: "command", command: $d, timeout: 15}]}]}}' > "$asettings"
}
with_am "$(jq -cn --arg c "$am_cmd statusline" '{type: "command", command: $c}')"
cp "$asettings" "$TMP/am-orig.json"
"${aenv[@]}" "$ROOT/install.sh" --claude --yes --theme light --layout "dir git | model route; ctx 5h 7d" --automodel off > "$TMP/am-install.log" 2>&1; rc=$?
CHECK_NAME="options: exit 0"; check test $rc -eq 0
for kv in THEME=light 'LAYOUT="dir git | model route; ctx 5h 7d"' AUTOMODEL=off CONFIG_VERSION=2; do
    CHECK_NAME="options: AGENTLINE_$kv saved"; check grep -qxF "AGENTLINE_$kv" "$aconf"
done
CHECK_NAME="over automodel: agentline's statusLine"; check grep -q 'agentline/claude-statusline.sh' "$asettings"
CHECK_NAME="over automodel: automodel's statusLine kept for --uninstall"
check test "$(jq -c . "$AH/home/.local/share/agentline/claude-previous-statusline.json")" = "$(jq -c .statusLine "$TMP/am-orig.json")"
CHECK_NAME="over automodel: says agentline shows the routing"; check grep -q "agentline now shows automodel's routing itself" "$TMP/am-install.log"
CHECK_NAME="over automodel: says the routing is off"; check grep -q 'AGENTLINE_AUTOMODEL=off hides it' "$TMP/am-install.log"
: > "$TMP/am-new/argv"
out=$("${aenv[@]}" COLUMNS=160 bash "$AH/home/.local/share/agentline/claude-statusline.sh" <<<"$jev" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="options: the saved layout is used"; check test "$(printf '%s
' "$out" | wc -l)" -eq 2 -a "$(grep -Ec 'cache|edits' <<<"$out")" -eq 0
CHECK_NAME="options: automodel off, never called"; check test ! -s "$TMP/am-new/argv"
"${aenv[@]}" "$ROOT/install.sh" --claude --yes --automodel auto > /dev/null 2>&1
out=$("${aenv[@]}" COLUMNS=160 bash "$AH/home/.local/share/agentline/claude-statusline.sh" <<<"$jev" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="options: automodel auto, its routing shown"; check grep -q 'jev → Opus 5.5 ●●●●○ xhigh  0.86' <<<"$out"
sum1=$(cd "$AH/home" && find . -type f -exec "${SHA[@]}" {} + | sort)
"${aenv[@]}" "$ROOT/install.sh" --claude --yes > "$TMP/am-second.log" 2>&1
sum2=$(cd "$AH/home" && find . -type f -exec "${SHA[@]}" {} + | sort)
CHECK_NAME="over automodel: second install changes nothing"; check test "$sum1" = "$sum2"
CHECK_NAME="over automodel: second install reports unchanged, no note"; check test "$(grep -v 'in your PATH' "$TMP/am-second.log" | grep -Ec '✓|!')" -eq 0
"${aenv[@]}" "$ROOT/install.sh" --claude --uninstall > "$TMP/am-uninstall.log" 2>&1
CHECK_NAME="over automodel: uninstall gives automodel its statusLine back"
check test "$(jq -S . "$asettings")" = "$(jq -S . "$TMP/am-orig.json")"
# The other order: your status line, agentline, then automodel.
jq -n '{statusLine: {type: "command", command: "~/bin/my-line \"x\""}}' > "$asettings"
"${aenv[@]}" "$ROOT/install.sh" --claude --yes > /dev/null 2>&1
with_am "$(jq -c .statusLine "$asettings")"
"${aenv[@]}" "$ROOT/install.sh" --claude --uninstall > "$TMP/am-uninstall2.log" 2>&1
CHECK_NAME="automodel after agentline: uninstall sets automodel's statusLine, from its hook"
check test "$(jq -c .statusLine "$asettings")" = "$(jq -cn --arg c "$am_cmd statusline" '{type: "command", command: $c}')"
CHECK_NAME="automodel after agentline: says so"; check grep -q "statusLine → automodel's" "$TMP/am-uninstall2.log"
CHECK_NAME="automodel after agentline: tells how to chain your status line"
check grep -qF 'statusline_command = "~/bin/my-line \"x\""' "$TMP/am-uninstall2.log"
CHECK_NAME="automodel after agentline: names automodel's config"; check grep -qF "$TMP/am-new/config.toml" "$TMP/am-uninstall2.log"
# automodel's status line kept aside, but automodel uninstalled since: removed.
with_am "$(jq -cn --arg c "$am_cmd statusline" '{type: "command", command: $c}')"
"${aenv[@]}" "$ROOT/install.sh" --claude --yes > /dev/null 2>&1
jq 'del(.hooks)' "$asettings" > "$TMP/s.json" && mv "$TMP/s.json" "$asettings"
"${aenv[@]}" "$ROOT/install.sh" --claude --uninstall > /dev/null 2>&1
CHECK_NAME="automodel gone: its status line is not restored"; check test "$(jq -c '.statusLine // null' "$asettings")" = null
# Without automodel's hooks, uninstall restores exactly what was there.
jq -n '{statusLine: {type: "command", command: "mine"}}' > "$asettings"
"${aenv[@]}" "$ROOT/install.sh" --claude --yes > /dev/null 2>&1
"${aenv[@]}" "$ROOT/install.sh" --claude --uninstall > "$TMP/un.log" 2>&1
CHECK_NAME="no automodel: uninstall restores your status line (got $(jq -c .statusLine "$asettings"); $(tr '\n' ' ' < "$TMP/un.log"))"; check test "$(jq -c .statusLine "$asettings")" = '{"type":"command","command":"mine"}'
# Configs from before 0.5.0: a saved list of parts gets "route", once.
migrate() { # migrate "<segments line>" [install options...] → the config afterwards
    local line=$1; shift
    printf '# old\nAGENTLINE_GLYPHS=unicode\n%s\nAGENTLINE_AUTO_UPDATE=0\n' "$line" > "$aconf"
    "${aenv[@]}" "$ROOT/install.sh" --claude --yes "$@" > "$TMP/migrate.log" 2>&1
}
migrate 'AGENTLINE_SEGMENTS="dir git session meta model effort ctx 5h 7d cache cost lines"'
CHECK_NAME="migration: route after effort"; check grep -qx 'AGENTLINE_SEGMENTS="dir git session meta model effort route ctx 5h 7d cache cost lines"' "$aconf"
CHECK_NAME="migration: version 2"; check test "$(grep -cx 'AGENTLINE_CONFIG_VERSION=2' "$aconf")" -eq 1
CHECK_NAME="migration: the rest of the config kept"; check test "$(grep -Ec '^# old$|^AGENTLINE_GLYPHS=unicode$|^AGENTLINE_AUTO_UPDATE=0$' "$aconf")" -eq 3
CHECK_NAME="migration: reported"; check grep -q 'route (automodel) added' "$TMP/migrate.log"
c1=$("${SHA[@]}" < "$aconf")
"${aenv[@]}" "$ROOT/install.sh" --claude --yes > "$TMP/migrate2.log" 2>&1
CHECK_NAME="migration: once only"; check test "$c1" = "$("${SHA[@]}" < "$aconf")"
CHECK_NAME="migration: second run reports the config unchanged"; check grep -q 'config (.*(unchanged)' "$TMP/migrate2.log"
sed 's/ route//' "$aconf" > "$aconf.t" && mv "$aconf.t" "$aconf"; "${aenv[@]}" "$ROOT/install.sh" --claude --yes > /dev/null 2>&1
CHECK_NAME="migration: route removed afterwards stays removed"; check grep -qx 'AGENTLINE_SEGMENTS="dir git session meta model effort ctx 5h 7d cache cost lines"' "$aconf"
migrate 'AGENTLINE_SEGMENTS="dir model ctx"'
CHECK_NAME="migration: route after the model without effort"; check grep -qx 'AGENTLINE_SEGMENTS="dir model route ctx"' "$aconf"
migrate 'AGENTLINE_SEGMENTS=dir'
CHECK_NAME="migration: no model, no route"; check grep -qx 'AGENTLINE_SEGMENTS=dir' "$aconf"
CHECK_NAME="migration: no model, version 2"; check grep -qx 'AGENTLINE_CONFIG_VERSION=2' "$aconf"
migrate 'AGENTLINE_SEGMENTS="dir model"' --segments "dir ctx"
CHECK_NAME="migration: --segments wins"; check grep -qx 'AGENTLINE_SEGMENTS="dir ctx"' "$aconf"
migrate '# no segments'
CHECK_NAME="migration: no saved parts, nothing added"; check test "$(grep -c SEGMENTS "$aconf")" -eq 0
# The assistant shows a custom layout from the config, and keeps it.
mkdir -p "${aconf%/*}"; printf 'AGENTLINE_CONFIG_VERSION=2\nAGENTLINE_LAYOUT="dir | model"\n' > "$aconf"; printf '\n' > "$TMP/enter"
"${aenv[@]}" AGENTLINE_TTY="$TMP/enter" COLUMNS=100 "$ROOT/install.sh" --claude --configure > "$TMP/custom.log" 2>&1; rc=$?
CHECK_NAME="assistant: a custom layout from the config, shown and kept"
check test $rc -eq 0 -a "$(grep -c '^AGENTLINE_LAYOUT="dir | model"$' "$aconf")" -eq 1 -a "$(grep -c 'custom (from config): dir | model' "$TMP/custom.log")" -ge 1
for bad in "--theme blue" "--automodel on" "--layout bogus" '--layout dir$x'; do
    # shellcheck disable=SC2086  # "<flag> <value>"
    "${aenv[@]}" "$ROOT/install.sh" --claude --yes $bad > /dev/null 2>&1; rc=$?
    CHECK_NAME="options: $bad refused"; check test $rc -eq 2
done

# ── Codex ──────────────────────────────────────────────────────────────────
echo "codex"
toml_ok() { python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"; }
items() { python3 -c 'import sys, tomllib; print(",".join(tomllib.load(open(sys.argv[1], "rb")).get("tui", {}).get("status_line", [])))' "$1"; }
# Default: Codex mirrors every Claude Code part it has an item for.
expected="model-with-reasoning,current-dir,git-branch,thread-title,context-used,five-hour-limit,weekly-limit,estimated-thread-cost"
mkdir -p "$HOME/.codex"
# Case 1: a [tui] table with a multi-line status_line of the user's.
cat > "$HOME/.codex/config.toml" <<'EOF'
model = "gpt-6"

[tui]
screen_reader_detection_done = true
status_line = [
  "model-name",
  "git-branch",
]

[tui.model_availability_nux]
gpt-6-astra = 4

[projects."/home/me/code"]
trust_level = "trusted"
EOF
cp "$HOME/.codex/config.toml" "$TMP/codex-orig.toml"
"$ROOT/install.sh" --codex >/dev/null
CHECK_NAME="codex: config parses"; check toml_ok "$HOME/.codex/config.toml"
CHECK_NAME="codex: status_line = preset"; check test "$(items "$HOME/.codex/config.toml")" = "$expected"
c1=$("${SHA[@]}" < "$HOME/.codex/config.toml")
"$ROOT/install.sh" --codex >/dev/null
CHECK_NAME="codex: second install changes nothing"; check test "$c1" = "$("${SHA[@]}" < "$HOME/.codex/config.toml")"
"$ROOT/install.sh" --codex --uninstall >/dev/null
CHECK_NAME="codex: uninstall is byte-identical"; check cmp -s "$HOME/.codex/config.toml" "$TMP/codex-orig.toml"
# Case 2: no [tui] table at all.
printf 'model = "gpt-6"\n\n[projects."/x"]\ntrust_level = "trusted"\n' > "$HOME/.codex/config.toml"
cp "$HOME/.codex/config.toml" "$TMP/codex-orig2.toml"
"$ROOT/install.sh" --codex >/dev/null
CHECK_NAME="codex (no tui): config parses"; check toml_ok "$HOME/.codex/config.toml"
CHECK_NAME="codex (no tui): status_line = preset"; check test "$(items "$HOME/.codex/config.toml")" = "$expected"
"$ROOT/install.sh" --codex --uninstall >/dev/null
CHECK_NAME="codex (no tui): uninstall is byte-identical"; check cmp -s "$HOME/.codex/config.toml" "$TMP/codex-orig2.toml"

# ── curl | bash bootstrap, assistant, update, CLI ──────────────────────────
echo "bootstrap and update"
BH="$TMP/boot"; mkdir -p "$BH/home/.claude"
benv=(env HOME="$BH/home" XDG_CONFIG_HOME="$BH/home/.config" XDG_DATA_HOME="$BH/home/.local/share" XDG_RUNTIME_DIR="$TMP/run")
# A release tarball of the working tree, like codeload serves it (one top directory).
mkdir -p "$TMP/pkg/agentline-test"
cp -R "$ROOT"/{install.sh,VERSION,README.md,LICENSE,claude,codex,lib,bin} "$TMP/pkg/agentline-test/"
tar czf "$TMP/release.tar.gz" -C "$TMP/pkg" agentline-test
# Keys for the assistant: ↓ → on each setting (glyphs, theme, layout, bars,
# compact, effort, ultracode, branch, reset, updates), hide "Session name",
# then ↓ past the other parts to "automodel routing" and turn it off, Enter.
D=$'\e[B' R=$'\e[C' L=$'\e[D'
printf '%s' "$D" "$D$R" "$D$R" "$D$R" "$D$R" "$D$L" "$D$R" "$D" "$D$R" "$D$R" "$D$D$D " "$D$D$D$D$D$D$D$D$D$D$D$R" $'\n' > "$TMP/answers"
lp="$TMP/run/agentline-$UID/last-payload.json"; lp0=$(cat "$lp" 2>/dev/null)
(cd "$TMP" && "${benv[@]}" AGENTLINE_SOURCE="$TMP/release.tar.gz" AGENTLINE_TTY="$TMP/answers" COLUMNS=100 \
    bash -s -- --claude < "$ROOT/install.sh" > "$TMP/boot.log" 2>&1); rc=$?
CHECK_NAME="bootstrap: exit 0"; check test $rc -eq 0
conf="$BH/home/.config/agentline/config"
for kv in GLYPHS=nerd BAR=smooth COMPACT_STYLE=none EFFORT_STYLE=ramp ULTRA_EFFECT=plain \
          BRANCH_ICON=octicon RESET_ICON=mdi-history AUTO_UPDATE=0 THEME=light LAYOUT=one AUTOMODEL=off CONFIG_VERSION=2; do
    CHECK_NAME="assistant: $kv saved"; check grep -qx "AGENTLINE_$kv" "$conf"
done
# Unicode glyphs and back: the capsule bars come back too.
GH="$TMP/glyphs"; mkdir -p "$GH/home/.claude"
printf '%s' "$D" "$R" "$R" $'\n' > "$TMP/answers-g"
(cd "$TMP" && env HOME="$GH/home" XDG_CONFIG_HOME="$GH/home/.config" XDG_DATA_HOME="$GH/home/.local/share" XDG_RUNTIME_DIR="$TMP/run" \
    AGENTLINE_TTY="$TMP/answers-g" COLUMNS=100 "$ROOT/install.sh" --claude > /dev/null 2>&1)
CHECK_NAME="assistant: Unicode and back to Nerd keeps capsule bars"; check grep -qx 'AGENTLINE_BAR=capsule' "$GH/home/.config/agentline/config"
CHECK_NAME="assistant: session name hidden"
check grep -qx 'AGENTLINE_SEGMENTS="dir git meta model effort route ctx 5h 7d cache cost lines"' "$conf"
CHECK_NAME="assistant: preview drawn"; check grep -q 'Preview' "$TMP/boot.log"
CHECK_NAME="assistant: automodel routing previewed on its row"; check grep -q 'showing a session routed by automodel' "$TMP/boot.log"
CHECK_NAME="assistant: previews leave the last session alone"; check test "$(cat "$lp" 2>/dev/null)" = "$lp0"
CHECK_NAME="bootstrap: agentline command"; check test -x "$BH/home/.local/bin/agentline"
CHECK_NAME="bootstrap: statusLine set"; check grep -q 'agentline/claude-statusline.sh' "$BH/home/.claude/settings.json"
sumA=$(cd "$BH/home" && find . -type f -exec "${SHA[@]}" {} + | sort)
(cd "$TMP" && "${benv[@]}" AGENTLINE_SOURCE="$TMP/release.tar.gz" bash -s -- --yes < "$ROOT/install.sh" > /dev/null 2>&1)
sumB=$(cd "$BH/home" && find . -type f -exec "${SHA[@]}" {} + | sort)
CHECK_NAME="bootstrap: second curl | bash changes nothing"; check test "$sumA" = "$sumB"
# Piped, there is no script file: a claude/statusline.sh in the current
# directory (dotfiles) is not agentline's, the release is installed.
mkdir -p "$TMP/dotfiles/claude"; echo 'echo not-agentline' > "$TMP/dotfiles/claude/statusline.sh"
(cd "$TMP/dotfiles" && "${benv[@]}" AGENTLINE_SOURCE="$TMP/release.tar.gz" bash -s -- --yes < "$ROOT/install.sh" > /dev/null 2>&1)
CHECK_NAME="bootstrap: piped in a directory with a claude/statusline.sh, the release is installed"
check cmp -s "$BH/home/.local/share/agentline/claude-statusline.sh" "$ROOT/claude/statusline.sh"
out=$("${benv[@]}" AGENTLINE_SOURCE="$TMP/release.tar.gz" "$BH/home/.local/bin/agentline" update 2>&1)
CHECK_NAME="update: same version is up to date"; check grep -q 'up to date' <<<"$out"
echo 9.9.9 > "$TMP/pkg/agentline-test/VERSION"; tar czf "$TMP/release2.tar.gz" -C "$TMP/pkg" agentline-test
"${benv[@]}" AGENTLINE_SOURCE="$TMP/release2.tar.gz" "$BH/home/.local/bin/agentline" update --quiet > "$TMP/upd.log" 2>&1
CHECK_NAME="update: new version installed"; check test "$(cat "$BH/home/.local/share/agentline/current/VERSION")" = 9.9.9
CHECK_NAME="update: --quiet prints nothing"; check test ! -s "$TMP/upd.log"
CHECK_NAME="update: configuration kept"; check grep -qx 'AGENTLINE_RESET_ICON=mdi-history' "$conf"
# The latest release: the tag github.com/<repo>/releases/latest redirects to,
# else the API's; never the main branch. A fake curl plays GitHub and logs the URLs.
mkdir -p "$TMP/fakegh"
cat > "$TMP/fakegh/curl" <<'EOF'
#!/usr/bin/env bash
url=${*: -1}; echo "$url" >> "$FAKE_LOG"
case $url in
    https://api.github.com/*) [ -n "$FAKE_API" ] || exit 22; printf '{\n  "url": "x",\n  "tag_name": "%s",\n  "name": "y"\n}\n' "$FAKE_API" ;;
    */releases/latest) [ -n "$FAKE_REDIRECT" ] || exit 22; printf '%s' "$FAKE_REDIRECT" ;;
    https://codeload.github.com/*) cat "$FAKE_TARBALL" ;;
    *) exit 6 ;;
esac
EOF
chmod +x "$TMP/fakegh/curl"
echo 9.9.10 > "$TMP/pkg/agentline-test/VERSION"; tar czf "$TMP/release3.tar.gz" -C "$TMP/pkg" agentline-test
gh_update() { # gh_update <redirect> <API tag> [env...]: agentline update against the fake GitHub
    local r=$1 a=$2; shift 2; : > "$TMP/gh.log"
    "${benv[@]}" PATH="$TMP/fakegh:$PATH" AGENTLINE_REPO=me/agentline FAKE_LOG="$TMP/gh.log" FAKE_REDIRECT="$r" FAKE_API="$a" \
        FAKE_TARBALL="$TMP/release3.tar.gz" "$@" "$BH/home/.local/bin/agentline" update --quiet > "$TMP/gh.out" 2>&1
}
cl=https://codeload.github.com/me/agentline/tar.gz
gh_update "" ""; rc=$?
CHECK_NAME="update: no release found, fails and says so"; check test $rc -ne 0 -a "$(grep -c 'no release found' "$TMP/gh.out")" -eq 1
CHECK_NAME="update: no release found, nothing downloaded"; check test "$(grep -c codeload "$TMP/gh.log")" -eq 0
gh_update https://github.com/me/agentline/releases main; rc=$?
CHECK_NAME="update: no tag, main refused"; check test $rc -ne 0 -a "$(grep -c codeload "$TMP/gh.log")" -eq 0
CHECK_NAME="update: no release, still installed"; check test "$(cat "$BH/home/.local/share/agentline/current/VERSION")" = 9.9.9
gh_update https://github.com/me/agentline/releases/tag/v9.9.10 ""
CHECK_NAME="update: the tag releases/latest redirects to"; check grep -qx "$cl/v9.9.10" "$TMP/gh.log"
CHECK_NAME="update: that release installed"; check test "$(cat "$BH/home/.local/share/agentline/current/VERSION")" = 9.9.10
gh_update https://github.com/me/agentline/releases/tag/v9.9.10 ""
CHECK_NAME="update: already on the latest release, nothing downloaded"; check test "$(grep -c codeload "$TMP/gh.log")" -eq 0
gh_update "" v9.9.11
CHECK_NAME="update: the API's tag when the redirect fails"; check grep -qx "$cl/v9.9.11" "$TMP/gh.log"
gh_update "" "" AGENTLINE_REF=v9.9.12
CHECK_NAME="update: AGENTLINE_REF, asked for directly"; check test "$(cat "$TMP/gh.log")" = "$cl/v9.9.12"
# Release tarballs (.gitattributes export-ignore) hold what the installer copies,
# not the demo, tools, tests or CI.
if git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
    files=$(git -C "$ROOT" archive --worktree-attributes HEAD | tar t)
    for f in install.sh VERSION README.md LICENSE claude/statusline.sh codex/preset lib/wizard.sh lib/sample.json bin/agentline; do
        CHECK_NAME="release tarball: $f"; check grep -qx "$f" <<<"$files"
    done
    CHECK_NAME="release tarball: no demo, tools, tests or CI"; check test "$(grep -Ec '^docs/demo.gif$|^tools/|^tests/|^\.github/' <<<"$files")" -eq 0
fi
"${benv[@]}" "$BH/home/.local/bin/agentline" uninstall > /dev/null 2>&1
CHECK_NAME="uninstall: command removed"; check test ! -e "$BH/home/.local/bin/agentline"
CHECK_NAME="uninstall: statusLine removed"; check test "$(jq -c '.statusLine // null' "$BH/home/.claude/settings.json")" = null

# ── Defaults without a Nerd Font, Codex mirroring ──────────────────────────
echo "defaults and mirroring"
NH="$TMP/nonerd"; mkdir -p "$NH/home/.claude" "$NH/home/.codex"
nenv=(env HOME="$NH/home" XDG_CONFIG_HOME="$NH/home/.config" XDG_DATA_HOME="$NH/home/.local/share" XDG_RUNTIME_DIR="$TMP/run")
"${nenv[@]}" AGENTLINE_ASSUME_NERD=0 "$ROOT/install.sh" --yes --claude --codex > /dev/null 2>&1
CHECK_NAME="no Nerd Font: Unicode glyphs by default"; check grep -qx 'AGENTLINE_GLYPHS=unicode' "$NH/home/.config/agentline/config"
CHECK_NAME="no Nerd Font: smooth bars by default"; check grep -qx 'AGENTLINE_BAR=smooth' "$NH/home/.config/agentline/config"
"${nenv[@]}" "$ROOT/install.sh" --yes --claude --codex --segments "dir ctx 7d" > /dev/null 2>&1
CHECK_NAME="mirror: Codex follows the Claude Code parts"
check test "$(items "$NH/home/.codex/config.toml")" = "current-dir,context-used,weekly-limit"
"${nenv[@]}" "$ROOT/install.sh" --yes --codex --codex-mirror off > /dev/null 2>&1
CHECK_NAME="mirror off: preset items"
check test "$(items "$NH/home/.codex/config.toml")" = "$(grep -Ev '^[[:space:]]*(#|$)' "$ROOT/codex/preset" | paste -sd, -)"

echo "$pass passed, $fail failed"
exit $((fail > 0))
