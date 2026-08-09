#!/usr/bin/env bash
# Tests for bin/slacube-reap.
#
# Standalone bash test harness. Uses a PATH-shadowing fake `df` that
# tracks its call count via a state file and returns bytes from a
# caller-supplied schedule (GiB values, space-separated). Each test
# seeds the schedule with the values the reap loop must observe to
# terminate after the desired number of evictions.
#
# Run as:
#     bash tests/test_slacube_reap.sh

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

# Per-test tempdir with $RAW_CACHE, $DROPBOX, $POOL.
make_fixture() {
  local root
  root=$(mktemp -d /tmp/slacube_reap_test_XXXXXX)
  local raw_cache="$root/raw"
  local dropbox="$root/data/dropbox"
  local pool="$root/data/pool"
  mkdir -p "$raw_cache" "$dropbox" "$pool"
  cat <<FIXTURE
ROOT=$root
RAW_CACHE=$raw_cache
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

# Build a PATH-shadowing dir with a fake `df` whose output depends on
# call count, per REAP_TEST_DF_SCHEDULE (GiB values, space-separated).
# The schedule is consumed left-to-right; once exhausted, the last
# value is returned forever. Call count is tracked in the file at
# $SLACUBE_REAP_TEST_DF_STATE.
make_fake_df() {
  local dir
  dir=$(mktemp -d /tmp/slacube_reap_fake_df_XXXXXX)
  cat > "$dir/df" <<'DF'
#!/usr/bin/env bash
state="${SLACUBE_REAP_TEST_DF_STATE:-}"
if [[ -n "$state" ]]; then
  n_calls=0
  [[ -f "$state" ]] && n_calls=$(cat "$state" 2>/dev/null)
  n_calls=$((n_calls + 1))
  echo "$n_calls" > "$state"
  sched="${REAP_TEST_DF_SCHEDULE:-100 100 100 100 800}"
  i=0
  val=""
  for v in $sched; do
    if [[ $i -eq $((n_calls - 1)) ]]; then val="$v"; break; fi
    i=$((i + 1))
  done
  if [[ -z "$val" ]]; then val=$(echo "$sched" | awk '{print $NF}'); fi
  printf '%s\n' "$((val * 1024 * 1024 * 1024))"
  exit 0
fi
printf '%s\n' "1125899906842624"
exit 0
DF
  chmod +x "$dir/df"
  echo "$dir"
}


echo "============================================================"
echo "test_slacube_reap"
echo "============================================================"


# ---------------------------------------------------------- above HIGH: no-op
echo
echo "[above HIGH watermark: no eviction]"
eval "$(make_fixture)"
mkdir -p "$RAW_CACHE/2026/2026-02-21"
for i in 1 2 3; do
  touch "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_1${i}.h5"
  backdate "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_1${i}.h5" $((i * 600))
done

fake_df=$(make_fake_df)
SLACUBE_REAP_TEST_DF_STATE="$ROOT/df_state" \
REAP_TEST_DF_SCHEDULE="900" \
PATH="$fake_df:$PATH" \
SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_RAW_CACHE_LOW=$((500 * 1024 ** 3)) \
SLACUBE_RAW_CACHE_HIGH=$((750 * 1024 ** 3)) \
  slacube-reap >/dev/null 2>"$ROOT/out.log"
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "above-high: exit 0"
n=$(find "$RAW_CACHE" -name 'raw_*.h5' -type f | wc -l)
check $([[ $n -eq 3 ]] && echo 1 || echo 0) "above-high: no raws evicted (n=$n)"
grep -qi 'free=' "$ROOT/out.log" && check 1 "above-high: log notes free" || check 0 "above-high: log notes free"
rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- below LOW: evict oldest-first
echo
echo "[below LOW watermark: evict oldest-first down to HIGH]"
eval "$(make_fixture)"
mkdir -p "$RAW_CACHE/2026/2026-02-21"
# 5 raws with increasing mtimes (oldest: i=1, newest: i=5).
for i in 1 2 3 4 5; do
  b="raw_2026_02_21_21_52_1${i}.h5"
  touch "$RAW_CACHE/2026/2026-02-21/$b"
  backdate "$RAW_CACHE/2026/2026-02-21/$b" $((i * 3600))
  touch "$DROPBOX/selftrigger_2026_02_21_21_52_1${i}.h5"
done

fake_df=$(make_fake_df)
# Schedule trace with 5 raws (walk order is oldest-first; the
# `backdate "$b" $((i*3600))` makes i=5 the oldest at 5h ago, i=1
# the newest at 1h ago):
#   call 1 reap_loop entry -> 100 -> enter body
#   call 2 _reap_once first check -> 100 -> walk
#   call 3 i=5 (oldest) per-raw check -> 100 -> evict
#   call 4 i=4 per-raw check -> 100 -> evict
#   call 5 i=3 per-raw check -> 800 -> break (>= HIGH)
#   call 6 reap_loop exit check -> 800 -> break (>= HIGH)
# Total: 2 evictions; i=5 and i=4 gone; i=1,2,3 remain.
fake_df=$(make_fake_df)
SLACUBE_REAP_TEST_DF_STATE="$ROOT/df_state" \
REAP_TEST_DF_SCHEDULE="100 100 100 100 800 800 800 800 800 800 800 800 800 800 800 800 800 800 800 800" \
PATH="$fake_df:$PATH" \
SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_RAW_CACHE_LOW=$((500 * 1024 ** 3)) \
SLACUBE_RAW_CACHE_HIGH=$((750 * 1024 ** 3)) \
  slacube-reap >/dev/null 2>"$ROOT/out.log"
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "below-low: exit 0"
n=$(find "$RAW_CACHE" -name 'raw_*.h5' -type f | wc -l)
check $([[ $n -eq 3 ]] && echo 1 || echo 0) "below-low: 3 raws remain (n=$n)"
# Oldest (i=5, 5h ago) and 2nd-oldest (i=4, 4h ago) evicted.
check $([[ ! -f "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_15.h5" ]] && echo 1 || echo 0) "below-low: oldest (i=5) evicted"
check $([[ ! -f "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_14.h5" ]] && echo 1 || echo 0) "below-low: 2nd oldest (i=4) evicted"
check $([[ -f "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_13.h5" ]] && echo 1 || echo 0) "below-low: 3rd oldest (i=3) kept"
check $([[ -f "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_11.h5" ]] && echo 1 || echo 0) "below-low: newest (i=1) kept"
grep -q 'evicted=2' "$ROOT/out.log" && check 1 "below-low: log reports evicted=2" || check 0 "below-low: log reports evicted=2"
rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- twin-less raw is never evicted
echo
echo "[twin-less raw: never evicted, even under pressure]"
eval "$(make_fixture)"
mkdir -p "$RAW_CACHE/2026/2026-02-21"
# Make raw_1 (twin-bearing) the OLDER one so it is walked first;
# raw_2 (twin-less) is the newer one, walked second. Schedule
# "100 100 100 100 800..." means: call 3 evict raw_1 (twin-bearing),
# call 4 per-raw check on raw_2 returns 800 -> break. So 1 eviction,
# raw_2 retained.
touch "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_11.h5"
backdate "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_11.h5" 7200  # older
touch "$DROPBOX/selftrigger_2026_02_21_21_52_11.h5"
touch "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_12.h5"
backdate "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_12.h5" 3600  # newer

fake_df=$(make_fake_df)
SLACUBE_REAP_TEST_DF_STATE="$ROOT/df_state" \
REAP_TEST_DF_SCHEDULE="100 100 100 100 800 800 800 800 800 800 800 800 800 800 800 800 800 800 800 800" \
PATH="$fake_df:$PATH" \
SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_RAW_CACHE_LOW=$((500 * 1024 ** 3)) \
SLACUBE_RAW_CACHE_HIGH=$((750 * 1024 ** 3)) \
  slacube-reap >/dev/null 2>"$ROOT/out.log"
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "twin-less: exit 0"
check $([[ -f "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_12.h5" ]] && echo 1 || echo 0) \
  "twin-less: twin-less raw retained"
grep -q 'raw_2026_02_21_21_52_12' "$ROOT/out.log" && check 1 "twin-less: log mentions twin-less raw" || check 0 "twin-less: log mentions twin-less raw"
rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- twin in pool/ also counts
echo
echo "[twin under pool/<type>/... also satisfies the twin check]"
eval "$(make_fixture)"
mkdir -p "$RAW_CACHE/2026/2026-02-21"
mkdir -p "$POOL/selftrigger/2026/2026-02-21"
# raw_1 (twin in pool/, evictable) is the OLDER one so it is walked
# first; raw_2 (twin-less) is the newer one, walked second.
touch "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_11.h5"
backdate "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_11.h5" 7200
touch "$POOL/selftrigger/2026/2026-02-21/selftrigger_2026_02_21_21_52_11.h5"
touch "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_12.h5"
backdate "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_12.h5" 3600

fake_df=$(make_fake_df)
SLACUBE_REAP_TEST_DF_STATE="$ROOT/df_state" \
REAP_TEST_DF_SCHEDULE="100 100 100 800 800 800 800 800 800 800 800 800 800 800 800 800 800 800 800 800" \
PATH="$fake_df:$PATH" \
SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_RAW_CACHE_LOW=$((500 * 1024 ** 3)) \
SLACUBE_RAW_CACHE_HIGH=$((750 * 1024 ** 3)) \
  slacube-reap >/dev/null 2>"$ROOT/out.log"
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "pool-twin: exit 0"
check $([[ ! -f "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_11.h5" ]] && echo 1 || echo 0) \
  "pool-twin: raw whose twin is in pool/ was evicted"
check $([[ -f "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_12.h5" ]] && echo 1 || echo 0) \
  "pool-twin: twin-less raw retained"
rm -rf "$ROOT" "$fake_df"


# ---------------------------------------------------------- missing env: exit non-zero
echo
echo "[config: missing \$SLACUBE_RAW_CACHE -> exit non-zero]"
out=$(unset SLACUBE_RAW_CACHE; SLACUBE_DROPBOX=/tmp slacube-reap 2>&1)
rc=$?
check $([[ $rc -ne 0 ]] && echo 1 || echo 0) "config: unset SLACUBE_RAW_CACHE -> non-zero"
echo "$out" | grep -qi 'SLACUBE_RAW_CACHE' && check 1 "config: error mentions SLACUBE_RAW_CACHE" || check 0 "config: error mentions SLACUBE_RAW_CACHE"


# ---------------------------------------------------------- result
echo
echo "============================================================"
if [[ "$_failures" -ne 0 ]]; then
  echo "FAILED ($_failures)"
  exit 1
fi
echo "ALL PASSED"
exit 0
