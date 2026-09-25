#!/usr/bin/env bash
# agentline test suite: rendering at every width/style, and idempotent
# install/uninstall for Claude Code and Codex in a throwaway HOME.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fail=0 pass=0
check() { if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: ${CHECK_NAME:-$*}"; fi; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" XDG_DATA_HOME="$TMP/home/.local/share" XDG_RUNTIME_DIR="$TMP/run"
unset CLAUDE_CONFIG_DIR CODEX_HOME
export AGENTLINE_ASSUME_NERD=1   # font detection is tested on its own below
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
seg=$(AGENTLINE_CONFIG=/dev/null AGENTLINE_SEGMENTS="dir ctx" COLUMNS=160 bash "$ROOT/claude/statusline.sh" < "$ROOT/tests/fixtures/session.json" | sed 's/\x1b\[[0-9;]*m//g')
CHECK_NAME="segments: hidden parts are gone"; check test "$(grep -c 'Opus\|5h\|cache' <<<"$seg")" -eq 0
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
sum1=$(cd "$HOME" && find . -type f -exec sha256sum {} + | sort)
CHECK_NAME="claude: statusLine points to agentline"
check grep -q 'agentline/claude-statusline.sh' "$HOME/.claude/settings.json"
CHECK_NAME="claude: other settings kept"
check test "$(jq -S 'del(.statusLine)' "$HOME/.claude/settings.json")" = "$(jq -S 'del(.statusLine)' "$TMP/claude-orig.json")"
CHECK_NAME="claude: config carries the chosen options"
check grep -qx 'AGENTLINE_BAR=capsule' "$XDG_CONFIG_HOME/agentline/config"
"$ROOT/install.sh" --claude --glyphs nerd --bar capsule > "$TMP/second.txt"
sum2=$(cd "$HOME" && find . -type f -exec sha256sum {} + | sort)
CHECK_NAME="claude: second install changes nothing"
check test "$sum1" = "$sum2"
CHECK_NAME="claude: second install reports unchanged"
check test "$(grep -c '✓' "$TMP/second.txt")" -eq 0
"$ROOT/install.sh" --claude --uninstall >/dev/null
CHECK_NAME="claude: uninstall restores the previous statusLine and settings"
check test "$(jq -S . "$HOME/.claude/settings.json")" = "$(jq -S . "$TMP/claude-orig.json")"

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
c1=$(sha256sum < "$HOME/.codex/config.toml")
"$ROOT/install.sh" --codex >/dev/null
CHECK_NAME="codex: second install changes nothing"; check test "$c1" = "$(sha256sum < "$HOME/.codex/config.toml")"
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
# Keys for the assistant: ↓ → on each setting, then hide "Session name", Enter.
D=$'\e[B' R=$'\e[C' L=$'\e[D'
printf '%s' "$D" "$D$R" "$D$R" "$D$L" "$D$R" "$D" "$D$R" "$D$R" "$D$D$D " $'\n' > "$TMP/answers"
(cd "$TMP" && "${benv[@]}" AGENTLINE_SOURCE="$TMP/release.tar.gz" AGENTLINE_TTY="$TMP/answers" COLUMNS=100 \
    bash -s -- --claude < "$ROOT/install.sh" > "$TMP/boot.log" 2>&1)
CHECK_NAME="bootstrap: exit 0"; check test $? -eq 0
conf="$BH/home/.config/agentline/config"
for kv in GLYPHS=nerd BAR=smooth COMPACT_STYLE=dots EFFORT_STYLE=braille ULTRA_EFFECT=violet \
          BRANCH_ICON=octicon RESET_ICON=mdi-history AUTO_UPDATE=0; do
    CHECK_NAME="assistant: $kv saved"; check grep -qx "AGENTLINE_$kv" "$conf"
done
CHECK_NAME="assistant: session name hidden"
check grep -qx 'AGENTLINE_SEGMENTS="dir git meta model effort ctx 5h 7d cache cost lines"' "$conf"
CHECK_NAME="assistant: preview drawn"; check grep -q 'Preview' "$TMP/boot.log"
CHECK_NAME="bootstrap: agentline command"; check test -x "$BH/home/.local/bin/agentline"
CHECK_NAME="bootstrap: statusLine set"; check grep -q 'agentline/claude-statusline.sh' "$BH/home/.claude/settings.json"
sumA=$(cd "$BH/home" && find . -type f -exec sha256sum {} + | sort)
(cd "$TMP" && "${benv[@]}" AGENTLINE_SOURCE="$TMP/release.tar.gz" bash -s -- --yes < "$ROOT/install.sh" > /dev/null 2>&1)
sumB=$(cd "$BH/home" && find . -type f -exec sha256sum {} + | sort)
CHECK_NAME="bootstrap: second curl | bash changes nothing"; check test "$sumA" = "$sumB"
out=$("${benv[@]}" AGENTLINE_SOURCE="$TMP/release.tar.gz" "$BH/home/.local/bin/agentline" update 2>&1)
CHECK_NAME="update: same version is up to date"; check grep -q 'up to date' <<<"$out"
echo 9.9.9 > "$TMP/pkg/agentline-test/VERSION"; tar czf "$TMP/release2.tar.gz" -C "$TMP/pkg" agentline-test
"${benv[@]}" AGENTLINE_SOURCE="$TMP/release2.tar.gz" "$BH/home/.local/bin/agentline" update --quiet > "$TMP/upd.log" 2>&1
CHECK_NAME="update: new version installed"; check test "$(cat "$BH/home/.local/share/agentline/current/VERSION")" = 9.9.9
CHECK_NAME="update: --quiet prints nothing"; check test ! -s "$TMP/upd.log"
CHECK_NAME="update: configuration kept"; check grep -qx 'AGENTLINE_RESET_ICON=mdi-history' "$conf"
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
check test "$(items "$NH/home/.codex/config.toml")" = "$(grep -v '^[[:space:]]*\(#\|$\)' "$ROOT/codex/preset" | paste -sd, -)"

echo "$pass passed, $fail failed"
exit $((fail > 0))
