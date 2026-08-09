NAME
====
**slacube bad-channel** - manage the bad-channel list

SYNOPSIS
========
**slacube bad-channel [ set | copy | add | help ]**

DESCRIPTION
===========
**slacube bad-channel** manages the active bad-channel list (`$BAD_CHANNEL_FILE`) for SLACube operation. It works under `$SLACUBE_WORKDIR`.

COMMAND
=======
set [_json-file_]
:   Set the active bad-channel list. If _json-file_ is not given, choose from an interactive list of `*.json` files under `$SLACUBE_WORKDIR`.

copy
:   Copy the active `$BAD_CHANNEL_FILE` to a freshly named sibling file and make that the active list. Use this as a checkpoint before `add`, so the previous list is preserved. Requires `$BAD_CHANNEL_FILE`.

add _chip-id_ [_channel_]
:   Mask all channels of _chip-id_ (default), or a single channel or comma-separated list of channels (e.g. `3,7,12`) if _channel_ is given. Requires `$BAD_CHANNEL_FILE` (run `slacube bad-channel set` first).

help
:   Show this text.

EXAMPLES
========
Select bad-channel list from the interactive list under `$SLACUBE_WORKDIR`
```
  $ slacube bad-channel set
```

Select bad-channel list from a file
```
  $ slacube bad-channel set bad-channels.json
```

Checkpoint the active list before further edits
```
  $ slacube bad-channel copy
```

Mask channel 13 from chip 1-1-19
```
  $ slacube bad-channel add 1-1-19 13
```

Mask channels 3, 7 and 12 from chip 1-1-19
```
  $ slacube bad-channel add 1-1-19 3,7,12
```

Mask all channels from chip 1-4-90
```
  $ slacube bad-channel add 1-4-90
```

ENVIRONMENT
===========
`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube env help`, `slacube rate-test help`, `slacube pedestal help`
