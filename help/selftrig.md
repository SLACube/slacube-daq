NAME
====
**slacube selftrig** - Script for self-triggered data.

SYNOPSIS
========
**slacube selftrig [ start | convert | plot | help ]**

DESCRIPTION
===========
**slacube seltrig** takes and analyzes self-triggered data. It works under `$SLACUBE_WORKDIR`. The data-taking function is a wrapper of `selftrigger_qc.py`. For commands with _file_, either providing a file path, or choosing from a interactive list of files under `$SLACUBE_WORKDIR`.

COMMAND
=======
start [-h] [_OPTIONS_]
:   Take a self-trigger run. Default runtime is 10 mins (as of 2023-04-10). See `slacube selftrig start -h` for additional _OPTIONS_, which are passed to `selftrigger_qc.py`.

convert [_file_]
:   Convert raw data into packets using `convert_raw.py`. Save output to `$SLACUBE_WORKDIR`.

plot [_file_]
:   Plot the mean, std and channel rate of a "packetized" selftrigger file. Save output to `$SLACUBE_WORKDIR`. For advanced usages, see `plot_selftrigger.py`.

help
:   Show this text.

EXAMPLES
========
Start a self-triggered run
```
   $ slacube selftrig start
```

Convert raw data
```
   $ slacube selftrig convert raw.h5
```

Plot selftriggered data
```
   $ slacube selftrig plot selftrigger.h5
```


ENVIRONMENT
===========
`$SLACUBE_QC_SCRIPTS`
:   Location of `selftrigger_qc.py` script. See `slacube help`

`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube help`, `slacube env help`
