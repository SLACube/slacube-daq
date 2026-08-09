#!/usr/bin/env bash
# Tests for bin/slacube-stage.
#
# Standalone bash test harness (no project test runner exists). Seeds a
# synthetic dropbox + pool layout and exercises the script end-to-end.
# exit 0 on success, non-zero otherwise.
#
# Run as:
#     bash tests/test_slacube_stage.sh

HERE=$(cd "$(dirname "$0")" && pwd)
BIN_DIR=$(cd "$HERE/../bin" && pwd)

export PATH="$BIN_DIR:$PATH"

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


# Build a per-test tempdir with $DROPBOX and $POOL_ROOT. Echoes
# newline-separated "key=path" pairs the caller can `eval` into local
# vars. The pool root is derived per the spec:
#   POOL=$(dirname "$DROPBOX")/pool
make_fixture() {
  local root
  root=$(mktemp -d /tmp/slacube_stage_test_XXXXXX)
  local dropbox="$root/data/dropbox"
  local pool="$root/data/pool"
  mkdir -p "$dropbox" "$pool"
  cat <<FIXTURE
ROOT=$root
DROPBOX=$dropbox
POOL=$pool
FIXTURE
}


# Touch a file at <path> with a given mtime offset (seconds before now).
backdate() {
  local path="$1"
  local seconds_ago="$2"
  touch -d "@$(( $(date +%s) - seconds_ago ))" "$path"
}


echo "============================================================"
echo "test_slacube_stage"
echo "============================================================"


# ---------------------------------------------------------- normal stage
echo
echo "[normal: classifiable file moves from dropbox to pool/<type>/<year>/<date>/]"
eval "$(make_fixture)"
touch "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5"
backdate "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5" 120
SLACUBE_DROPBOX="$DROPBOX" slacube-stage
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "stage: exit 0"
check $([[ ! -f "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5" ]] && echo 1 || echo 0) \
  "stage: file removed from dropbox"
target="$POOL/selftrigger/2026/2026-02-21/selftrigger_2026_02_21_21_52_18.h5"
check $([[ -f "$target" ]] && echo 1 || echo 0) "stage: file in pool/selftrigger/2026/2026-02-21/"
rm -rf "$ROOT"


# ---------------------------------------------------------- too-fresh file stays put
echo
echo "[too-fresh: file with mtime < 60s stays in dropbox]"
eval "$(make_fixture)"
touch "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5"
# mtime is "now" -- well under 60s old
SLACUBE_DROPBOX="$DROPBOX" slacube-stage
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "too-fresh: exit 0"
check $([[ -f "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5" ]] && echo 1 || echo 0) \
  "too-fresh: file still in dropbox"
check $([[ ! -d "$POOL/selftrigger" ]] && echo 1 || echo 0) \
  "too-fresh: no pool directory created"
rm -rf "$ROOT"


# ---------------------------------------------------------- mixed: fresh + old + unclassifiable
echo
echo "[mixed: too-fresh stays, classifiable moves, unclassifiable -> non-zero]"
eval "$(make_fixture)"
# Classifiable, old enough
touch "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5"
backdate "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5" 120
# Classifiable but too fresh (stays)
touch "$DROPBOX/pedestal_2026_02_21_21_52_19.h5"
# Unclassifiable (old enough to attempt)
touch "$DROPBOX/garbage_2026_02_21_21_52_20.h5"
backdate "$DROPBOX/garbage_2026_02_21_21_52_20.h5" 120

stderr=$(SLACUBE_DROPBOX="$DROPBOX" slacube-stage 2>&1 >/dev/null)
rc=$?
check $([[ $rc -ne 0 ]] && echo 1 || echo 0) "mixed: non-zero exit on unclassifiable"
check $([[ -f "$DROPBOX/pedestal_2026_02_21_21_52_19.h5" ]] && echo 1 || echo 0) \
  "mixed: too-fresh classifiable stays in dropbox"
check $([[ -f "$DROPBOX/garbage_2026_02_21_21_52_20.h5" ]] && echo 1 || echo 0) \
  "mixed: unclassifiable stays in dropbox (no rename attempted)"
check $([[ -f "$POOL/selftrigger/2026/2026-02-21/selftrigger_2026_02_21_21_52_18.h5" ]] && echo 1 || echo 0) \
  "mixed: classifiable+old moved to pool"
echo "$stderr" | grep -q 'garbage_2026_02_21_21_52_20' && check 1 "mixed: stderr names unclassifiable file" || check 0 "mixed: stderr names unclassifiable file"
echo "$stderr" | grep -q 'pool//' && check 0 "mixed: stderr does NOT contain pool// path" || check 1 "mixed: stderr does NOT contain pool// path (empty-type bug)"
rm -rf "$ROOT"


# ---------------------------------------------------------- multiple types in one run
echo
echo "[multiple types: selftrigger + pedestal + exttrig all stage correctly]"
eval "$(make_fixture)"
touch "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5"
touch "$DROPBOX/pedestal_2026_02_21_21_52_19.h5"
touch "$DROPBOX/exttrig_2026_02_21_21_52_20.h5"
backdate "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5" 120
backdate "$DROPBOX/pedestal_2026_02_21_21_52_19.h5" 120
backdate "$DROPBOX/exttrig_2026_02_21_21_52_20.h5" 120
SLACUBE_DROPBOX="$DROPBOX" slacube-stage
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "multi: exit 0"
check $([[ -f "$POOL/selftrigger/2026/2026-02-21/selftrigger_2026_02_21_21_52_18.h5" ]] && echo 1 || echo 0) "multi: selftrigger staged"
check $([[ -f "$POOL/pedestal/2026/2026-02-21/pedestal_2026_02_21_21_52_19.h5" ]] && echo 1 || echo 0) "multi: pedestal staged"
check $([[ -f "$POOL/exttrig/2026/2026-02-21/exttrig_2026_02_21_21_52_20.h5" ]] && echo 1 || echo 0) "multi: exttrig staged"
rm -rf "$ROOT"


# ---------------------------------------------------------- skip dotfiles / .part / non-.h5
echo
echo "[skips: dotfiles, .part, .tmp, and non-.h5 names are left alone]"
eval "$(make_fixture)"
touch "$DROPBOX/.hidden_2026_02_21_21_52_18.h5"
backdate "$DROPBOX/.hidden_2026_02_21_21_52_18.h5" 120
touch "$DROPBOX/.selftrigger_2026_02_21_21_52_18.h5.part"
backdate "$DROPBOX/.selftrigger_2026_02_21_21_52_18.h5.part" 120
touch "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5.tmp"
backdate "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5.tmp" 120
touch "$DROPBOX/not_an_h5.txt"
backdate "$DROPBOX/not_an_h5.txt" 120
# Plus one valid to confirm stage still runs.
touch "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5"
backdate "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5" 120

SLACUBE_DROPBOX="$DROPBOX" slacube-stage
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "skips: exit 0"
check $([[ -f "$DROPBOX/.hidden_2026_02_21_21_52_18.h5" ]] && echo 1 || echo 0) "skips: dotfile left"
check $([[ -f "$DROPBOX/.selftrigger_2026_02_21_21_52_18.h5.part" ]] && echo 1 || echo 0) "skips: .part left"
check $([[ -f "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5.tmp" ]] && echo 1 || echo 0) "skips: .tmp left"
check $([[ -f "$DROPBOX/not_an_h5.txt" ]] && echo 1 || echo 0) "skips: non-.h5 left"
check $([[ -f "$POOL/selftrigger/2026/2026-02-21/selftrigger_2026_02_21_21_52_18.h5" ]] && echo 1 || echo 0) "skips: valid file still staged"
rm -rf "$ROOT"


# ---------------------------------------------------------- exit 2 if $SLACUBE_DROPBOX unset
echo
echo "[config: missing \$SLACUBE_DROPBOX exits non-zero]"
out=$(unset SLACUBE_DROPBOX; slacube-stage 2>&1)
rc=$?
check $([[ $rc -ne 0 ]] && echo 1 || echo 0) "config: unset SLACUBE_DROPBOX -> non-zero"
echo "$out" | grep -qi 'SLACUBE_DROPBOX' && check 1 "config: error mentions SLACUBE_DROPBOX" || check 0 "config: error mentions SLACUBE_DROPBOX"


# ---------------------------------------------------------- result
echo
echo "============================================================"
if [[ "$_failures" -ne 0 ]]; then
  echo "FAILED ($_failures)"
  exit 1
fi
echo "ALL PASSED"
exit 0
