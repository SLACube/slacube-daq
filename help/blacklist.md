NAME
====
**slacube blacklist** - manage bad channels list.

SYNOPSIS
========
**slacube blacklist [ add | set | help ]**

DESCRIPTION
===========
**slacube blacklist** manage a list of bad channels for SLACube operation. It works under `$SLACUBE_WORKDIR`.

COMMAND
=======
add _chip-id_  [_channel_]
:   Mask all channels of _chip-id_ (default) or mask a specified channel. It only works after `slacube blacklist set`.

set [_json-file_]
:   Select a bad channels list for further operations.If _json-file_ is not given, a popup window will show up for file selection under `$SLACUBE_WORKDIR`.  

help
:   Show this text.

EXAMPLES
========
Select bad channels list from file picker under `$SLACUBE_WORKDIR`
```
  $ slacube blacklist set
```

Select bad channels list from a file
```
  $ slacube blacklist set bad-channels.json
```

Mask channel 13 from chip 1-1-19
```
  $ slacube blacklist add 1-1-19 13
```

Mask all channels from chip 1-4-90
```
  $ slacube blacklist add 1-4-90
```

ENVIRONMENT
===========
`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube env help`, `slacube rate-test help`, `slacube pedestal help`.
