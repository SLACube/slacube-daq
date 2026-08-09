NAME
====
**slacube ped-mon** - monitor pedestal drift over long periods

SYNOPSIS
========
**slacube ped-mon [ start | stop | analyze | plot | help ]**

DESCRIPTION
===========
**slacube ped-mon** repeatedly takes short pedestal runs to monitor pedestal drift over long periods, and analyzes/plots the accumulated results. It works under `$SLACUBE_WORKDIR` and requires `$CTRL_FILE`, `$BAD_CHANNEL_FILE`, and `$SLACUBE_DROPBOX` for `start`. For commands with _file_, either provide a file path, or choose from an interactive list of files under `$SLACUBE_DROPBOX`. Each pedestal acquisition is preceded by `guard_acquisition` (see ENVIRONMENT) which holds the loop on spool backlog or low disk and stops it cleanly on consecutive convertd failures or a failed `df`.

COMMAND
=======
start [_runtime_] [_trig_cycle_]
:   Start the monitoring loop, taking one pedestal run of _runtime_ seconds with _trig_cycle_ periodic-trigger cycles, repeated until stopped, moving output to `$SLACUBE_DROPBOX`. Takes either zero arguments (defaults) or exactly two. Defaults: `runtime=600`, `trig_cycle=2000000` (as of 2023-04-10).

stop
:   Stop the loop after the run in progress finishes.

analyze [_file_]
:   Analyze one pedestal-monitor file with `analyze_ped_mon.py`, writing output under `./ped_mon`.

plot [_dir_]
:   Plot the accumulated analysis in _dir_ (default `./ped_mon`) with `plot_ped_mon.py`.

help
:   Show this text.

EXAMPLES
========
Start monitoring with defaults
```
   $ slacube ped-mon start
```

Start monitoring with a shortened runtime
```
   $ slacube ped-mon start 120 2000000
```

Analyze one file
```
   $ slacube ped-mon analyze pedestal_1234.h5
```

Plot the accumulated analysis in a non-default directory
```
   $ slacube ped-mon plot my_ped_mon_dir
```

ENVIRONMENT
===========
`$SLACUBE_QC_SCRIPTS`
:   Location of `pedestal_qc.py`, `analyze_ped_mon.py`, and `plot_ped_mon.py`. See `slacube help`.

`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

`$SLACUBE_DROPBOX`
:   Destination for pedestal-monitor output. See `slacube help`.

`$SLACUBE_SPOOL`
::   Spool directory used by `slacube-convertd` to convert data. `guard_acquisition` reads the spool's convertd status to gate the loop on backlog and quarantine depth. See `slacube queue help`.

`$SLACUBE_MAX_CONSECUTIVE_FAIL`, `$SLACUBE_MAX_BACKLOG`, `$SLACUBE_MIN_FREE`, `$SLACUBE_MIN_FREE_DROPBOX`, `$SLACUBE_RESUME_FREE`, `$SLACUBE_RESUME_FREE_DROPBOX`, `$SLACUBE_GUARD_POLL`, `$SLACUBE_MAX_HOLD`
::   Guardrail knobs (defaults live in `guard_acquisition` in `bin/slacube`): the loop holds when the spool backlog exceeds `MAX_BACKLOG` or either filesystem falls below its `MIN_FREE*`, prints one line per `GUARD_POLL` seconds, and resumes once the backlog and free-space thresholds recover. Consecutive convertd failures at or above `MAX_CONSECUTIVE_FAIL`, a failed `df`, or holding longer than `MAX_HOLD` set `.state=0` and exit the loop cleanly. See `slacube help`.

SEE ALSO
========
`slacube help`, `slacube env help`, `slacube pedestal help`, `slacube queue help`
