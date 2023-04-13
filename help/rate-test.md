NAME
====
**slacube rate-test** - QC test on trigger rate.

SYNOPSIS
========
**slacube rate-test [ start | help ]**

DESCRIPTION
===========
**slacube rate-test** identifies and masks the channels with high trigger rate.

COMMAND
=======
start
:   Perform a trigger rate test. Save an updated bad channel list under `$SLACUBE_WORKDIR`. It is a wrapper function for `trigger_rate_qc.py`.

help
:   Show this text.

EXAMPLES
========
Start a new test
```
   $ slacube rate-test start
```

ENVIRONMENT
===========
`$SLACUBE_QC_SCRIPTS`
:   Location of `trigger_rate_qc.py` script. See `slacube help`

`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.


SEE ALSO
========
`slacube help`, `slacube env help`
