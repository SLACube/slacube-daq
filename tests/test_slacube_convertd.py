#!/usr/bin/env python3
"""Test harness for bin/slacube-convertd.

This is a standalone test driver (no pytest required). It exercises the
daemon's importable library functions and the CLI subcommands against a
synthetic filesystem layout, using a PATH-shadowing fake
`slacube-convert-raw.py` so conversion does not require the real larpix
toolchain.

Run as:
    python3 tests/test_slacube_convertd.py
Exit code 0 on success, non-zero on failure.
"""

from __future__ import print_function

import contextlib
import errno
import fcntl
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import time as _time
import types
from datetime import datetime

# Load bin/slacube-convertd as a Python module (it has no .py extension).
HERE = os.path.dirname(os.path.abspath(__file__))
BIN_DIR = os.path.normpath(os.path.join(HERE, "..", "bin"))
_CONVERTD_PATH = os.path.join(BIN_DIR, "slacube-convertd")
import importlib.util as _importlib_util
import importlib.machinery as _importlib_machinery
_loader = _importlib_machinery.SourceFileLoader("slacube_convertd", _CONVERTD_PATH)
_spec = _importlib_util.spec_from_loader("slacube_convertd", _loader)
convertd = _importlib_util.module_from_spec(_spec)
_loader.exec_module(convertd)
SCRIPTS_DIR = os.path.normpath(os.path.join(HERE, "..", "scripts"))
if SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, SCRIPTS_DIR)
import _slacube_paths as shared_paths


# ---------------------------------------------------------------- helpers
_failures = []


def check(cond, msg):
    if cond:
        print("  PASS: " + msg)
    else:
        print("  FAIL: " + msg)
        _failures.append(msg)


@contextlib.contextmanager
def tmp_layout():
    root = tempfile.mkdtemp(prefix="slacube_test_")
    spool = os.path.join(root, "spool")
    dropbox = os.path.join(root, "dropbox")
    raw_cache = os.path.join(root, "raw_cache")
    workdir = os.path.join(root, "work")
    for d in (spool, dropbox, raw_cache, workdir):
        os.makedirs(d)
    for sub in ("incoming", "running", "failed", "done"):
        os.makedirs(os.path.join(spool, sub))
    try:
        yield {
            "root": root,
            "spool": spool,
            "dropbox": dropbox,
            "raw_cache": raw_cache,
            "workdir": workdir,
        }
    finally:
        shutil.rmtree(root, ignore_errors=True)


def write_fake_raw(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(b"FAKE_RAW\n")


def install_fake_converter(sleep_seconds=0.0, counter_path=None):
    """Replace PATH's view of `slacube-convert-raw.py` with a script that
    just copies input to output (or fails on demand, or sleeps).

    `sleep_seconds` makes the fake converter sleep that long between
    start and copyfile, so concurrent invocations can be observed by
    timing or by a shared counter (see `counter_path`).

    `counter_path`, if set, makes the fake converter on entry:
      1. flock a single file at <counter_path>
      2. read "in_flight peak"
      3. write "in_flight+1 max(peak,in_flight+1)"
      4. release the lock
      then sleep, copy, and (before exit) repeat steps 1-4 decrementing
    in_flight. Used by the concurrency test to prove peak in-flight count.

    Returns the directory holding the fake script. The caller is
    responsible for shutil.rmtree().
    """
    fake_dir = tempfile.mkdtemp(prefix="fake_conv_")
    script = os.path.join(fake_dir, "slacube-convert-raw.py")
    extra = ""
    if counter_path:
        # Single-file shared state: "in_flight peak". Atomically update
        # both via flock + read + write + release.
        extra = (
            "import os as _os, fcntl as _fcntl\n"
            "_ctr = %r\n"
            "_fd = _os.open(_ctr, _os.O_CREAT | _os.O_RDWR, 0o644)\n"
            "def _bump(delta):\n"
            "    while True:\n"
            "        try:\n"
            "            _fcntl.flock(_fd, _fcntl.LOCK_EX)\n"
            "            break\n"
            "        except OSError:\n"
            "            continue\n"
            "    _os.lseek(_fd, 0, 0)\n"
            "    _raw = _os.read(_fd, 1024).decode('utf-8', 'replace').strip()\n"
            "    parts = _raw.split() if _raw else ['0', '0']\n"
            "    cur = int(parts[0]); peak = int(parts[1])\n"
            "    cur += delta\n"
            "    if cur > peak:\n"
            "        peak = cur\n"
            "    _os.ftruncate(_fd, 0)\n"
            "    _os.lseek(_fd, 0, 0)\n"
            "    _os.write(_fd, ('%%d %%d\\n' %% (cur, peak)).encode('utf-8'))\n"
            "    _fcntl.flock(_fd, _fcntl.LOCK_UN)\n"
            "    return peak\n"
            "_peak_observed = _bump(+1)\n"
        ) % counter_path
    sleep_block = ""
    if sleep_seconds > 0:
        sleep_block = "import time as _time\n_t0 = _time.time()\nwhile _time.time() - _t0 < %r: pass\n" % sleep_seconds
    decrement = ""
    if counter_path:
        decrement = "_bump(-1)\n_os.close(_fd)\n"
    with open(script, "w") as fh:
        fh.write(
            "#!/usr/bin/env python3\n"
            "import sys, shutil, os\n"
            + extra +
            "args = sys.argv[1:]\n"
            "inp = out = fail = None\n"
            "i = 0\n"
            "while i < len(args):\n"
            "    a = args[i]\n"
            "    if a in ('--input_filename', '-i'):\n"
            "        inp = args[i+1]; i += 2\n"
            "    elif a in ('--output_filename', '-o'):\n"
            "        out = args[i+1]; i += 2\n"
            "    elif a == '--fail':\n"
            "        fail = True; i += 1\n"
            "    else:\n"
            "        i += 1\n"
            "if fail:\n"
            "    sys.stderr.write('forced fail\\n')\n"
            "    sys.exit(1)\n"
            "if not inp or not out:\n"
            "    sys.exit(2)\n"
            + sleep_block +
            "os.makedirs(os.path.dirname(out), exist_ok=True)\n"
            "shutil.copyfile(inp, out)\n"
            + decrement +
            "sys.exit(0)\n"
        )
    os.chmod(script, 0o755)
    return fake_dir


def run_cli(args, env_extra=None):
    """Invoke `slacube-convertd` as a subprocess. Returns (rc, stdout, stderr)."""
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    proc = subprocess.Popen(
        [sys.executable, os.path.join(BIN_DIR, "slacube-convertd")] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    out, err = proc.communicate()
    return proc.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")


# ============================================================== tests
print("=" * 60)
print("test_slacube_convertd")
print("=" * 60)


# ---------------------------------------------------------- classification
print("\n[classification]")

check(
    convertd.classify_basename("raw_2026_02_21_21_52_18.h5") == "selftrigger_",
    "raw_*.h5 -> selftrigger_",
)
check(
    convertd.classify_basename("pedestal_2026_02_21_21_52_18.h5") == "pedestal_",
    "pedestal_*.h5 -> pedestal_",
)
check(
    convertd.classify_basename("selftrigger_2026_02_21_21_52_18.h5") is None,
    "selftrigger_*.h5 -> None (already converted)",
)
check(
    convertd.classify_basename("garbage.h5") is None,
    "garbage.h5 -> None (unclassifiable)",
)

yr, dt = convertd.parse_year_date("raw_2026_02_21_21_52_18.h5")
check(yr == "2026" and dt == "2026-02-21", "parse year/date from raw_2026_02_21_21_52_18.h5")

print("\n[classification/date parity with shared path helpers]")
fixtures = (
    "raw_2026_02_21_21_52_18.h5",
    "pedestal_2026_02_21_21_52_18.h5",
    "archive_raw_2026_02_21_21_52_18.h5",
    "raw_bad_stamp.h5",
)
for basename in fixtures:
    converted = shared_paths.raw_basename_to_converted(basename)
    expected_prefix = None
    if converted is not None:
        expected_prefix = converted[:-len(basename.split("_", 1)[1])]
    check(convertd.classify_basename(basename) == expected_prefix,
          "classification agrees for %s" % basename)
    try:
        convertd_result = convertd.parse_year_date(basename)
    except ValueError:
        convertd_result = ValueError
    try:
        shared_result = shared_paths.parse_year_date(basename)
    except ValueError:
        shared_result = ValueError
    check(convertd_result == shared_result,
          "date parsing agrees for %s" % basename)

# ---------------------------------------------------------- submit / dedup
print("\n[submit & dedup]")

with tmp_layout() as L:
    raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
    write_fake_raw(raw)

    status, msg, out = convertd.submit(raw, L["spool"], L["dropbox"])
    check(status == "ok", "submit returns ok for new raw: %r" % ((status, msg, out),))
    job_name = "raw_2026_02_21_21_52_18"
    check(
        os.path.isfile(os.path.join(L["spool"], "incoming", job_name + ".json")),
        "incoming/<job>.json was written",
    )
    with open(os.path.join(L["spool"], "incoming", job_name + ".json")) as fh:
        rec = json.load(fh)
    check(rec["raw"] == raw, "record.raw == submitted path")
    check(rec["attempts"] == 0, "record.attempts == 0")
    check(rec["out"].endswith("selftrigger_2026_02_21_21_52_18.h5"), "record.out ends with selftrigger_*")
    check(rec["out"].startswith(L["dropbox"]), "record.out lands under dropbox")

    # Duplicate
    status2, msg2, _ = convertd.submit(raw, L["spool"], L["dropbox"])
    check(status2 == "duplicate", "submit returns duplicate for resubmit: %r" % (msg2,))

# ---------------------------------------------------------- unclassifiable
print("\n[unclassifiable basename]")
with tmp_layout() as L:
    raw = os.path.join(L["workdir"], "garbage.h5")
    write_fake_raw(raw)
    status, msg, out = convertd.submit(raw, L["spool"], L["dropbox"])
    check(status == "unclassifiable", "submit returns unclassifiable for garbage.h5: %r" % (msg,))
    job_name = "garbage"
    check(
        os.path.isfile(os.path.join(L["spool"], "failed", job_name + ".json")),
        "unclassifiable job lands in failed/ immediately",
    )
    with open(os.path.join(L["spool"], "failed", job_name + ".json")) as fh:
        rec = json.load(fh)
    check(rec.get("last_error") == "unclassifiable", "unclassifiable record has last_error='unclassifiable'")

# ---------------------------------------------------------- status counts
print("\n[status & exit codes]")
with tmp_layout() as L:
    s = convertd.compute_status(L["spool"], max_consecutive=3)
    check(s["counts"]["pending"] == 0 and s["counts"]["running"] == 0
          and s["counts"]["failed"] == 0 and s["counts"]["done"] == 0,
          "empty spool: all counts zero: %r" % (s,))
    check(s["consecutive_fail"] == 0, "empty spool: consecutive_fail == 0")
    check(s["exit_code"] == 0, "empty spool: exit_code == 0")

    # Add an unclassifiable -> 1 failed
    raw = os.path.join(L["workdir"], "garbage.h5")
    write_fake_raw(raw)
    convertd.submit(raw, L["spool"], L["dropbox"])
    s = convertd.compute_status(L["spool"], max_consecutive=3)
    check(s["counts"]["failed"] == 1, "1 failed: failed count == 1: %r" % (s,))
    check(s["consecutive_fail"] == 1, "1 failed, 0 done: consecutive_fail == 1")
    check(s["exit_code"] == 2, "1 failed but below threshold: exit_code == 2")

    # Add 2 more failures -> 3 total, threshold reached
    for nm in ("raw_a", "raw_b"):
        rec = {
            "raw": "/nonexistent/raw_" + nm + ".h5",
            "submitted": "2026-02-21T00:00:00",
            "attempts": 3,
            "not_before": None,
            "last_error": "boom",
            "pid": None,
            "started": None,
            "finished": "2026-02-21T00:00:10",
            "duration_s": 1.0,
            "out": "/tmp/out_" + nm + ".h5",
        }
        convertd.atomic_write_json(os.path.join(L["spool"], "failed", nm + ".json"), rec)
    s = convertd.compute_status(L["spool"], max_consecutive=3)
    check(s["counts"]["failed"] == 3, "3 failed total: %r" % (s,))
    check(s["consecutive_fail"] == 3, "3 failed consecutive (no done): consecutive_fail == 3")
    check(s["exit_code"] == 1, "consecutive_fail >= threshold: exit_code == 1")

    # Add a done record older than all the failures
    done_rec = {
        "raw": "/none/raw_old.h5",
        "submitted": "2026-01-01T00:00:00",
        "attempts": 0,
        "not_before": None,
        "last_error": None,
        "pid": None,
        "started": None,
        "finished": "2026-01-01T00:00:10",
        "duration_s": 1.0,
        "out": "/tmp/out_old.h5",
    }
    convertd.atomic_write_json(os.path.join(L["spool"], "done", "raw_old.json"), done_rec)
    s = convertd.compute_status(L["spool"], max_consecutive=3)
    # All 3 failures are newer than the done record -> consecutive_fail still 3
    check(s["consecutive_fail"] == 3, "failures newer than done: consecutive_fail still 3")

    # Add a newer done record -> resets consecutive_fail to 0
    done_rec2 = dict(done_rec)
    done_rec2["finished"] = "2030-01-01T00:00:10"
    convertd.atomic_write_json(os.path.join(L["spool"], "done", "raw_new.json"), done_rec2)
    s = convertd.compute_status(L["spool"], max_consecutive=3)
    check(s["consecutive_fail"] == 0, "done newer than all failed: consecutive_fail == 0")
    check(s["exit_code"] == 2, "failed non-empty but no consecutive failures: exit_code == 2")


# ---------------------------------------------------------- claim
print("\n[claim]")
with tmp_layout() as L:
    raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
    write_fake_raw(raw)
    convertd.submit(raw, L["spool"], L["dropbox"])
    claimed = convertd.claim_job(L["spool"], "raw_2026_02_21_21_52_18")
    check(claimed == os.path.join(L["spool"], "running", "raw_2026_02_21_21_52_18.json"),
          "claim moves incoming -> running: %r" % (claimed,))
    # Second claim returns None
    again = convertd.claim_job(L["spool"], "raw_2026_02_21_21_52_18")
    check(again is None, "second claim returns None")

# ---------------------------------------------------------- process happy
print("\n[process happy path]")
with tmp_layout() as L:
    fake_dir = install_fake_converter()
    saved_path = os.environ.get("PATH", "")
    os.environ["PATH"] = fake_dir + os.pathsep + saved_path
    try:
        raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
        write_fake_raw(raw)
        convertd.submit(raw, L["spool"], L["dropbox"])
        running = convertd.claim_job(L["spool"], "raw_2026_02_21_21_52_18")
        outcome, rec = convertd.process_job(running, L["dropbox"], L["raw_cache"], L["workdir"])
        check(outcome == "ok", "process returns ok: %r" % (outcome,))
        # record moved to done/
        check(os.path.isfile(os.path.join(L["spool"], "done", "raw_2026_02_21_21_52_18.json")),
              "record moved to done/")
        # converted file in dropbox
        out_name = "selftrigger_2026_02_21_21_52_18.h5"
        check(os.path.isfile(os.path.join(L["dropbox"], out_name)),
              "converted file in dropbox: %s" % out_name)
        # raw in cache under year/date
        check(os.path.isfile(os.path.join(L["raw_cache"], "2026", "2026-02-21",
                                          "raw_2026_02_21_21_52_18.h5")),
              "raw in cache under 2026/2026-02-21/")
        # no leftover .part
        check(not any(n.startswith(".") for n in os.listdir(L["dropbox"])),
              "no dotfiles in dropbox (no .part leftovers)")
        # record has finished/duration_s
        with open(os.path.join(L["spool"], "done", "raw_2026_02_21_21_52_18.json")) as fh:
            done_rec = json.load(fh)
        check(done_rec["finished"] is not None, "done record has finished: %r" % (done_rec["finished"],))
        check(done_rec["duration_s"] is not None and done_rec["duration_s"] >= 0,
              "done record has duration_s: %r" % (done_rec["duration_s"],))
    finally:
        os.environ["PATH"] = saved_path
        shutil.rmtree(fake_dir, ignore_errors=True)


# ---------------------------------------------------------- process failure
print("\n[process failure path (forced converter failure)]")
with tmp_layout() as L:
    fake_dir = install_fake_converter()
    saved_path = os.environ.get("PATH", "")
    os.environ["PATH"] = fake_dir + os.pathsep + saved_path
    try:
        # Force process_job to pass --fail
        raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
        write_fake_raw(raw)
        convertd.submit(raw, L["spool"], L["dropbox"])
        running = convertd.claim_job(L["spool"], "raw_2026_02_21_21_52_18")
        # Use a wrapper that injects --fail
        outcome, rec = convertd.process_job(
            running, L["dropbox"], L["raw_cache"], L["workdir"],
            extra_args=["--fail"],
        )
        check(outcome == "fail", "process returns fail when converter exits 1: %r" % (outcome,))
        # raw untouched
        check(os.path.isfile(raw), "raw is untouched after failure")
        # .part files cleaned
        check(not any(n.startswith(".") for n in os.listdir(os.path.dirname(raw))),
              "no .part leftovers in raw's directory")
        check(not os.path.isfile(os.path.join(L["dropbox"], ".selftrigger_2026_02_21_21_52_18.h5.part")),
              "no .part in dropbox after failure")
        # record moved to incoming/ with attempts incremented (D2 retry path)
        incoming_path = os.path.join(L["spool"], "incoming", "raw_2026_02_21_21_52_18.json")
        check(os.path.isfile(incoming_path), "failed-but-retryable record moved to incoming/")
        check(not os.path.isfile(running), "running/ record removed on retry path")
        with open(incoming_path) as fh:
            rec_running = json.load(fh)
        check(rec_running["attempts"] == 1, "attempts incremented: %r" % (rec_running["attempts"],))
        check(rec_running["last_error"] not in (None, ""), "last_error set: %r" % (rec_running["last_error"],))
        check(rec_running["not_before"] is not None, "not_before set on retry: %r" % (rec_running["not_before"],))
        check(rec_running["finished"] is None, "finished is None while still retrying")
    finally:
        os.environ["PATH"] = saved_path
        shutil.rmtree(fake_dir, ignore_errors=True)


# ---------------------------------------------------------- attempts exhausted -> failed
print("\n[attempts exhausted -> failed]")
with tmp_layout() as L:
    # Manually create a job at attempts == 2 so one more failure pushes it to failed/
    rec = {
        "raw": "/nonexistent/raw_2026_02_21_21_52_18.h5",
        "submitted": "2026-02-21T00:00:00",
        "attempts": 2,
        "not_before": None,
        "last_error": "previous",
        "pid": None,
        "started": None,
        "finished": None,
        "duration_s": None,
        "out": os.path.join(L["dropbox"], "selftrigger_2026_02_21_21_52_18.h5"),
    }
    # Actually, process_job needs the raw file to exist for requeue etc. Use a real raw.
    raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
    write_fake_raw(raw)
    rec["raw"] = raw
    convertd.atomic_write_json(os.path.join(L["spool"], "running", "raw_2026_02_21_21_52_18.json"), rec)
    fake_dir = install_fake_converter()
    saved_path = os.environ.get("PATH", "")
    os.environ["PATH"] = fake_dir + os.pathsep + saved_path
    try:
        running = os.path.join(L["spool"], "running", "raw_2026_02_21_21_52_18.json")
        outcome, rec2 = convertd.process_job(
            running, L["dropbox"], L["raw_cache"], L["workdir"],
            extra_args=["--fail"],
        )
        check(outcome == "fail", "still fail outcome: %r" % (outcome,))
        # After failure with attempts=2 -> exhausted -> moved to failed/
        check(os.path.isfile(os.path.join(L["spool"], "failed", "raw_2026_02_21_21_52_18.json")),
              "exhausted attempts -> record in failed/")
        check(not os.path.isfile(os.path.join(L["spool"], "incoming", "raw_2026_02_21_21_52_18.json")),
              "no record requeued to incoming/")
        check(not os.path.isfile(os.path.join(L["spool"], "running", "raw_2026_02_21_21_52_18.json")),
              "no record left in running/")
        # raw untouched
        check(os.path.isfile(raw), "raw untouched after attempts exhausted")
        with open(os.path.join(L["spool"], "failed", "raw_2026_02_21_21_52_18.json")) as fh:
            rec_failed = json.load(fh)
        check(rec_failed["attempts"] == 3, "attempts == 3 (default max): %r" % (rec_failed["attempts"],))
        check(rec_failed["finished"] is not None, "finished timestamp set")
        check(rec_failed["duration_s"] is not None, "duration_s set")
    finally:
        os.environ["PATH"] = saved_path
        shutil.rmtree(fake_dir, ignore_errors=True)


# ---------------------------------------------------------- crash recovery
print("\n[crash recovery: re-queue running/ on daemon start]")
with tmp_layout() as L:
    raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
    write_fake_raw(raw)
    # Simulate: job in running/, attempts=0
    rec = {
        "raw": raw,
        "submitted": "2026-02-21T00:00:00",
        "attempts": 0,
        "not_before": None,
        "last_error": None,
        "pid": 1234,
        "started": "2026-02-21T00:00:01",
        "finished": None,
        "duration_s": None,
        "out": os.path.join(L["dropbox"], "selftrigger_2026_02_21_21_52_18.h5"),
    }
    convertd.atomic_write_json(os.path.join(L["spool"], "running", "raw_2026_02_21_21_52_18.json"), rec)
    # Simulate a leftover .part in dropbox
    leftover = os.path.join(L["dropbox"], ".selftrigger_2026_02_21_21_52_18.h5.part")
    open(leftover, "w").close()

    convertd.requeue_running(L["spool"], L["workdir"])
    check(os.path.isfile(os.path.join(L["spool"], "incoming", "raw_2026_02_21_21_52_18.json")),
          "recovered job moved back to incoming/")
    check(not os.path.isfile(os.path.join(L["spool"], "running", "raw_2026_02_21_21_52_18.json")),
          "no record left in running/")
    check(not os.path.exists(leftover), "leftover .part deleted")
    with open(os.path.join(L["spool"], "incoming", "raw_2026_02_21_21_52_18.json")) as fh:
        rec2 = json.load(fh)
    check(rec2["attempts"] == 1, "attempts incremented: %r" % (rec2["attempts"],))
    check(rec2["last_error"] == "interrupted", "last_error == 'interrupted'")


# ---------------------------------------------------------- retry & ack
print("\n[retry & ack]")
with tmp_layout() as L:
    raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
    write_fake_raw(raw)
    convertd.submit(raw, L["spool"], L["dropbox"])
    # Move to failed by submitting unclassifiable
    raw2 = os.path.join(L["workdir"], "garbage.h5")
    write_fake_raw(raw2)
    convertd.submit(raw2, L["spool"], L["dropbox"])  # ends in failed/

    # retry: move failed/garbage.json -> incoming/garbage.json
    convertd.retry(L["spool"], "garbage")
    check(os.path.isfile(os.path.join(L["spool"], "incoming", "garbage.json")),
          "retry moves failed -> incoming")
    check(not os.path.isfile(os.path.join(L["spool"], "failed", "garbage.json")),
          "retry removes from failed/")
    with open(os.path.join(L["spool"], "incoming", "garbage.json")) as fh:
        rec = json.load(fh)
    check(rec["attempts"] == 0, "retry resets attempts to 0")
    check(rec["last_error"] is None, "retry resets last_error to None")

    # ack: failed job -> done with outcome=acked
    raw3 = os.path.join(L["workdir"], "weird.h5")
    write_fake_raw(raw3)
    convertd.submit(raw3, L["spool"], L["dropbox"])  # goes to failed/
    convertd.ack(L["spool"], "weird")
    check(os.path.isfile(os.path.join(L["spool"], "done", "weird.json")),
          "ack moves failed -> done")
    with open(os.path.join(L["spool"], "done", "weird.json")) as fh:
        rec = json.load(fh)
    check(rec.get("outcome") == "acked", "ack adds outcome='acked'")


# ---------------------------------------------------------- flock
print("\n[flock exclusivity]")
with tmp_layout() as L:
    # Hold a lock manually
    lock_path = os.path.join(L["spool"], ".daemon.lock")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        rc, _, err = run_cli(["serve", "--once"],
                             env_extra={"SLACUBE_SPOOL": L["spool"]})
        check(rc != 0, "second instance refused while flock held: rc=%d err=%r" % (rc, err))
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


# ---------------------------------------------------------- drain
print("\n[drain]")
with tmp_layout() as L:
    # Initially empty: drain should return quickly
    t0 = time.time()
    convertd.drain(L["spool"], poll_interval=0.05, timeout=5.0)
    elapsed = time.time() - t0
    check(elapsed < 2.0, "drain on empty spool returns quickly (%.2fs)" % elapsed)


# ---------------------------------------------------------- CLI: serve --once end-to-end
print("\n[CLI: serve --once end-to-end]")
with tmp_layout() as L:
    fake_dir = install_fake_converter()
    saved_path = os.environ.get("PATH", "")
    os.environ["PATH"] = fake_dir + os.pathsep + saved_path
    try:
        raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
        write_fake_raw(raw)
        # Submit via CLI
        rc, out, err = run_cli(
            ["submit", raw],
            env_extra={
                "SLACUBE_SPOOL": L["spool"],
                "SLACUBE_DROPBOX": L["dropbox"],
                "SLACUBE_RAW_CACHE": L["raw_cache"],
                "SLACUBE_WORKDIR": L["workdir"],
            },
        )
        check(rc == 0, "CLI submit ok: rc=%d out=%r err=%r" % (rc, out, err))
        # Serve --once
        rc, out, err = run_cli(
            ["serve", "--once"],
            env_extra={
                "SLACUBE_SPOOL": L["spool"],
                "SLACUBE_DROPBOX": L["dropbox"],
                "SLACUBE_RAW_CACHE": L["raw_cache"],
                "SLACUBE_WORKDIR": L["workdir"],
                "SLACUBE_CONVERT_POLL": "0.1",
            },
        )
        check(rc == 0, "CLI serve --once ok: rc=%d out=%r err=%r" % (rc, out, err))
        check(os.path.isfile(os.path.join(L["spool"], "done", "raw_2026_02_21_21_52_18.json")),
              "after serve --once: record in done/")
        check(os.path.isfile(os.path.join(L["dropbox"], "selftrigger_2026_02_21_21_52_18.h5")),
              "after serve --once: converted file in dropbox")
        check(os.path.isfile(os.path.join(L["raw_cache"], "2026", "2026-02-21",
                                          "raw_2026_02_21_21_52_18.h5")),
              "after serve --once: raw in cache")
    finally:
        os.environ["PATH"] = saved_path
        shutil.rmtree(fake_dir, ignore_errors=True)


# ---------------------------------------------------------- G2: workdir fallback is per-daemon
print("\n[G2: cmd_serve workdir fallback is $SLACUBE_SPOOL/.work, not dirname(spool)]")
with tmp_layout() as L:
    saved = {}
    for k in ("SLACUBE_SPOOL", "SLACUBE_DROPBOX", "SLACUBE_RAW_CACHE", "SLACUBE_WORKDIR"):
        saved[k] = os.environ.pop(k, None)
    os.environ["SLACUBE_SPOOL"] = L["spool"]
    os.environ["SLACUBE_DROPBOX"] = L["dropbox"]
    os.environ["SLACUBE_RAW_CACHE"] = L["raw_cache"]
    # SLACUBE_WORKDIR deliberately left unset -- this is the fallback case.
    try:
        args = types.SimpleNamespace(once=True)
        convertd.cmd_serve(args, os.environ)
        fallback = os.path.join(L["spool"], ".work")
        check(os.path.isdir(fallback),
              "cmd_serve creates $SLACUBE_SPOOL/.work when SLACUBE_WORKDIR is unset")
        shared_parent_work = os.path.join(os.path.dirname(L["spool"]), ".work")
        check(not os.path.isdir(shared_parent_work),
              "fallback is not dirname(spool)/.work (the pre-fix shared location)")
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


# ---------------------------------------------------------- G3: refuse cross-device workdir/raw_cache
print("\n[G3: cmd_serve refuses when workdir and raw_cache are on different devices]")
with tmp_layout() as L:
    raised = False
    try:
        convertd._check_same_device(L["workdir"], L["raw_cache"])
    except convertd.ConvertdError:
        raised = True
    check(not raised, "same-device workdir/raw_cache passes the G3 check")

    # Two real filesystems are not guaranteed in a test sandbox, so the
    # differing-device case is exercised by monkeypatching os.stat to
    # report distinct st_dev values for the two paths under test.
    real_stat = convertd.os.stat

    class _FakeStatResult(object):
        def __init__(self, st_dev):
            self.st_dev = st_dev

    def _fake_stat(path, *a, **kw):
        if path == L["workdir"]:
            return _FakeStatResult(1)
        if path == L["raw_cache"]:
            return _FakeStatResult(2)
        return real_stat(path, *a, **kw)

    convertd.os.stat = _fake_stat
    try:
        raised = False
        msg = ""
        try:
            convertd._check_same_device(L["workdir"], L["raw_cache"])
        except convertd.ConvertdError as exc:
            raised = True
            msg = str(exc)
        check(raised, "different-device workdir/raw_cache refuses (ConvertdError)")
        check(raised and L["workdir"] in msg and L["raw_cache"] in msg,
              "refusal names both paths: %r" % (msg,))
    finally:
        convertd.os.stat = real_stat


# ---------------------------------------------------------- CLI: status text and --json
print("\n[CLI: status text and --json]")
with tmp_layout() as L:
    raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
    write_fake_raw(raw)
    convertd.submit(raw, L["spool"], L["dropbox"])

    rc, out, err = run_cli(
        ["status"],
        env_extra={"SLACUBE_SPOOL": L["spool"],
                   "SLACUBE_DROPBOX": L["dropbox"]},
    )
    # pending=1 running=0 failed=0 done=0
    check(rc == 0, "status rc == 0 on pending-only: rc=%d out=%r" % (rc, out))
    check("pending=1" in out, "status text contains pending=1: %r" % (out,))
    check("running=0" in out, "status text contains running=0: %r" % (out,))
    check("failed=0" in out, "status text contains failed=0: %r" % (out,))
    check("done=0" in out, "status text contains done=0: %r" % (out,))
    check("consecutive_fail=0" in out, "status text contains consecutive_fail=0: %r" % (out,))

    rc, out, err = run_cli(
        ["status", "--json"],
        env_extra={"SLACUBE_SPOOL": L["spool"],
                   "SLACUBE_DROPBOX": L["dropbox"]},
    )
    check(rc == 0, "status --json rc == 0")
    j = json.loads(out)
    check(j.get("pending") == 1, "status --json pending == 1: %r" % (j,))
    check(j.get("running") == 0 and j.get("failed") == 0 and j.get("done") == 0,
          "status --json other counts zero")
    check(j.get("consecutive_fail") == 0, "status --json consecutive_fail == 0")


# ---------------------------------------------------------- CLI: retry/ack/drain via subprocess
print("\n[CLI: retry/ack/drain]")
with tmp_layout() as L:
    raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
    write_fake_raw(raw)
    # Inject a failed record directly via convertd module
    convertd.atomic_write_json(os.path.join(L["spool"], "failed", "raw_2026_02_21_21_52_18.json"),
                               {"raw": raw, "submitted": "2026-02-21T00:00:00",
                                "attempts": 3, "not_before": None, "last_error": "x",
                                "pid": None, "started": None, "finished": "2026-02-21T00:00:10",
                                "duration_s": 1.0,
                                "out": os.path.join(L["dropbox"], "selftrigger_2026_02_21_21_52_18.h5")})
    rc, out, err = run_cli(["retry", "raw_2026_02_21_21_52_18"],
                           env_extra={"SLACUBE_SPOOL": L["spool"]})
    check(rc == 0 and os.path.isfile(os.path.join(L["spool"], "incoming",
                                                  "raw_2026_02_21_21_52_18.json")),
          "CLI retry moves failed -> incoming")

    # Move it back to failed
    os.rename(os.path.join(L["spool"], "incoming", "raw_2026_02_21_21_52_18.json"),
              os.path.join(L["spool"], "failed", "raw_2026_02_21_21_52_18.json"))
    rc, out, err = run_cli(["ack", "raw_2026_02_21_21_52_18"],
                           env_extra={"SLACUBE_SPOOL": L["spool"]})
    check(rc == 0 and os.path.isfile(os.path.join(L["spool"], "done",
                                                  "raw_2026_02_21_21_52_18.json")),
          "CLI ack moves failed -> done")


# ---------------------------------------------------------- CLI: install refuses without a site file (G1)
print("\n[G1: install refuses when the site file does not exist]")
with tmp_layout() as L:
    xdg = os.path.join(L["root"], "xdg")
    rc, out, err = run_cli(
        ["install"],
        env_extra={
            "HOME": L["root"],
            "SLACUBE_SPOOL": L["spool"],
            "SLACUBE_DROPBOX": L["dropbox"],
            "XDG_CONFIG_HOME": xdg,
            "PATH": "/usr/bin:/bin",
        },
    )
    check(rc == 1, "install refuses with no site file: rc=%d out=%r err=%r" % (rc, out, err))
    check("error:" in err and ".slacube-site.sh" in err,
          "install names the missing site file: %r" % (err,))
    unit_path = os.path.join(xdg, "systemd", "user", "slacube-convert.service")
    check(not os.path.isfile(unit_path),
          "no unit file written when the site file is missing")


# ---------------------------------------------------------- CLI: install/uninstall dry-run checks
print("\n[CLI: install writes unit file with substituted site-file path]")
with tmp_layout() as L:
    site_file = os.path.join(L["root"], "site.sh")
    with open(site_file, "w") as fh:
        fh.write("# fake site file for tests\n")
    rc, out, err = run_cli(
        ["install"],
        env_extra={
            "HOME": L["root"],
            "SLACUBE_SPOOL": L["spool"],
            "SLACUBE_DROPBOX": L["dropbox"],
            "SLACUBE_SITE_FILE": site_file,
            "XDG_CONFIG_HOME": os.path.join(L["root"], "xdg"),
            "PATH": "/usr/bin:/bin",
        },
    )
    # The unit-file write should succeed; systemctl calls may fail in this sandbox
    # The actual path is printed to stdout as `wrote <path> (site file: <site_file>)`.
    unit = None
    for line in out.splitlines():
        if line.startswith("wrote "):
            unit = line[len("wrote "):].split(" (site file:")[0].strip()
            break
    check(unit is not None and os.path.isfile(unit),
          "install wrote unit file: %r (rc=%d err=%r)" % (unit, rc, err))
    check(site_file in out, "install prints the resolved site file on success: %r" % (out,))
    with open(unit) as fh:
        content = fh.read()
    check("slacube-convertd serve" in content, "unit file references slacube-convertd serve")
    check(site_file in content, "unit file has the configured site file")


# ---------------------------------------------------------- concurrency (finding 2)
# Submit N jobs with a slow converter; with workers=K, multiple jobs must
# overlap. Verify via timing: K * sleep_time per job if serial, ~ sleep_time
# total if fully concurrent.
print("\n[concurrency: SLACUBE_CONVERT_WORKERS > 1 dispatches in parallel]")
with tmp_layout() as L:
    counter_path = os.path.join(L["root"], "ctr")
    open(counter_path, "w").close()
    n_jobs = 4
    sleep_s = 0.5
    fake_dir = install_fake_converter(sleep_seconds=sleep_s, counter_path=counter_path)
    saved_path = os.environ.get("PATH", "")
    os.environ["PATH"] = fake_dir + os.pathsep + saved_path
    try:
        names = []
        for i in range(n_jobs):
            nm = "raw_2026_02_21_%02d_%02d_%02d" % (i, i, i)
            raw = os.path.join(L["workdir"], nm + ".h5")
            write_fake_raw(raw)
            convertd.submit(raw, L["spool"], L["dropbox"])
            names.append(nm)
        workers = 4
        t0 = time.time()
        rc, out, err = run_cli(
            ["serve", "--once"],
            env_extra={
                "SLACUBE_SPOOL": L["spool"],
                "SLACUBE_DROPBOX": L["dropbox"],
                "SLACUBE_RAW_CACHE": L["raw_cache"],
                "SLACUBE_WORKDIR": L["workdir"],
                "SLACUBE_CONVERT_WORKERS": str(workers),
                "SLACUBE_CONVERT_POLL": "0.1",
            },
        )
        elapsed = time.time() - t0
        check(rc == 0, "serve --once with workers=%d ok: rc=%d err=%r" % (workers, rc, err))
        # All jobs completed (sleep_s * n_jobs if fully serial -> ~2s).
        # Fully parallel (workers == n_jobs) -> ~sleep_s -> ~0.5s.
        serial_lower = sleep_s * n_jobs * 0.5  # halfway between serial and parallel
        check(
            elapsed < serial_lower,
            "serve --once with %d workers of %d overlapping jobs finished in %.2fs (< %.2fs = half-serial lower bound)"
            % (workers, n_jobs, elapsed, serial_lower),
        )
        # Peak concurrent counter from the fake converter: must reach >= 2.
        with open(counter_path) as fh:
            raw = fh.read().strip().split()
        cur = int(raw[0]) if len(raw) >= 1 else 0
        peak = int(raw[1]) if len(raw) >= 2 else 0
        check(cur == 0, "all converter processes decremented before exit: cur=%d" % cur)
        check(peak >= 2, "shared counter proves concurrency: peak=%d (>=2)" % peak)
        # All jobs landed in done/
        done_count = len([f for f in os.listdir(os.path.join(L["spool"], "done"))
                          if f.endswith(".json")])
        check(done_count == n_jobs,
              "all %d jobs ended in done/ (got %d)" % (n_jobs, done_count))
    finally:
        os.environ["PATH"] = saved_path
        shutil.rmtree(fake_dir, ignore_errors=True)


# ---------------------------------------------------------- workers cap
# With workers=2 and 4 jobs each sleeping 0.5s, peak concurrent in-flight
# converter calls must be <= 2 (the semaphore bounds concurrency).
print("\n[concurrency: SLACUBE_CONVERT_WORKERS caps peak in-flight calls]")
with tmp_layout() as L:
    counter_path = os.path.join(L["root"], "ctr2")
    open(counter_path, "w").close()
    n_jobs = 4
    sleep_s = 0.5
    fake_dir = install_fake_converter(sleep_seconds=sleep_s, counter_path=counter_path)
    saved_path = os.environ.get("PATH", "")
    os.environ["PATH"] = fake_dir + os.pathsep + saved_path
    try:
        for i in range(n_jobs):
            nm = "raw_2026_03_21_%02d_%02d_%02d" % (i, i, i)
            raw = os.path.join(L["workdir"], nm + ".h5")
            write_fake_raw(raw)
            convertd.submit(raw, L["spool"], L["dropbox"])
        workers = 2
        rc, out, err = run_cli(
            ["serve", "--once"],
            env_extra={
                "SLACUBE_SPOOL": L["spool"],
                "SLACUBE_DROPBOX": L["dropbox"],
                "SLACUBE_RAW_CACHE": L["raw_cache"],
                "SLACUBE_WORKDIR": L["workdir"],
                "SLACUBE_CONVERT_WORKERS": str(workers),
                "SLACUBE_CONVERT_POLL": "0.1",
            },
        )
        check(rc == 0, "serve --once with workers=%d ok" % workers)
        with open(counter_path) as fh:
            raw = fh.read().strip().split()
        cur = int(raw[0]) if len(raw) >= 1 else 0
        peak = int(raw[1]) if len(raw) >= 2 else 0
        check(
            1 <= peak <= workers,
            "peak concurrent calls within [1, workers]: peak=%d workers=%d" % (peak, workers),
        )
        check(cur == 0, "all converter processes decremented before exit: cur=%d" % cur)
    finally:
        os.environ["PATH"] = saved_path
        shutil.rmtree(fake_dir, ignore_errors=True)




# ---------------------------------------------------------- not_before backoff (finding 3)
# A failed job is moved to incoming/ with not_before set in the future.
# A subsequent serve --once must NOT claim it. After waiting past
# not_before, a subsequent serve --once MUST claim it.
print("\n[not_before: failed job NOT reclaimed before backoff window]")
with tmp_layout() as L:
    fake_dir = install_fake_converter()
    saved_path = os.environ.get("PATH", "")
    os.environ["PATH"] = fake_dir + os.pathsep + saved_path
    try:
        # Submit + claim + force-fail so process_job writes
        # rec.not_before = now + 2^1 = 2 minutes from now (default backoff).
        raw = os.path.join(L["workdir"], "raw_2026_02_21_21_52_18.h5")
        write_fake_raw(raw)
        convertd.submit(raw, L["spool"], L["dropbox"])
        running = convertd.claim_job(L["spool"], "raw_2026_02_21_21_52_18")
        outcome, rec = convertd.process_job(
            running, L["dropbox"], L["raw_cache"], L["workdir"],
            extra_args=["--fail"],
        )
        check(outcome == "fail", "force-fail yields fail outcome")
        # After failure with attempts=1, the job is requeued to incoming/
        # with not_before set to now + 2 minutes.
        inc_path = os.path.join(L["spool"], "incoming", "raw_2026_02_21_21_52_18.json")
        check(os.path.isfile(inc_path), "failed-retryable record moved back to incoming/")
        with open(inc_path) as fh:
            rec = json.load(fh)
        check(rec.get("not_before") is not None,
              "not_before set on retry: %r" % (rec.get("not_before"),))
        # First serve --once: job is in the backoff window -> NOT claimed
        rc, out, err = run_cli(
            ["serve", "--once"],
            env_extra={
                "SLACUBE_SPOOL": L["spool"],
                "SLACUBE_DROPBOX": L["dropbox"],
                "SLACUBE_RAW_CACHE": L["raw_cache"],
                "SLACUBE_WORKDIR": L["workdir"],
                "SLACUBE_CONVERT_WORKERS": "2",
                "SLACUBE_CONVERT_POLL": "0.1",
            },
        )
        check(rc == 0, "serve --once during backoff ok: rc=%d err=%r" % (rc, err))
        check(
            not os.path.isfile(os.path.join(L["spool"], "running", "raw_2026_02_21_21_52_18.json")),
            "job not claimed (backoff window): no entry in running/",
        )
        check(
            os.path.isfile(inc_path),
            "job still in incoming/ after backoff-skipped dispatch",
        )
        check(
            not os.path.isfile(os.path.join(L["spool"], "done", "raw_2026_02_21_21_52_18.json")),
            "job not yet completed (backoff honored)",
        )
        # Now rewrite the record's not_before to a point in the past and
        # re-run serve --once: the job MUST be claimed and completed.
        with open(inc_path) as fh:
            rec = json.load(fh)
        rec["not_before"] = "2000-01-01T00:00:00"
        convertd.atomic_write_json(inc_path, rec)
        rc, out, err = run_cli(
            ["serve", "--once"],
            env_extra={
                "SLACUBE_SPOOL": L["spool"],
                "SLACUBE_DROPBOX": L["dropbox"],
                "SLACUBE_RAW_CACHE": L["raw_cache"],
                "SLACUBE_WORKDIR": L["workdir"],
                "SLACUBE_CONVERT_WORKERS": "2",
                "SLACUBE_CONVERT_POLL": "0.1",
            },
        )
        check(rc == 0, "serve --once after backoff expired ok: rc=%d err=%r" % (rc, err))
        check(
            os.path.isfile(os.path.join(L["spool"], "done", "raw_2026_02_21_21_52_18.json")),
            "job reclaimed after backoff window expired -> done/",
        )
    finally:
        os.environ["PATH"] = saved_path
        shutil.rmtree(fake_dir, ignore_errors=True)


# ---------------------------------------------------------- consecutive_failures > comparison (minor)
# With one done record and one failed record that ties its finished
# timestamp, the comparison must use '>' (newer than) so the failed
# record does NOT count toward consecutive_fail.
print("\n[consecutive_failures: uses '>' not '>=']")
with tmp_layout() as L:
    ts = "2026-02-21T00:00:10"
    done_rec = {
        "raw": "/none/raw_d.h5", "submitted": ts,
        "attempts": 0, "not_before": None, "last_error": None,
        "pid": None, "started": ts, "finished": ts, "duration_s": 0.0,
        "out": "/tmp/out_d.h5",
    }
    failed_rec = {
        "raw": "/none/raw_f.h5", "submitted": ts,
        "attempts": 3, "not_before": None, "last_error": "boom",
        "pid": None, "started": ts, "finished": ts, "duration_s": 0.0,
        "out": "/tmp/out_f.h5",
    }
    convertd.atomic_write_json(os.path.join(L["spool"], "done", "raw_d.json"), done_rec)
    convertd.atomic_write_json(os.path.join(L["spool"], "failed", "raw_f.json"), failed_rec)
    s = convertd.compute_status(L["spool"], max_consecutive=3)
    # The 'failed' finished equals (not strictly newer than) the done finished,
    # so it should NOT count toward consecutive_fail. With the '>=' bug, the
    # count would be 1; the corrected '>' gives 0.
    check(s["consecutive_fail"] == 0,
          "consecutive_fail == 0 when failed finished ties done finished: got %d"
          % s["consecutive_fail"])
    check(s["exit_code"] == 2,
          "exit_code == 2 (failed non-empty, no consecutive failures): got %d"
          % s["exit_code"])


# ---------------------------------------------------------- clean error: missing raw (minor)
# `submit <missing>` should print a clean error and exit 1 (was a Python
# traceback before the fix).
print("\n[CLI: submit missing raw -> clean error + exit 1]")
with tmp_layout() as L:
    rc, out, err = run_cli(
        ["submit", "/no/such/raw.h5"],
        env_extra={
            "SLACUBE_SPOOL": L["spool"],
            "SLACUBE_DROPBOX": L["dropbox"],
        },
    )
    check(rc == 1, "submit missing raw exits 1: rc=%d err=%r" % (rc, err))
    check("error:" in err and "not found" in err,
          "submit missing raw prints clean error to stderr: %r" % (err,))


# ---------------------------------------------------------- clean error: missing systemctl (minor)
# `install` with an empty PATH should print a clean error and exit 1
# (was an uncaught FileNotFoundError before the fix).
print("\n[CLI: install with no systemctl -> clean error + exit 1]")
with tmp_layout() as L:
    empty_dir = tempfile.mkdtemp(prefix="empty_path_")
    site_file = os.path.join(L["root"], "site.sh")
    with open(site_file, "w") as fh:
        fh.write("# fake site file for tests\n")
    try:
        rc, out, err = run_cli(
            ["install"],
            env_extra={
                "HOME": L["root"],
                "SLACUBE_SPOOL": L["spool"],
                "SLACUBE_DROPBOX": L["dropbox"],
                "SLACUBE_SITE_FILE": site_file,
                "XDG_CONFIG_HOME": os.path.join(L["root"], "xdg"),
                "PATH": empty_dir,
            },
        )
        check(rc == 1, "install with no systemctl exits 1: rc=%d" % rc)
        check("error:" in err and "not found" in err,
              "install with no systemctl prints clean error: %r" % (err,))
    finally:
        shutil.rmtree(empty_dir, ignore_errors=True)


# ---------------------------------------------------------- _serve_once removed (minor)
# The old `_serve_once` was dead code. Verify it's gone (replaced by
# _dispatch_pass + _serve_loop).
print("\n[cleanup: _serve_once removed]")
check(not hasattr(convertd, "_serve_once"),
      "_serve_once is gone (dead code removed)")
check(hasattr(convertd, "_dispatch_pass"),
      "_dispatch_pass exists (the new single-pass dispatcher)")
check(hasattr(convertd, "_now_in_window"),
      "_now_in_window exists (not_before helper)")


# ---------------------------------------------------------- result
print("\n" + "=" * 60)
if _failures:
    print("FAILED (%d):" % len(_failures))
    for f in _failures:
        print("  - " + f)
    sys.exit(1)
else:
    print("ALL PASSED")
    sys.exit(0)
