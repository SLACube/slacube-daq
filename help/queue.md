NAME
====
**slacube queue** - manage the raw-to-converted conversion spool

SYNOPSIS
========
**slacube queue [ submit | serve | status | retry | ack | drain | install | uninstall | logs | help ]**

DESCRIPTION
===========
**slacube queue** is the user-facing front of the conversion spool. Raw `.h5`
files written under `$SLACUBE_WORKDIR` are submitted to the spool, picked up
by a long-running conversion daemon (`serve`), and the resulting packets
published atomically to `$SLACUBE_DROPBOX` while the raws are moved into
`$SLACUBE_RAW_CACHE`.

The spool is a directory of JSON records, one per job, kept under
`$SLACUBE_SPOOL`:

```
$SLACUBE_SPOOL/
├── incoming/   jobs awaiting a worker
├── running/    claimed by a worker, conversion in progress
├── failed/     conversion exhausted retries, or basename unclassifiable
└── done/       successfully published
```

The daemon (`slacube-convertd serve`) is installed as a systemd `--user`
service by `slacube queue install`. A second instance started by hand is
refused via `flock` on `$SLACUBE_SPOOL/.daemon.lock`.

COMMAND
=======
submit _raw-file_
::   Submit a raw `.h5` to `incoming/`. No-op (exit 0) if a job with the same
    basename already exists in any of the four spool subdirectories. A
    basename that does not match a known raw convention (e.g. `raw_*.h5`
    or `pedestal_*.h5`) is recorded in `failed/` with
    `last_error="unclassifiable"` immediately (no conversion attempted).

serve
::   Run the daemon loop (for systemd). Polls `incoming/` every
    `$SLACUBE_CONVERT_POLL` seconds (default 5), claims up to
    `$SLACUBE_CONVERT_WORKERS` (default 2) jobs in parallel via `os.rename`,
    runs `slacube-convert-raw.py` on each with a per-job timeout of
    `$SLACUBE_CONVERT_TIMEOUT` seconds (default 1800), publishes the
    converted file atomically into `$SLACUBE_DROPBOX`, then moves the raw
    to `$SLACUBE_RAW_CACHE/<year>/<date>/`. On crash, every job in
    `running/` is re-queued into `incoming/` with `attempts += 1` and
    `last_error="interrupted"` on next start.

status
::   Print one summary line `pending=N running=N failed=N done=N
    consecutive_fail=N` to stdout, then exit:

    | exit | meaning                                                           |
    |------|-------------------------------------------------------------------|
    | 0    | `failed/` is empty                                                |
    | 2    | `failed/` non-empty but `consecutive_fail < SLACUBE_MAX_CONSECUTIVE_FAIL` (default 3) - isolated failures, proceed with caution |
    | 1    | `consecutive_fail >= SLACUBE_MAX_CONSECUTIVE_FAIL` - systematic failure, stop and investigate |

    Use `status --json` for the same data as a machine-readable object
    suitable for `jq` or `python3 -c` (Task 2's `guard_acquisition` and
    Task 3's `slacube-fsck` both consume this).

retry _job_
::   Move `failed/<job>.json` back to `incoming/<job>.json` and reset
    `attempts` to 0 and `last_error` to null. Use after fixing the
    underlying cause (free space, bad channel file, etc).

ack _job_
::   Move `failed/<job>.json` to `done/<job>.json` with `outcome="acked"`.
    Use to retire a job without retrying (e.g. raw is known-corrupt).

drain
::   Block (polling, no daemon required) until `incoming/` and `running/`
    are both empty, then exit 0. Used for tests and for clean shutdown
    before an upgrade.

install
::   Write `~/.config/systemd/user/slacube-convert.service` and run
    `systemctl --user daemon-reload && systemctl --user enable --now
    slacube-convert.service`. The unit sources `$SLACUBE_SITE_FILE`
    (default `~/.slacube-site.sh`) before starting `slacube-convertd serve`.

uninstall
::   Run `systemctl --user disable --now slacube-convert.service` and
    remove the unit file.

logs
::   Tail the systemd user journal for `slacube-convert.service` via
    `journalctl --user -u slacube-convert.service`. Implemented in
    `slacube` itself (the daemon script has no `logs` subcommand).

help
::   Show this text.

EXAMPLES
========
Submit a raw file and check status
```
   $ slacube queue submit raw_2026_02_21_21_52_18.h5
   $ slacube queue status
   pending=1 running=0 failed=0 done=0 consecutive_fail=0
```

Install and enable the daemon
```
   $ loginctl enable-linger $USER        # one-time, manual (see NOTES)
   $ slacube queue install
   $ slacube queue logs                  # follow the journal
```

Inspect via JSON (for scripts)
```
   $ slacube queue status --json | jq '.pending + .running'
   1
```

Retry a failed job
```
   $ slacube queue retry raw_2026_02_21_21_52_18
```

ENVIRONMENT
===========
`$SLACUBE_SPOOL`
::   Root of the spool directory (containing `incoming/`, `running/`,
    `failed/`, `done/`).

`$SLACUBE_DROPBOX`
::   Destination for converted files. Atomically published as
    `<basename>` after staging via `.<basename>.part`.

`$SLACUBE_RAW_CACHE`
::   Root of the raw-file archive. Each raw is renamed into
    `<year>/<date>/<basename>` based on the timestamp embedded in the raw
    filename.

`$SLACUBE_WORKDIR`
::   Scratch directory where the daemon writes the `.part` intermediate
    before publishing to the dropbox. Defaults to the parent of
    `$SLACUBE_SPOOL` if unset.

`$SLACUBE_CONVERT_POLL`
::   Poll interval (seconds) for `serve`. Default `5`.

`$SLACUBE_CONVERT_WORKERS`
::   Number of worker threads. Default `2`.

`$SLACUBE_CONVERT_TIMEOUT`
::   Per-job converter timeout (seconds). Default `1800`.

`$SLACUBE_CONVERT_ATTEMPTS`
::   Maximum attempts per job before quarantine. Default `3`.

`$SLACUBE_MAX_CONSECUTIVE_FAIL`
::   Threshold used by `status` to classify a quarantine as systematic
    (exit 1) vs. isolated (exit 2). Default `3`.

`$SLACUBE_SITE_FILE`
::   Path sourced by the systemd unit before `slacube-convertd serve`.
    Default `~/.slacube-site.sh`.

NOTES
=====
- `loginctl enable-linger $USER` must be run once per user before
  `slacube queue install`; the daemon is a `--user` service and would
  otherwise stop on logout. This is a manual one-time step; the
  `install` subcommand does NOT call it (to keep `install` idempotent).

- The daemon refuses to start if `$SLACUBE_SPOOL/.daemon.lock` is already
  held. If you are sure no other instance is running, `rm` the lock and
  retry.

- Intermediate `.part` files under `$SLACUBE_WORKDIR` and the dropbox are
  only visible on failure; on success they are renamed into the final
  product and disappear.

SEE ALSO
========
`slacube help`
