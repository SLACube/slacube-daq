NAME
====
**slacube exttrig** - Script for taking data from external triggers.

SYNOPSIS
========
**slacube exttrig [ start | help ]**

DESCRIPTION
===========
**slacube exttrig** takes data from external triggers. It works under `$SLACUBE_WORKDIR`. The data-taking function is a wrapper of `exttrig.py`.

COMMAND
=======
start [-h] [_OPTIONS_]
:   Take a external trigger run. Default runtime is 30 seconds. See `exttrig.py -h` for additional _OPTIONS_.

help
:   Show this text.

EXAMPLES
========
Start a external triggered run for 1 mins
```
   $ slacube extrig start --runtime 60
```

ENVIRONMENT
===========
`$SLACUBE_QC_SCRIPTS`
:   Location of `exttrig.py` script. See `slacube help`

`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube help`, `slacube env help`
