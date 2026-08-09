#!/usr/bin/env bash
# Tests for `slacube <cmd> help` on the three new data-mgmt commands.
#
# The bin/slacube `cmd_<name>` wrappers each have a `help)` arm that
# `show_help`s help/<name>. Missing help files would die() at the
# bin/slacube top level (exit 1, "No help for command"), so the
# presence of the help pages is itself the contract. Each test sets
# $SLACUBE_HELP_DIR to the repo's help/ dir and runs the command in
# a child shell with a no-pager override.

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/.." && pwd)

export PATH="$REPO_ROOT/bin:$PATH"
export SLACUBE_HELP_DIR="$REPO_ROOT/help"
export SLACUBE_PAGER=cat

_failures=0

check() {
  local cond=$1
  local msg=$2
  if [[ "$cond" == "1" ]]; then
    echo "  PASS: $msg"
  else
    echo "  FAIL: $msg"
    _failures=$((_failures + 1))
  fi
}


echo "============================================================"
echo "test_slacube_help"
echo "============================================================"

# ---------------------------------------------------------- fsck help
echo
echo "[slacube fsck help]"
out=$(slacube fsck help 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "fsck help: exit 0"
echo "$out" | head -1 | grep -q 'NAME' && check 1 "fsck help: starts with NAME section" || check 0 "fsck help: starts with NAME section"
echo "$out" | grep -q 'slacube fsck' && check 1 "fsck help: identifies command" || check 0 "fsck help: identifies command"
echo "$out" | grep -q 'SLACUBE_DROPBOX' && check 1 "fsck help: documents SLACUBE_DROPBOX" || check 0 "fsck help: documents SLACUBE_DROPBOX"


# ---------------------------------------------------------- reap help
echo
echo "[slacube reap help]"
out=$(slacube reap help 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "reap help: exit 0"
echo "$out" | head -1 | grep -q 'NAME' && check 1 "reap help: starts with NAME section" || check 0 "reap help: starts with NAME section"
echo "$out" | grep -q 'slacube reap' && check 1 "reap help: identifies command" || check 0 "reap help: identifies command"
echo "$out" | grep -q 'SLACUBE_RAW_CACHE' && check 1 "reap help: documents SLACUBE_RAW_CACHE" || check 0 "reap help: documents SLACUBE_RAW_CACHE"
echo "$out" | grep -q 'SLACUBE_RAW_CACHE_LOW' && check 1 "reap help: documents SLACUBE_RAW_CACHE_LOW" || check 0 "reap help: documents SLACUBE_RAW_CACHE_LOW"


# ---------------------------------------------------------- stage help (regression)
echo
echo "[slacube stage help (regression)]"
out=$(slacube stage help 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "stage help: exit 0"
echo "$out" | grep -q 'slacube stage' && check 1 "stage help: identifies command" || check 0 "stage help: identifies command"


# ---------------------------------------------------------- result
echo
echo "============================================================"
if [[ "$_failures" -ne 0 ]]; then
  echo "FAILED ($_failures)"
  exit 1
fi
echo "ALL PASSED"
exit 0
