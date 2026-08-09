#!/usr/bin/env bash
# Tests for guard_acquisition (bin/slacube).
#
# Standalone bash test harness (no project test runner exists). Sources
# bin/slacube to pick up the function under test, then exercises each of
# the six rules with synthetic spool + df fixtures. exit 0 on success,
# non-zero otherwise. Mirrors the convention of test_slacube_convertd.py.
#
# Run as:
#     bash tests/test_guard_acquisition.sh
#
# The function being tested is shell-only; we source bin/slacube once
# per test process and call guard_acquisition directly. A PATH-shadowing
# fake `df` provides controlled free-space bytes; a per-test tempdir is
# used as $SLACUBE_SPOOL against the real slacube-convertd. The function
# itself reads $SLACUBE_WORKDIR, $SLACUBE_DROPBOX, and the SLACUBE_*
# guardrail vars from the environment.

HERE=$(cd "$(dirname "$0")" && pwd)
BIN_DIR=$(cd "$HERE/../bin" && pwd)

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

# Usage: assert "test_condition" "msg"
assert() {
  local test_expr=$1
  local msg=$2
  if eval "[[ $test_expr ]]"; then
    check 1 "$msg"
  else
    check 0 "$msg"
  fi
}

# Put bin/ on PATH so guard_acquisition can call slacube-convertd.
export SLACUBE_HELP_DIR="$HERE/../help"
export SLACUBE_PAGER=cat
export PATH="$BIN_DIR:$PATH"

# Source bin/slacube once. The bottom of the file runs a case "$1" that
# falls through to show_version when sourced with no args; discard
# stdout/stderr to keep test output clean.
source "$BIN_DIR/slacube" >/dev/null 2>&1
if ! declare -f guard_acquisition >/dev/null; then
  echo "ERROR: guard_acquisition is not defined after sourcing bin/slacube"
  exit 2
fi


# Build a per-test tempdir with $SLACUBE_SPOOL/{incoming,running,failed,done}
# and a writable workdir + dropbox. Echoes a newline-separated list of
# "key=path" pairs the caller can `eval` into local vars.
make_fixture() {
  local root
  root=$(mktemp -d /tmp/slacube_guard_test_XXXXXX)
  local spool="$root/spool"
  local workdir="$root/work"
  local dropbox="$root/dropbox"
  for sub in incoming running failed done; do
    mkdir -p "$spool/$sub"
  done
  mkdir -p "$workdir" "$dropbox"
  cat <<FIXTURE
ROOT=$root
SPOOL=$spool
WORKDIR=$workdir
DROPBOX=$dropbox
FIXTURE
}

# Write a fake df that prints the given bytes for each path pattern.
# df --output=avail -B1 <path> passes --output=avail -B1 <path> as argv,
# so the first non-flag arg is the path.
write_fake_df() {
  local path="$1"
  local workdir_pat="$2"
  local dropbox_pat="$3"
  local bytes_work="$4"
  local bytes_drop="$5"
  local fail_work="${6:-0}"
  local fail_drop="${7:-0}"
  cat > "$path" <<DF
#!/usr/bin/env bash
path=""
for arg in "\$@"; do
  case "\$arg" in
    --output=*) ;;
    -B*) ;;
    -*) ;;
    *) path="\$arg"; break ;;
  esac
done
case "\$path" in
  ${workdir_pat}*)
    if [[ "${fail_work}" == "1" ]]; then exit 1; fi
    printf '%s\n' "${bytes_work}"
    exit 0
    ;;
  ${dropbox_pat}*)
    if [[ "${fail_drop}" == "1" ]]; then exit 1; fi
    printf '%s\n' "${bytes_drop}"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
DF
  chmod +x "$path"
}

# Build a PATH-shadowing dir with a fake `df`. Bytes default to 1 TiB
# each, which clears the default MIN_FREE (25 GiB) and MIN_FREE_DROPBOX
# (50 GiB). Args 5+6 set fail_work/fail_drop (0 or 1).
make_fake_df() {
  local workdir="$1"
  local dropbox="$2"
  local bytes_work="${3:-1099511627776}"
  local bytes_drop="${4:-1099511627776}"
  local fail_work="${5:-0}"
  local fail_drop="${6:-0}"
  local dir
  dir=$(mktemp -d /tmp/slacube_fake_df_XXXXXX)
  write_fake_df "$dir/df" "$workdir" "$dropbox" "$bytes_work" "$bytes_drop" "$fail_work" "$fail_drop"
  echo "$dir"
}

# Mutate the fake df's reported bytes (atomic rewrite).
set_fake_df_bytes() {
  local fake_df_dir="$1"
  local workdir="$2"
  local dropbox="$3"
  local bytes_work="$4"
  local bytes_drop="$5"
  write_fake_df "$fake_df_dir/df" "$workdir" "$dropbox" "$bytes_work" "$bytes_drop"
}

# Seed n records into $SLACUBE_SPOOL/incoming/ as valid JSON.
seed_incoming() {
  local spool="$1"
  local n="$2"
  local i
  for ((i=0; i<n; i++)); do
    cat > "$spool/incoming/raw_2026_02_21_21_52_$(printf '%02d' "$i").json" <<JSON
{"raw": "/scratch/slacube/work/${USER}/raw_2026_02_21_21_52_${i}.h5", "submitted": "2026-02-21T21:52:${i}", "attempts": 0, "not_before": null, "last_error": null, "pid": null, "started": null, "finished": null, "duration_s": null, "out": "/data/slacube/dropbox/selftrigger_2026_02_21_21_52_${i}.h5"}
JSON
  done
}

# Seed n records into $SLACUBE_SPOOL/failed/ as valid JSON. The "finished"
# timestamps are what compute_status uses to count consecutive failures.
seed_failed() {
  local spool="$1"
  local n="$2"
  local i
  for ((i=0; i<n; i++)); do
    cat > "$spool/failed/raw_fail_${i}.json" <<JSON
{"raw": "/scratch/slacube/work/${USER}/raw_fail_${i}.h5", "submitted": "2026-02-21T00:00:0${i}", "attempts": 3, "not_before": null, "last_error": "boom", "pid": null, "started": "2026-02-21T00:00:0${i}", "finished": "2026-02-21T00:01:0${i}", "duration_s": 1.0, "out": null}
JSON
  done
}

# Seed one completed record with a chosen finished timestamp.
seed_done() {
  local spool="$1"
  local name="$2"
  local finished="$3"
  cat > "$spool/done/${name}.json" <<JSON
{"raw": "/scratch/slacube/work/${USER}/${name}.h5", "submitted": "2026-02-21T00:00:00", "attempts": 1, "not_before": null, "last_error": null, "pid": null, "started": "2026-02-21T00:00:00", "finished": "${finished}", "duration_s": 1.0, "out": "/data/slacube/dropbox/${name}.h5"}
JSON
}


echo "============================================================"
echo "test_guard_acquisition"
echo "============================================================"


# ---------------------------------------------------------- clear path returns 0
echo
echo "[clear: returns 0 immediately when nothing is wrong]"
eval "$(make_fixture)"
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX")
cd "$WORKDIR"
out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_GUARD_POLL=1 \
PATH="$fake_df:$PATH" \
  bash -c 'source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1; guard_acquisition; echo "rc=$?"')
echo "$out"
echo "$out" | grep -q '^rc=0$' && check 1 "clear: rc==0" || check 0 "clear: rc==0"

rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- backlog hold and resume
echo
echo "[backlog: holds while pending+running > MAX_BACKLOG, resumes when <= MAX_BACKLOG/2]"
eval "$(make_fixture)"
seed_incoming "$SPOOL" 9
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX")
cd "$WORKDIR"
(
  sleep 2
  for f in "$SPOOL"/incoming/*.json; do mv "$f" "$SPOOL/done/"; done
) &
drainer=$!

t0=$(date +%s)
out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_GUARD_POLL=1 \
SLACUBE_MAX_BACKLOG=8 \
SLACUBE_MAX_HOLD=30 \
PATH="$fake_df:$PATH" \
  bash -c 'source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1; guard_acquisition; echo "rc=$?"')
t1=$(date +%s)
elapsed=$((t1 - t0))
echo "$out"
echo "$out" | grep -q '^rc=0$' && check 1 "backlog: rc==0 (held then resumed)" || check 0 "backlog: rc==0"
assert "\"$elapsed\" -ge 2" "backlog: held at least 2s before resume (got ${elapsed}s)"
assert "\"$elapsed\" -lt 15" "backlog: did not exceed MAX_HOLD (got ${elapsed}s)"
echo "$out" | grep -q 'workdir_free=[0-9][0-9]*B' && check 1 "backlog: reports workdir free bytes" || check 0 "backlog: reports workdir free bytes"
echo "$out" | grep -q 'dropbox_free=[0-9][0-9]*B' && check 1 "backlog: reports dropbox free bytes" || check 0 "backlog: reports dropbox free bytes"
echo "$out" | grep -q 'backlog=9 quarantined=0 elapsed=0s; waiting on backlog' && check 1 "backlog: reports depth, quarantine, elapsed, and wait reason" || check 0 "backlog: reports complete hold context"


wait "$drainer" 2>/dev/null || true
rm -rf "$ROOT" "$fake_df"

# ---------------------------------------------------------- backlog priority over failures
echo
echo "[priority: backlog hold precedes consecutive-failure stop]"
eval "$(make_fixture)"
seed_incoming "$SPOOL" 9
seed_failed "$SPOOL" 3
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX")
cd "$WORKDIR"
echo 1 > .state
(
  sleep 2
  for f in "$SPOOL"/incoming/*.json; do mv "$f" "$SPOOL/done/"; done
) &
drainer=$!

t0=$(date +%s)
out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_GUARD_POLL=1 \
SLACUBE_MAX_BACKLOG=8 \
SLACUBE_MAX_CONSECUTIVE_FAIL=3 \
SLACUBE_MAX_HOLD=30 \
PATH="$fake_df:$PATH" \
  bash -c '
    source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1
    guard_acquisition
    echo "rc=$?"
  ' 2>&1)
t1=$(date +%s)
elapsed=$((t1 - t0))
echo "$out"
first_guard=$(printf '%s\n' "$out" | grep '^guard:' | sed -n '1p')
echo "$first_guard" | grep -q 'waiting on backlog' && check 1 "priority: backlog is handled before consecutive failures" || check 0 "priority: backlog is handled first"
assert "\"$elapsed\" -ge 2" "priority: backlog held before failure stop (got ${elapsed}s)"
echo "$out" | grep -q '^rc=[1-9]' && check 1 "priority: stops after backlog clears and failures remain" || check 0 "priority: eventual failure stop"

wait "$drainer" 2>/dev/null || true
rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- free-space hold + resume
echo
echo "[free space: holds below MIN_FREE*, resumes only above RESUME_FREE*]"
eval "$(make_fixture)"
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX" 5368709120 5368709120)  # 5 GiB each
cd "$WORKDIR"
(
  sleep 2
  set_fake_df_bytes "$fake_df" "$WORKDIR" "$DROPBOX" 107374182400 161061273600
) &
bump=$!

t0=$(date +%s)
out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_GUARD_POLL=1 \
SLACUBE_MAX_HOLD=30 \
PATH="$fake_df:$PATH" \
  bash -c 'source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1; guard_acquisition; echo "rc=$?"')
t1=$(date +%s)
elapsed=$((t1 - t0))
echo "$out"
echo "$out" | grep -q '^rc=0$' && check 1 "free space: rc==0" || check 0 "free space: rc==0"
assert "\"$elapsed\" -ge 2" "free space: held at least 2s before resume (got ${elapsed}s)"

wait "$bump" 2>/dev/null || true
rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- free-space hysteresis
# While held (bytes < MIN_FREE), raising bytes to a value between MIN_FREE
# and RESUME_FREE must NOT cause the guard to resume: it must stay held
# until bytes are above RESUME_FREE. Test: start at 5 GiB (well below
# MIN_FREE=25 GiB); raise to 1 GiB (still well below MIN_FREE) for a
# few seconds; then raise to 100 GiB / 150 GiB (above RESUME_FREE). The
# guard should not resume until the final raise.
echo
echo "[free space: stays held between MIN_FREE and RESUME_FREE, only resumes above RESUME_FREE]"
eval "$(make_fixture)"
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX" 5368709120 5368709120)
cd "$WORKDIR"
(
  sleep 2
  # Still well below MIN_FREE; guard should stay held.
  set_fake_df_bytes "$fake_df" "$WORKDIR" "$DROPBOX" 1073741824 1073741824
  sleep 3
  # Above RESUME_FREE; guard should resume now.
  set_fake_df_bytes "$fake_df" "$WORKDIR" "$DROPBOX" 107374182400 161061273600
) &
bump=$!

t0=$(date +%s)
out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_GUARD_POLL=1 \
SLACUBE_MAX_HOLD=30 \
PATH="$fake_df:$PATH" \
  bash -c 'source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1; guard_acquisition; echo "rc=$?"')
t1=$(date +%s)
elapsed=$((t1 - t0))
echo "$out"
echo "$out" | grep -q '^rc=0$' && check 1 "hysteresis: rc==0 (eventually resumed)" || check 0 "hysteresis: rc==0"
assert "\"$elapsed\" -ge 5" "hysteresis: held at least 5s before resume (got ${elapsed}s)"

wait "$bump" 2>/dev/null || true
rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- consecutive failures -> STOP
echo
echo "[consecutive failures (exit_code 1): stops, not holds]"
eval "$(make_fixture)"
seed_failed "$SPOOL" 4
seed_done "$SPOOL" "newer_success" "2026-02-21T00:01:01"
cd "$WORKDIR"
echo 1 > .state
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX")

t0=$(date +%s)
out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_GUARD_POLL=1 \
SLACUBE_MAX_CONSECUTIVE_FAIL=2 \
PATH="$fake_df:$PATH" \
  bash -c '
    source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1
    guard_acquisition
    rc=$?
    echo "rc=$rc"
    echo "state=$(cat .state 2>/dev/null)"
  ' 2>&1)
t1=$(date +%s)
elapsed=$((t1 - t0))
echo "$out"
echo "$out" | grep -q '^rc=[1-9]' && check 1 "stop-on-fail: rc!=0" || check 0 "stop-on-fail: rc!=0"
echo "$out" | grep -q '^state=0$' && check 1 "stop-on-fail: .state=0" || check 0 "stop-on-fail: .state=0"
assert "\"$elapsed\" -lt 3" "stop-on-fail: did not hold (elapsed=${elapsed}s)"
echo "$out" | grep -q 'reports 2 consecutive failures' && check 1 "stop-on-fail: reports consecutive_fail, not total quarantined" || check 0 "stop-on-fail: reports consecutive_fail"
if echo "$out" | grep -q 'reports 4 consecutive failures'; then
  check 0 "stop-on-fail: does not label all quarantined jobs consecutive"
else
  check 1 "stop-on-fail: does not label all quarantined jobs consecutive"
fi

rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- isolated failures (exit_code 2) proceed
echo
echo "[isolated failures (exit_code 2): prints warning, proceeds]"
eval "$(make_fixture)"
seed_failed "$SPOOL" 1  # below MAX_CONSECUTIVE_FAIL=3, so exit_code 2
cd "$WORKDIR"
echo 1 > .state
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX")

out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_GUARD_POLL=1 \
SLACUBE_MAX_CONSECUTIVE_FAIL=3 \
PATH="$fake_df:$PATH" \
  bash -c '
    source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1
    guard_acquisition
    echo "rc=$?"
    echo "state=$(cat .state 2>/dev/null)"
  ')
echo "$out"
echo "$out" | grep -q '^rc=0$' && check 1 "isolated: rc==0 (proceeds)" || check 0 "isolated: rc==0"
echo "$out" | grep -q '^state=1$' && check 1 "isolated: .state unchanged (still 1)" || check 0 "isolated: .state unchanged"

rm -rf "$ROOT" "$fake_df"

# ---------------------------------------------------------- newest quarantined by timestamp
echo
echo "[isolated failures: newest quarantine is selected by finished timestamp]"
eval "$(make_fixture)"
cat > "$SPOOL/failed/zzz_old.json" <<JSON
{"raw": "/scratch/zzz_old.h5", "submitted": "2026-02-21T00:00:00", "attempts": 3, "not_before": null, "last_error": "old", "pid": null, "started": "2026-02-21T00:00:00", "finished": "2026-02-21T00:01:00", "duration_s": 1.0, "out": null}
JSON
cat > "$SPOOL/failed/aaa_new.json" <<JSON
{"raw": "/scratch/aaa_new.h5", "submitted": "2026-02-21T00:00:00", "attempts": 3, "not_before": null, "last_error": "new", "pid": null, "started": "2026-02-21T00:00:00", "finished": "2026-02-21T00:02:00", "duration_s": 1.0, "out": null}
JSON
cd "$WORKDIR"
echo 1 > .state
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX")

out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_MAX_CONSECUTIVE_FAIL=3 \
PATH="$fake_df:$PATH" \
  bash -c 'source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1; guard_acquisition' 2>&1)
echo "$out"
echo "$out" | grep -q 'newest: aaa_new' && check 1 "isolated: newest job follows finished timestamp" || check 0 "isolated: newest job follows finished timestamp"

rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- invalid directory stops state
echo
echo "[configuration error: invalid directory clears acquisition state]"
eval "$(make_fixture)"
cd "$ROOT"
echo 1 > .state
out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$ROOT/missing-workdir" \
SLACUBE_DROPBOX="$DROPBOX" \
  bash -c '
    source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1
    guard_acquisition
    echo "rc=$?"
    echo "state=$(cat .state)"
  ' 2>&1)
echo "$out"
echo "$out" | grep -q '^rc=2$' && check 1 "configuration: invalid workdir returns 2" || check 0 "configuration: invalid workdir returns 2"
echo "$out" | grep -q '^state=0$' && check 1 "configuration: invalid workdir clears .state" || check 0 "configuration: invalid workdir clears .state"

rm -rf "$ROOT"


# ---------------------------------------------------------- df failure -> STOP
echo
echo "[df failure (non-zero exit): stops, not holds]"
eval "$(make_fixture)"
cd "$WORKDIR"
echo 1 > .state
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX" 0 0 1 0)  # df fails on WORKDIR

out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_GUARD_POLL=1 \
PATH="$fake_df:$PATH" \
  bash -c '
    source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1
    guard_acquisition
    echo "rc=$?"
    echo "state=$(cat .state 2>/dev/null)"
  ')
echo "$out"
echo "$out" | grep -q '^rc=[1-9]' && check 1 "df-fail: rc!=0" || check 0 "df-fail: rc!=0"
echo "$out" | grep -q '^state=0$' && check 1 "df-fail: .state=0" || check 0 "df-fail: .state=0"

rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- MAX_HOLD exceeded -> STOP
echo
echo "[MAX_HOLD exceeded: stops after MAX_HOLD seconds of holding]"
eval "$(make_fixture)"
fake_df=$(make_fake_df "$WORKDIR" "$DROPBOX" 5368709120 5368709120)
cd "$WORKDIR"
echo 1 > .state

t0=$(date +%s)
out=$(SLACUBE_SPOOL="$SPOOL" \
SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_GUARD_POLL=1 \
SLACUBE_MAX_HOLD=3 \
PATH="$fake_df:$PATH" \
  bash -c '
    source "'"$BIN_DIR"'/slacube" >/dev/null 2>&1
    guard_acquisition
    echo "rc=$?"
    echo "state=$(cat .state 2>/dev/null)"
  ')
t1=$(date +%s)
elapsed=$((t1 - t0))
echo "$out"
assert "\"$elapsed\" -ge 3" "max-hold: held at least 3s (got ${elapsed}s)"
assert "\"$elapsed\" -lt 6" "max-hold: stopped soon after (got ${elapsed}s, should be ~3-5s)"
echo "$out" | grep -q '^rc=[1-9]' && check 1 "max-hold: rc!=0" || check 0 "max-hold: rc!=0"
echo "$out" | grep -q '^state=0$' && check 1 "max-hold: .state=0" || check 0 "max-hold: .state=0"

rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- cmd_run repeat reset
echo
echo "[run loop: every pedestal cycle runs selftrig-repeat acquisitions]"
eval "$(make_fixture)"
fake_bin=$(mktemp -d /tmp/slacube_fake_run_XXXXXX)
qc_dir="$ROOT/qc"
cfg_dir="$ROOT/cfg"
mkdir -p "$qc_dir" "$cfg_dir"
touch "$ROOT/controller.json" "$ROOT/bad-channels.json"
cat > "$WORKDIR/.slacuberc" <<RC
CTRL_FILE $ROOT/controller.json
BAD_CHANNEL_FILE $ROOT/bad-channels.json
CFG_DIR $cfg_dir
RC
cat > "$fake_bin/python" <<'PY'
#!/usr/bin/env bash
script=${1##*/}
shift
outdir=""
while (($#)); do
  if [[ $1 == --outdir ]]; then outdir=$2; break; fi
  shift
done
case "$script" in
  pedestal_qc.py)
    count_file="$SLACUBE_WORKDIR/pedestal-count"
    count=$(cat "$count_file" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$count_file"
    touch "$outdir/pedestal-${count}.h5"
    # Bound a regressed loop whose self-trigger counter never resets.
    (( count < 3 )) || echo 0 > "$SLACUBE_WORKDIR/.state"
    ;;
  selftrigger_qc.py)
    count_file="$SLACUBE_WORKDIR/selftrig-count"
    count=$(cat "$count_file" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$count_file"
    touch "$outdir/raw_2026_02_21_21_52_$(printf '%02d' "$count").h5"
    ;;
esac
PY
chmod +x "$fake_bin/python"
cat > "$fake_bin/slacube-convertd" <<'CONVERTD'
#!/usr/bin/env bash
case "$1" in
  status)
    echo '{"pending":0,"running":0,"failed":0,"done":0,"consecutive_fail":0}'
    ;;
  submit)
    count_file="$SLACUBE_WORKDIR/submit-count"
    count=$(cat "$count_file" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$count_file"
    (( count < 4 )) || echo 0 > "$SLACUBE_WORKDIR/.state"
    ;;
esac
CONVERTD
chmod +x "$fake_bin/slacube-convertd"

out=$(SLACUBE_WORKDIR="$WORKDIR" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
SLACUBE_QC_SCRIPTS="$qc_dir" \
SLACUBE_MIN_FREE=0 \
SLACUBE_MIN_FREE_DROPBOX=0 \
SLACUBE_RESUME_FREE=0 \
SLACUBE_RESUME_FREE_DROPBOX=0 \
PATH="$fake_bin:$PATH" \
  "$BIN_DIR/slacube" run start 0 0 2 2>&1)
rc=$?
echo "$out"
assert "\"$rc\" -eq 0" "run-loop: command exits cleanly"
pedestal_count=$(cat "$WORKDIR/pedestal-count" 2>/dev/null || echo 0)
submit_count=$(cat "$WORKDIR/submit-count" 2>/dev/null || echo 0)
raw_count=$(find "$WORKDIR/tmp" -name 'raw*.h5' -type f | wc -l)
assert "\"$pedestal_count\" -eq 2" "run-loop: completed two outer pedestal cycles"
assert "\"$submit_count\" -eq 4" "run-loop: each outer cycle submitted two self-trigger raws"
assert "\"$raw_count\" -eq 4" "run-loop: submitted raws remain at recorded paths for asynchronous conversion"

rm -rf "$ROOT" "$fake_bin"


# ---------------------------------------------------------- result
echo
echo "============================================================"
if [[ "$_failures" -ne 0 ]]; then
  echo "FAILED ($_failures)"
  exit 1
fi
echo "ALL PASSED"
exit 0
