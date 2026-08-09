NAME
====
**slacube selftrig** - take and analyze self-triggered data

SYNOPSIS
========
**slacube selftrig [ start | convert | plot | help ]**

DESCRIPTION
===========
**slacube selftrig** takes and analyzes self-triggered data. It works under `$SLACUBE_WORKDIR`, and `start` requires `$CTRL_FILE`, `$BAD_CHANNEL_FILE`, and `$CFG_DIR` to already be set. The data-taking function is a wrapper of `selftrigger_qc.py`. For commands with _file_, either provide a file path or choose from an interactive list of files under `$SLACUBE_WORKDIR`.

COMMAND
=======
start [-h] [_OPTIONS_]
:   Take a self-trigger run. Default runtime is 10 mins (as of 2023-04-10). See `slacube selftrig start -h` for additional _OPTIONS_, which are passed to `selftrigger_qc.py`.

convert [_file_]
:   Convert a raw file (`raw_*.h5`) into packets with `slacube-convert-raw.py`, saving to `$SLACUBE_WORKDIR` as `selftrigger_*.h5` (the `raw_` prefix replaced with `selftrigger_`).

plot [_file_]
:   Plot the mean, std and channel rate of a converted (`selftrigger_*.h5`) file. Save output to `$SLACUBE_WORKDIR`. For advanced usages, see `plot_selftrigger.py`.

help
:   Show this text.

EXAMPLES
========
Start a self-triggered run
```
   $ slacube selftrig start
```

Convert a raw file
```
   $ slacube selftrig convert raw_2026_08_08_13_57_38_PDT.h5
```

Plot a converted self-trigger file
```
   $ slacube selftrig plot selftrigger_2026_08_08_13_57_38_PDT.h5
```

ENVIRONMENT
===========
`$SLACUBE_QC_SCRIPTS`
:   Location of `selftrigger_qc.py`, `slacube-convert-raw.py`, and `plot_selftrigger.py`. See `slacube help`.

`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube help`, `slacube env help`
