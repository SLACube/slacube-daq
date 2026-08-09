NAME
====
**slacube rate-test** - QC test on trigger rate

SYNOPSIS
========
**slacube rate-test [ start | help ]**

DESCRIPTION
===========
**slacube rate-test** identifies channels with anomalously high trigger rate. It works under `$SLACUBE_WORKDIR` and requires `$CTRL_FILE` and `$BAD_CHANNEL_FILE` to already be set.

COMMAND
=======
start
:   Run the trigger-rate test (a wrapper for `trigger_rate_qc.py`) and save the offending channels to a new `trigger-rate-DO-NOT-ENABLE-channel-list-<timestamp>.json` file under `$SLACUBE_WORKDIR`. This does **not** update `$BAD_CHANNEL_FILE` automatically — run `slacube bad-channel set` on the new file to make it the active bad-channel list.

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
