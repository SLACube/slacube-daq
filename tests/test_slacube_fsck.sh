#!/usr/bin/env bash
# Tests for bin/slacube-fsck.
#
# Standalone bash test harness. Seeds a synthetic raw cache + dropbox +
# pool + spool layout, each test triggering one or more of fsck's six
# report sections. Exits 0 on success, non-zero otherwise.
#
# Run as:
#     bash tests/test_slacube_fsck.sh
#
# The script's "free space per tier" section reads `df`; tests do not
# assert free-space *values*, only that the section header appears.
# Faking `df` (as Task 2's tests do) is unnecessary here because
# fsck always reports whatever the host's df says for each tier.

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

# Build a per-test tempdir with $RAW_CACHE, $DROPBOX, $POOL, $SPOOL.
make_fixture() {
  local root
  root=$(mktemp -d /tmp/slacube_fsck_test_XXXXXX)
  local raw_cache="$root/raw"
  local dropbox="$root/data/dropbox"
  local pool="$root/data/pool"
  local spool="$root/spool"
  mkdir -p "$raw_cache" "$dropbox" "$pool"
  for sub in incoming running failed done; do
    mkdir -p "$spool/$sub"
  done
  cat <<FIXTURE
ROOT=$root
RAW_CACHE=$raw_cache
DROPBOX=$dropbox
POOL=$pool
SPOOL=$spool
FIXTURE
}


echo "============================================================"
echo "test_slacube_fsck"
echo "============================================================"


# ---------------------------------------------------------- section (a): raw without twin
echo
echo "[section (a): raw files in raw cache with no converted twin are listed]"
eval "$(make_fixture)"
# A raw whose converted twin exists -> should NOT appear in section (a).
mkdir -p "$RAW_CACHE/2026/2026-02-21"
touch "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_18.h5"
touch "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5"
# A raw with NO twin -> SHOULD appear in section (a).
touch "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_19.h5"

out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "fsck: exits 0 on healthy scan"
echo "$out" | grep -q 'raw without converted twin' && check 1 "fsck: section (a) header present" || check 0 "fsck: section (a) header present"
echo "$out" | grep -q 'raw_2026_02_21_21_52_19' && check 1 "fsck: section (a) lists the twin-less raw" || check 0 "fsck: section (a) lists the twin-less raw"
# The raw whose twin DOES exist should NOT be listed in (a).
echo "$out" | awk '/raw without converted twin/{f=1; next} /^##/{f=0} f' | grep -q 'raw_2026_02_21_21_52_18' && check 0 "fsck: section (a) does NOT list raw with twin" || check 1 "fsck: section (a) does NOT list raw with twin"
rm -rf "$ROOT"


# ---------------------------------------------------------- section (b): leftover .part/.tmp
echo
echo "[section (b): leftover .part/.tmp in dropbox are listed]"
eval "$(make_fixture)"
touch "$DROPBOX/.selftrigger_2026_02_21_21_52_18.h5.part"
touch "$DROPBOX/.selftrigger_2026_02_21_21_52_19.h5.tmp"

out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
echo "$out" | grep -q 'leftover part' && check 1 "fsck: section (b) header present" || check 0 "fsck: section (b) header present"
echo "$out" | grep -q '\.selftrigger_2026_02_21_21_52_18\.h5\.part' && check 1 "fsck: section (b) lists .part file" || check 0 "fsck: section (b) lists .part file"
echo "$out" | grep -q '\.selftrigger_2026_02_21_21_52_19\.h5\.tmp' && check 1 "fsck: section (b) lists .tmp file" || check 0 "fsck: section (b) lists .tmp file"
rm -rf "$ROOT"


# ---------------------------------------------------------- section (c): failed jobs
echo
echo "[section (c): failed jobs listed with last_error + age]"
eval "$(make_fixture)"
cat > "$SPOOL/failed/raw_2026_02_21_21_52_18.json" <<JSON
{"raw": "/scratch/raw_2026_02_21_21_52_18.h5", "submitted": "2026-02-21T21:52:18", "attempts": 3, "last_error": "converter crashed", "pid": null, "started": "2026-02-21T21:52:18", "finished": "2026-02-21T21:53:00", "duration_s": 42.0, "out": null}
JSON

out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
echo "$out" | grep -q 'failed jobs' && check 1 "fsck: section (c) header present" || check 0 "fsck: section (c) header present"
echo "$out" | grep -q 'raw_2026_02_21_21_52_18' && check 1 "fsck: section (c) lists the failed job name" || check 0 "fsck: section (c) lists the failed job name"
echo "$out" | grep -q 'converter crashed' && check 1 "fsck: section (c) lists last_error" || check 0 "fsck: section (c) lists last_error"
# Age formatting: should mention "h" or "d" (hours/days)
echo "$out" | awk '/failed jobs/{f=1; next} /^##/{f=0} f' | grep -q 'raw_2026_02_21_21_52_18' && echo "$out" | awk '/failed jobs/{f=1; next} /^##/{f=0} f' | grep -qE '[0-9]+(\.[0-9]+)?[hd]' && check 1 "fsck: section (c) lists age in h/d" || check 0 "fsck: section (c) lists age in h/d"
rm -rf "$ROOT"


# ---------------------------------------------------------- section (d): old dropbox files
echo
echo "[section (d): dropbox files older than 24h are listed]"
eval "$(make_fixture)"
touch "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5"
touch -d "2 days ago" "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5"

out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
echo "$out" | grep -q 'dropbox files older' && check 1 "fsck: section (d) header present" || check 0 "fsck: section (d) header present"
echo "$out" | awk '/dropbox files older/{f=1; next} /^##/{f=0} f' | grep -q 'selftrigger_2026_02_21_21_52_18' && check 1 "fsck: section (d) lists the 2-day-old file" || check 0 "fsck: section (d) lists the 2-day-old file"
rm -rf "$ROOT"


# ---------------------------------------------------------- section (d): fresh dropbox NOT listed
echo
echo "[section (d): dropbox files newer than 24h are NOT listed]"
eval "$(make_fixture)"
touch "$DROPBOX/selftrigger_2026_02_21_21_52_18.h5"
# mtime is "now"

out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
echo "$out" | awk '/dropbox files older/{f=1; next} /^##/{f=0} f' | grep -q 'selftrigger_2026_02_21_21_52_18' && check 0 "fsck: section (d) excludes fresh file" || check 1 "fsck: section (d) excludes fresh file"
rm -rf "$ROOT"


# ---------------------------------------------------------- section (e): S3DF check is documented, not run
echo
echo "[section (e): pool S3DF verification is documented, not run]"
eval "$(make_fixture)"
out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
echo "$out" | grep -qi 's3df\|sync-pool\|sdfcron' && check 1 "fsck: section (e) mentions S3DF/sync-pool/sdfcron" || check 0 "fsck: section (e) mentions S3DF/sync-pool/sdfcron"
# Must NOT actually try to reach sdfcron001.
echo "$out" | grep -qi 'ssh.*sdfcron' && check 0 "fsck: section (e) does NOT ssh to sdfcron" || check 1 "fsck: section (e) does NOT ssh to sdfcron"
rm -rf "$ROOT"


# ---------------------------------------------------------- section (f): free space
echo
echo "[section (f): free space per tier (df output)]"
eval "$(make_fixture)"
out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
echo "$out" | grep -qi 'free space' && check 1 "fsck: section (f) header present" || check 0 "fsck: section (f) header present"
echo "$out" | grep -q 'raw_cache' && check 1 "fsck: section (f) mentions raw_cache" || check 0 "fsck: section (f) mentions raw_cache"
echo "$out" | grep -q 'dropbox' && check 1 "fsck: section (f) mentions dropbox" || check 0 "fsck: section (f) mentions dropbox"
rm -rf "$ROOT"


# ---------------------------------------------------------- always exits 0 on healthy tree
echo
echo "[default: empty tree -> exit 0]"
eval "$(make_fixture)"
SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck >/dev/null 2>&1
check $([[ $? -eq 0 ]] && echo 1 || echo 0) "fsck: empty tree exits 0"
rm -rf "$ROOT"


# ---------------------------------------------------------- missing env exits 1
echo
echo "[config: missing \$SLACUBE_DROPBOX -> exit 1]"
out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
rc=$?
check $([[ $rc -eq 1 ]] && echo 1 || echo 0) "fsck: unset SLACUBE_DROPBOX -> exit 1"
echo "$out" | grep -qi 'SLACUBE_DROPBOX' && check 1 "fsck: error mentions SLACUBE_DROPBOX" || check 0 "fsck: error mentions SLACUBE_DROPBOX"


# ---------------------------------------------------------- D7: pool/raw/ is never entered
echo
echo "[D7: pool/raw/ subtree is never visited by fsck]"
eval "$(make_fixture)"
mkdir -p "$POOL/raw"
# Seed a file whose basename would match the converted twin if walked
# (legacy tree carries pre-scheme data; not a real twin).
touch "$POOL/raw/selftrigger_2026_02_21_21_52_18.h5"
# Also seed a real twin-less raw so the section (a) findings list is
# non-empty (the report still has to be valid; D7 does not silence
# the section header).
mkdir -p "$RAW_CACHE/2026/2026-02-21"
touch "$RAW_CACHE/2026/2026-02-21/raw_2026_02_21_21_52_18.h5"

out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "D7: fsck exits 0 with pool/raw/ present"
# The pool/raw/ file must NOT appear in any section of the report.
echo "$out" | grep -q "$POOL/raw/" && check 0 "D7: pool/raw/ file is NOT listed anywhere" || check 1 "D7: pool/raw/ file is NOT listed anywhere"
# Stderr note should mention pool/raw/ once (D7 exclusion fired).
echo "$out" | grep -qi 'pool/raw/' && check 1 "D7: stderr note announces pool/raw/ exclusion" || check 0 "D7: stderr note announces pool/raw/ exclusion"
rm -rf "$ROOT"

# ---------------------------------------------------------- section (b) scans workdir too
echo
echo "[section (b): leftover .part/.tmp in workdir tree (Task 1's primary .part location)]"
eval "$(make_fixture)"
mkdir -p "$ROOT/scratch/workdir"
touch "$DROPBOX/.selftrigger_2026_02_21_21_52_18.h5.part"
touch "$ROOT/scratch/workdir/.selftrigger_2026_02_21_21_52_19.h5.part"

out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
echo "$out" | grep -q 'leftover part' && check 1 "section (b) header present" || check 0 "section (b) header present"
echo "$out" | awk '/leftover part/{f=1; next} /^##/{f=0} f' | grep -q 'scratch/workdir/.selftrigger_2026_02_21_21_52_19.h5.part' && check 1 "section (b) scans workdir tree" || check 0 "section (b) scans workdir tree"
rm -rf "$ROOT"


# ---------------------------------------------------------- _check_scoped: unreadable raw_cache
echo
echo "[config: unreadable scoped directory -> exit 1]"
eval "$(make_fixture)"
chmod 000 "$RAW_CACHE"
out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
rc=$?
chmod 755 "$RAW_CACHE"
check $([[ $rc -eq 1 ]] && echo 1 || echo 0) "fsck: unreadable raw_cache -> exit 1"
echo "$out" | grep -qi 'SLACUBE_RAW_CACHE' && check 1 "fsck: error mentions SLACUBE_RAW_CACHE" || check 0 "fsck: error mentions SLACUBE_RAW_CACHE"
rm -rf "$ROOT"


# ---------------------------------------------------------- _check_scoped: unreadable pool
echo
echo "[config: unreadable pool/ -> exit 1]"
eval "$(make_fixture)"
chmod 000 "$POOL"
out=$(SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
rc=$?
chmod 755 "$POOL"
check $([[ $rc -eq 1 ]] && echo 1 || echo 0) "fsck: unreadable pool/ -> exit 1"
echo "$out" | grep -qi 'pool' && check 1 "fsck: error mentions pool/" || check 0 "fsck: error mentions pool/"
rm -rf "$ROOT"


# ---------------------------------------------------------- TZ: failed-job age is correct
# The "_parse_iso" function inside slacube-fsck must interpret a
# naive-UTC ISO8601 timestamp as UTC, regardless of host $TZ. The
# earlier implementation used datetime.strftime("%s"), which is
# glibc-only and treats the parsed wall-clock time as local time --
# so a failed-job 'finished' timestamp carries an error equal to the
# host's UTC offset. Drive slacube-fsck under TZ=America/Los_Angeles
# and assert the reported age is consistent with UTC, not local.
echo
echo "[TZ: failed-job age is computed against UTC, not host TZ]"
eval "$(make_fixture)"
# Seed a finished record exactly 1 hour ago in TRUE UTC.
now_epoch=$(date -u +%s)
finished_epoch=$((now_epoch - 3600))
finished_utc=$(TZ=UTC date -u -d "@$finished_epoch" '+%Y-%m-%dT%H:%M:%S')
cat > "$SPOOL/failed/raw_2026_02_21_21_52_18.json" <<JSON
{"raw": "/scratch/raw_2026_02_21_21_52_18.h5", "submitted": "$finished_utc", "attempts": 3, "last_error": "x", "pid": null, "started": "$finished_utc", "finished": "$finished_utc", "duration_s": 42.0, "out": null}
JSON

out=$(TZ=America/Los_Angeles \
SLACUBE_RAW_CACHE="$RAW_CACHE" \
SLACUBE_DROPBOX="$DROPBOX" \
SLACUBE_SPOOL="$SPOOL" \
  slacube-fsck 2>&1)
# Age must be within (0.5h, 1.5h) of "1 hour ago". The bug would
# surface as an age shifted by 7-8 hours (PST offset) and so well
# outside this band.
age_line=$(echo "$out" | awk '/failed jobs/{f=1; next} /^##/{f=0} f' | grep raw_2026_02_21_21_52_18 | head -1)
age_val=$(echo "$age_line" | grep -oE '[0-9]+\.[0-9]+h' | head -1 | tr -d 'h')
check $([[ -n "$age_val" ]] && python3 -c "v=$age_val; import sys; sys.exit(0 if 0.5 <= v <= 1.5 else 1)" && echo 1 || echo 0) \
  "TZ: failed-job age=${age_val}h is consistent with UTC (should be ~1h)"
rm -rf "$ROOT"

echo
echo "============================================================"
if [[ "$_failures" -ne 0 ]]; then
  echo "FAILED ($_failures)"
  exit 1
fi
echo "ALL PASSED"
exit 0
