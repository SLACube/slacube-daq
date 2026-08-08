NAME
====
**slacube run** - take data for a series of pedestal and self-triggered runs.

SYNOPSIS
========
**slacube run [ start | stop | help ]**

DESCRIPTION
===========
**slacube run** loops pedestal and self-triggered data-taking, moving pedestal output to `$SLACUBE_DROPBOX` directly and queueing self-triggered output for conversion via `nq`. It works under `$SLACUBE_WORKDIR` and requires `$CTRL_FILE`, `$BAD_CHANNEL_FILE`, `$CFG_DIR`, and `$SLACUBE_DROPBOX` to already be set.

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
:   Destination for pedestal output; self-triggered output is queued via `nq` for conversion into the dropbox. See `slacube help`.

`$NQDIR`, `$NQDONEDIR`, `$NQFAILDIR`
:   Job queue used to convert and move self-triggered data in the background. See `slacube help`.

SEE ALSO
========
`slacube help`, `slacube env help`, `slacube pedestal help`, `slacube selftrig help`
