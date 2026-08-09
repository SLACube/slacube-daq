NAME
====
**slacube threshold** - manage trigger threshold

SYNOPSIS
========
**slacube threshold [ start | set | copy | adjust | plot | help ]**

DESCRIPTION
===========
**slacube threshold** runs the trigger-threshold search and manages the resulting configuration directory (`$CFG_DIR`). It works under `$SLACUBE_WORKDIR`. The search is a wrapper of `threshold_qc.py` and requires `$CTRL_FILE`, `$BAD_CHANNEL_FILE`, and `$PEDESTAL_FILE` to already be set. For commands with _cfg_, either provide a directory path, or choose from an interactive list of `cfg*` directories under `$SLACUBE_WORKDIR`.

COMMAND
=======
start [--cryo] [_OPTIONS_]
:   Run the threshold search at room temperature, or at cryogenic temperature with `--cryo`. Additional _OPTIONS_ are passed through to `threshold_qc.py`. Prompts for confirmation before starting. On success, writes `$CFG_DIR` to a new `cfg_room_*`/`cfg_cold_*` directory.

set [_cfg_]
:   Set the active threshold configuration directory.

copy
:   Copy the current `$CFG_DIR` into a freshly named sibling directory and make that the active configuration. Requires `$CTRL_FILE`.

adjust global _delta_ [_chip-id_]
:   Adjust the global threshold of one chip, or all chips if _chip-id_ is omitted, by the integer _delta_ (may be negative). Prompts for confirmation. Requires `$CFG_DIR`.

adjust trim _delta_ _chip-id_ [_channel-list_]
:   Adjust the per-channel trim threshold of _chip-id_ by the integer _delta_, for _channel-list_ (comma-separated, e.g. `3,7,12`) or all channels if omitted. Prompts for confirmation. Requires `$CFG_DIR`.

plot [_cfg_]
:   Plot the threshold configuration. Prompts for `VDDA` (default 1800 mV) and whether the data is cryogenic.

help
:   Show this text.

EXAMPLES
========
Start a room-temperature threshold search
```
   $ slacube threshold start
```

Start a cryogenic threshold search
```
   $ slacube threshold start --cryo
```

Adjust the global threshold of every chip by +1
```
   $ slacube threshold adjust global 1
```

Adjust the trim threshold of chip 1-1-19, channels 3 and 7, by -2
```
   $ slacube threshold adjust trim -2 1-1-19 3,7
```

Set the active configuration from a directory
```
   $ slacube threshold set cfg_room_1a2b3c4d
```

Plot a threshold configuration
```
   $ slacube threshold plot cfg_room_1a2b3c4d
```

ENVIRONMENT
===========
`$SLACUBE_QC_SCRIPTS`
:   Location of `threshold_qc.py` and `plot_threshold.py`. See `slacube help`.

`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube help`, `slacube env help`, `slacube pedestal help`, `slacube bad-channel help`
