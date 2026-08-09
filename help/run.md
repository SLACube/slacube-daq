NAME
====
**slacube run** - take data for a series of pedestal and self-triggered runs

SYNOPSIS
========
**slacube run [ start | stop | help ]**

DESCRIPTION
===========
**slacube run** loops pedestal and self-triggered data-taking, moving pedestal output to `$SLACUBE_DROPBOX` directly and submitting self-triggered raw output to `$SLACUBE_SPOOL` for conversion by `slacube-convertd`. It works under `$SLACUBE_WORKDIR` and requires `$CTRL_FILE`, `$BAD_CHANNEL_FILE`, `$CFG_DIR`, and `$SLACUBE_DROPBOX` to already be set.

COMMAND
=======
start [_ped-runtime_] [_selftrig-runtime_] [_selftrig-repeat_]
:   Start the data-taking loop: one pedestal run followed by _selftrig-repeat_ self-triggered runs, repeated until stopped. Takes either zero arguments (all defaults) or exactly three. Defaults: `ped-runtime=120`, `selftrig-runtime=1200`, `selftrig-repeat=3` (seconds/count, as of 2023-04-10).

stop
:   Stop the loop after the run in progress finishes.

help
:   Show this text.

EXAMPLES
========
Start with defaults
```
   $ slacube run start
```

Start with a shortened cycle (60 s pedestal, 120 s self-trigger, 2 repeats)
```
   $ slacube run start 60 120 2
```

Stop the loop
```
   $ slacube run stop
```

ENVIRONMENT
===========
`$SLACUBE_QC_SCRIPTS`
:   Location of `pedestal_qc.py` and `selftrigger_qc.py`. See `slacube help`.

`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

`$SLACUBE_DROPBOX`
:   Destination for pedestal output. Self-triggered raw output is submitted to `$SLACUBE_SPOOL` and converted/moved into `$SLACUBE_DROPBOX` by `slacube-convertd`. See `slacube help`.

`$SLACUBE_SPOOL`
::   Spool directory used by `slacube-convertd` to convert self-triggered data. See `slacube queue help`.

`$SLACUBE_MAX_CONSECUTIVE_FAIL`, `$SLACUBE_MAX_BACKLOG`, `$SLACUBE_MIN_FREE`, `$SLACUBE_MIN_FREE_DROPBOX`, `$SLACUBE_RESUME_FREE`, `$SLACUBE_RESUME_FREE_DROPBOX`, `$SLACUBE_GUARD_POLL`, `$SLACUBE_MAX_HOLD`
::   Guardrail knobs (defaults live in `guard_acquisition` in `bin/slacube`): the self-trigger loop holds when the spool backlog exceeds `MAX_BACKLOG` or either filesystem falls below its `MIN_FREE*`, prints one line per `GUARD_POLL` seconds, and resumes once the backlog and free-space thresholds recover. Consecutive convertd failures at or above `MAX_CONSECUTIVE_FAIL`, a failed `df`, or holding longer than `MAX_HOLD` set `.state=0` and exit the loop cleanly. See `slacube help`.

SEE ALSO
========
`slacube help`, `slacube env help`, `slacube pedestal help`, `slacube selftrig help`, `slacube queue help`
