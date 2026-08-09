#!/usr/bin/env bash
# Tests for sync/slacube-sync-pool.
#
# Standalone bash test harness. Runs `slacube-sync-pool` against two
# local temp directories standing in for the DAQ host's pool and the
# S3DF (sdfcron001) pool -- no real SSH to nu-daq01-ir2 or sdfcron001.
# rsync supports local paths natively, so by overriding
# SLACUBE_SYNC_SOURCE to `$SRC/` and SLACUBE_SYNC_DEST to `$DST/`, we
# fully exercise the pull + verify + dry-run + delete-source paths.
# The `enumerate_source_files` helper inside the script is invoked
# locally (the file walker), not over ssh, since the source is a
# local path during the tests.
#
# Run as:
#     bash tests/test_slacube_sync_pool.sh

HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/.." && pwd)
SYNC_DIR=$(cd "$HERE/../sync" && pwd)

export PATH="$SYNC_DIR:$PATH"

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

# Build a per-test tempdir with $SRC, $DST, $OUT (stdout capture).
make_fixture() {
  local root
  root=$(mktemp -d /tmp/slacube_sync_pool_test_XXXXXX)
  local src="$root/src"
  local dst="$root/dst"
  mkdir -p "$src" "$dst"
  cat <<FIXTURE
ROOT=$root
SRC=$src
DST=$dst
FIXTURE
}

# Seed a synthetic pool tree under $1 (the root the caller wants:
# $SRC or $DST). The tree follows pool/<type>/<year>/<date>/<file>.h5
# and includes a pool/raw/ that must be excluded from any sync.
seed_pool_tree() {
  local root="$1"
  mkdir -p "$root/pool/selftrigger/2026/2026-08-01"
  mkdir -p "$root/pool/selftrigger/2026/2026-08-02"
  mkdir -p "$root/pool/pedestal/2026/2026-08-01"
  mkdir -p "$root/pool/raw"
  echo "st-01-A" > "$root/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5"
  echo "st-01-B" > "$root/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_11_00_00.h5"
  echo "st-02-A" > "$root/pool/selftrigger/2026/2026-08-02/selftrigger_2026_08_02_10_00_00.h5"
  echo "ped-01-A" > "$root/pool/pedestal/2026/2026-08-01/pedestal_2026_08_01_09_00_00.h5"
  # stuff that MUST NOT be synced (D7 legacy + raw exclusion).
  echo "LEGACY" > "$root/pool/raw/selftrigger_2026_01_01_00_00_00.h5"
  echo "OTHER" > "$root/pool/raw/some-other-thing.h5"
}


echo "============================================================"
echo "test_slacube_sync_pool"
echo "============================================================"


# ---------------------------------------------------------- pull populates $DST, excludes raw/
echo
echo "[pull: copies pool tree, excludes pool/raw/]"
eval "$(make_fixture)"
seed_pool_tree "$SRC"

out=$(SLACUBE_SYNC_SOURCE="$SRC/" \
SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "pull: exit 0"
check $([[ -f "$DST/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5" ]] && echo 1 || echo 0) "pull: synced selftrigger file"
check $([[ -f "$DST/pool/pedestal/2026/2026-08-01/pedestal_2026_08_01_09_00_00.h5" ]] && echo 1 || echo 0) "pull: synced pedestal file"
check $([[ ! -e "$DST/pool/raw" ]] && echo 1 || echo 0) "pull: pool/raw/ NOT synced"
# one-line summary on stdout
n_summary=$(echo "$out" | grep -E '^slacube-sync-pool: pulled=' | wc -l)
check $([[ $n_summary -ge 1 ]] && echo 1 || echo 0) "pull: one-line summary printed"
rm -rf "$ROOT"


# ---------------------------------------------------------- verify matches identical files
echo
echo "[verify: identical files are reported as verified-eligible]"
eval "$(make_fixture)"
seed_pool_tree "$SRC"
# First pull.
SLACUBE_SYNC_SOURCE="$SRC/" SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool >/dev/null 2>&1
# Second run: everything in $DST came from $SRC and is identical.
out=$(SLACUBE_SYNC_SOURCE="$SRC/" \
SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "verify: exit 0"
echo "$out" | grep -E '^slacube-sync-pool: pulled=' | grep -q 'verified=4' && check 1 "verify: 4 files verified" || check 0 "verify: 4 files verified"
echo "$out" | grep -E '^slacube-sync-pool: pulled=' | grep -q 'would_delete=4' && check 1 "verify: 4 would_delete eligible" || check 0 "verify: 4 would_delete eligible"
rm -rf "$ROOT"


# ---------------------------------------------------------- drift: corrupted DST file is flagged
echo
echo "[verify: corrupted-DST file is flagged non-matching and excluded from would_delete]"
eval "$(make_fixture)"
seed_pool_tree "$SRC"
SLACUBE_SYNC_SOURCE="$SRC/" SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool >/dev/null 2>&1
# Corrupt one file in $DST (simulate drift). Use a size-preserving
# corruption so rsync -a's size+mtime check does NOT overwrite it
# during the next pull; only the --checksum-based verify step sees
# the difference.
printf 'CORRUPT!' > "$DST/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5"
touch -r "$SRC/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5" \
  "$DST/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5"

out=$(SLACUBE_SYNC_SOURCE="$SRC/" \
SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "drift: exit 0"
echo "$out" | grep -E '^slacube-sync-pool: pulled=' | grep -q 'verified=3' && check 1 "drift: 3 verified (one flagged)" || check 0 "drift: 3 verified (one flagged)"
echo "$out" | grep -E '^slacube-sync-pool: pulled=' | grep -q 'flagged=1' && check 1 "drift: 1 flagged non-matching" || check 0 "drift: 1 flagged non-matching"
echo "$out" | grep -E '^slacube-sync-pool: pulled=' | grep -q 'would_delete=3' && check 1 "drift: 3 would_delete (flagged excluded)" || check 0 "drift: 3 would_delete (flagged excluded)"
rm -rf "$ROOT"


# ---------------------------------------------------------- default invocation NEVER deletes source
echo
echo "[default: invocation does NOT delete from source even when would_delete > 0]"
eval "$(make_fixture)"
seed_pool_tree "$SRC"
SLACUBE_SYNC_SOURCE="$SRC/" SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool >/dev/null 2>&1

SLACUBE_SYNC_SOURCE="$SRC/" \
SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool >/dev/null 2>&1
# All source files must still be present.
n_src=$(find "$SRC" -type f | wc -l)
check $([[ $n_src -eq 6 ]] && echo 1 || echo 0) "default: source preserved (n=$n_src, expected 6)"
# raw/ files in source untouched.
check $([[ -f "$SRC/pool/raw/selftrigger_2026_01_01_00_00_00.h5" ]] && echo 1 || echo 0) "default: source raw/ preserved"
rm -rf "$ROOT"


# ---------------------------------------------------------- --delete-source deletes only eligible
echo
echo "[--delete-source: deletes only verified-matching files from source; never raw/; never flagged]"
eval "$(make_fixture)"
seed_pool_tree "$SRC"
SLACUBE_SYNC_SOURCE="$SRC/" SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool >/dev/null 2>&1
# Corrupt one DST file so it will be flagged. Size-preserving so
# rsync -a's size+mtime check does NOT overwrite it during the next
# pull; only the --checksum verify step sees the difference.
printf 'CORRUPT!' > "$DST/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5"
touch -r "$SRC/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5" \
  "$DST/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5"

SLACUBE_SYNC_SOURCE="$SRC/" \
SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool --delete-source >/dev/null 2>&1
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "--delete-source: exit 0"
# Three verified files gone from $SRC.
for f in selftrigger_2026_08_01_11_00_00.h5 selftrigger_2026_08_02_10_00_00.h5 pedestal_2026_08_01_09_00_00.h5; do
  path=$(find "$SRC" -name "$f" -type f)
  check $([[ -z "$path" ]] && echo 1 || echo 0) "--delete-source: $f removed from source"
done
# The flagged file (same name as corrupted DST) still in source.
check $([[ -f "$SRC/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5" ]] && echo 1 || echo 0) "--delete-source: flagged file retained in source"
# raw/ never deleted.
check $([[ -f "$SRC/pool/raw/selftrigger_2026_01_01_00_00_00.h5" ]] && echo 1 || echo 0) "--delete-source: raw/ preserved"
check $([[ -f "$SRC/pool/raw/some-other-thing.h5" ]] && echo 1 || echo 0) "--delete-source: raw/ preserved (other)"
rm -rf "$ROOT"

# ---------------------------------------------------------- SLACUBE_SYNC_SOURCE WITHOUT trailing slash
echo
echo "[no-trailing-slash: SLACUBE_SYNC_SOURCE without trailing slash still protects flagged file]"
# Regression: enumerate_source_files derived relative paths by stripping
# SOURCE's trailing slash, and flagged_set's keys come from rsync's
# itemize output whose relative-path namespace only matches when SOURCE
# ends in '/'. If SLACUBE_SYNC_SOURCE is set WITHOUT a trailing slash,
# every flagged_set lookup silently misses, making every source file
# (including genuinely flagged-differing ones) eligible for deletion
# under --delete-source -- violating the invariant. Source MUST be
# normalized so that --delete-source never deletes a flagged file.
eval "$(make_fixture)"
seed_pool_tree "$SRC"
# Initial pull with trailing slash so files land at $DST/pool/...
# (same setup as the other tests). The regression condition is the
# NEXT invocation, which uses SLACUBE_SYNC_SOURCE WITHOUT a trailing
# slash together with --delete-source.
SLACUBE_SYNC_SOURCE="$SRC/" SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool >/dev/null 2>&1
# Size-preserving corruption so rsync -a's size+mtime check does NOT
# overwrite the corruption during the next pull; only the --checksum
# verify step sees the difference.
printf 'CORRUPT!' > "$DST/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5"
touch -r "$SRC/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5" \
  "$DST/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5"

# NOTE: $SRC (no trailing slash) -- the regression condition.
SLACUBE_SYNC_SOURCE="$SRC" \
SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool --delete-source >/dev/null 2>&1
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "no-trailing-slash: --delete-source: exit 0"
check $([[ -f "$SRC/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_10_00_00.h5" ]] && echo 1 || echo 0) "no-trailing-slash: flagged file retained in source"
# Other verified files should still have been deleted (the fix must
# not break the normal --delete-source path).
check $([[ ! -e "$SRC/pool/selftrigger/2026/2026-08-01/selftrigger_2026_08_01_11_00_00.h5" ]] && echo 1 || echo 0) "no-trailing-slash: non-flagged file deleted from source"
check $([[ -f "$SRC/pool/raw/selftrigger_2026_01_01_00_00_00.h5" ]] && echo 1 || echo 0) "no-trailing-slash: raw/ preserved"
rm -rf "$ROOT"


# ---------------------------------------------------------- --help shows default alias and usage
echo
echo "[--help: shows default alias and usage]"
out=$(slacube-sync-pool --help 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "help: exit 0"
echo "$out" | grep -q 'slacube-daq-pull' && check 1 "help: shows default alias slacube-daq-pull" || check 0 "help: shows default alias slacube-daq-pull"
echo "$out" | grep -q 'SLACUBE_SYNC_SOURCE' && check 1 "help: mentions SLACUBE_SYNC_SOURCE env var" || check 0 "help: mentions SLACUBE_SYNC_SOURCE env var"
echo "$out" | grep -q 'delete-source' && check 1 "help: mentions --delete-source flag" || check 0 "help: mentions --delete-source flag"


# ---------------------------------------------------------- --verbose lists file-level detail
echo
echo "[--verbose: prints per-file detail beyond the one-line summary]"
eval "$(make_fixture)"
seed_pool_tree "$SRC"
out=$(SLACUBE_SYNC_SOURCE="$SRC/" \
SLACUBE_SYNC_DEST="$DST" \
  slacube-sync-pool --verbose 2>&1)
# Verbose output should include filenames under pool/.
echo "$out" | grep -q 'selftrigger_2026_08_01_10_00_00' && check 1 "verbose: per-file detail (selftrigger)" || check 0 "verbose: per-file detail (selftrigger)"
# And the one-line summary is still present.
echo "$out" | grep -E '^slacube-sync-pool: pulled=' | grep -q 'pulled=4' && check 1 "verbose: summary still present" || check 0 "verbose: summary still present"
rm -rf "$ROOT"
 
 # ---------------------------------------------------------- restricted remote source
echo
echo "[restricted remote source: report uses rsync only]"
eval "$(make_fixture)"
mkdir -p "$SRC/pool/selftrigger/2026/2026-08-01"
echo remote > "$SRC/pool/selftrigger/2026/2026-08-01/remote.h5"
fakebin=$(mktemp -d)
cat > "$fakebin/rsync" <<'RSYNC'
#!/usr/bin/env bash
set -u
if [[ "$*" == *--dry-run* ]]; then
  exit 0
fi
src="${@: -2:1}"; dst="${@: -1}"
src=${src#*:}
mkdir -p "$dst"
cp -a "$src"/. "$dst"/
printf '>f+++++++++ pool/selftrigger/2026/2026-08-01/remote.h5\n'
RSYNC
ssh_marker="$ROOT/ssh-called"
cat > "$fakebin/ssh" <<'SSH'
#!/usr/bin/env bash
touch "$SSH_MARKER"
exit 77
SSH
chmod +x "$fakebin/rsync" "$fakebin/ssh"
out=$(SSH_MARKER="$ssh_marker" PATH="$fakebin:$PATH" SLACUBE_SYNC_SOURCE="alias:$SRC/" SLACUBE_SYNC_DEST="$DST" slacube-sync-pool 2>&1)
rc=$?
check $([[ $rc -eq 0 ]] && echo 1 || echo 0) "restricted remote source: rsync-only report succeeds"
check $([[ ! -e "$ssh_marker" ]] && echo 1 || echo 0) "restricted remote source: no SSH enumeration"
rm -rf "$fakebin" "$ROOT"

echo
echo "[enumeration failure: fatal error]"
eval "$(make_fixture)"
fakebin=$(mktemp -d)
cat > "$fakebin/rsync" <<'RSYNC'
#!/usr/bin/env bash
exit 1
RSYNC
chmod +x "$fakebin/rsync"
out=$(PATH="$fakebin:$PATH" SLACUBE_SYNC_SOURCE="alias:/missing/" SLACUBE_SYNC_DEST="$DST" slacube-sync-pool 2>&1)
rc=$?
check $([[ $rc -eq 1 ]] && echo 1 || echo 0) "connection failure: fatal exit"
check $([[ "$out" == *"pull failed"* ]] && echo 1 || echo 0) "connection failure: clear fatal message"
rm -rf "$fakebin" "$ROOT"


# ---------------------------------------------------------- result
echo
echo "============================================================"
if [[ "$_failures" -ne 0 ]]; then
  echo "FAILED ($_failures)"
  exit 1
fi
echo "ALL PASSED"
exit 0
