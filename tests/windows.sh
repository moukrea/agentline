#!/usr/bin/env bash
# Windows smoke test (Git Bash), after install.ps1 ran with AGENTLINE_SOURCE:
# the installed status line renders, a second install changes nothing, and
# uninstall restores settings.json. The full suite runs on Linux and macOS.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fail=0 pass=0
check() { if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $CHECK_NAME"; fi; }
S="$HOME/.claude/settings.json"

cmd=$(jq -r '.statusLine.command' "$S"); echo "statusLine: $cmd"
CHECK_NAME="statusLine runs Git's bash.exe on the installed script, as C:/ paths"
check grep -Eq '^"[A-Za-z]:/.*/bin/bash\.exe" "[A-Za-z]:/.*/agentline/claude-statusline\.sh"$' <<<"$cmd"
CHECK_NAME="agentline command"; check test -x "$HOME/.local/bin/agentline"
CHECK_NAME="agentline version"; check test "$("$HOME/.local/bin/agentline" version)" = "$(cat "$ROOT/VERSION")"

payload=$(jq --arg d "$ROOT" '.cwd = $d | .workspace.current_dir = $d' "$ROOT/tests/fixtures/session.json")
for cols in "" 80 160; do
    # Run it the way Claude Code does: the command line, through a shell.
    out=$(COLUMNS=$cols bash -c "$cmd" <<<"$payload" 2>"$ROOT/.err"); rc=$?
    CHECK_NAME="render @${cols:-auto}: exit 0 and no stderr ($(head -c 300 "$ROOT/.err"))"; check test $rc -eq 0 -a ! -s "$ROOT/.err"
    CHECK_NAME="render @${cols:-auto}: two lines"; check test "$(printf '%s\n' "$out" | wc -l)" -eq 2
    printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g'
done
CHECK_NAME="render: the model shown"; check grep -q 'Opus' <<<"$out"

before=$(cat "$S")
AGENTLINE_SOURCE=$(cygpath -w "$ROOT") powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ROOT/install.ps1")" > /dev/null
CHECK_NAME="second install: settings.json unchanged"; check test "$(cat "$S")" = "$before"
"$HOME/.local/bin/agentline" uninstall > /dev/null
CHECK_NAME="uninstall: previous statusLine restored"; check test "$(jq -c '.statusLine' "$S")" = '{"type":"command","command":"echo mine"}'
CHECK_NAME="uninstall: command removed"; check test ! -e "$HOME/.local/bin/agentline"
echo "$pass passed, $fail failed"
exit $((fail > 0))
