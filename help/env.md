NAME
====
**slacube env** - manage SLACube DAQ working environment

SYNOPSIS
========
**slacube env [ create | curr | list | help ]**

DESCRIPTION
===========
**slacube env** creates and sets up a working environment for SLACube data taking.

COMMAND
=======
create [_NAME_]
:   Create a working directory under `$SLACUBE_DEFAULT_WORKDIR`.

curr
:   Print the setup script for the most recent (by modification time) working directory.

list
:   List all available setup scripts.

help
:   Show this text.

EXAMPLES
========
Create a new working environment
```
   $ slacube env create
```

Create a new working environment with custom prefix
```
   $ slacube env create mytest
```

Activate the most recent working environment
```
   $ source $(slacube env curr)
```

List all available environments
```
   $ slacube env list
```

Setup a previous working environment
```
   $ source path_to_workdir/setup.sh
```

ENVIRONMENT
===========
`$SLACUBE_DEFAULT_WORKDIR`
:   The default location where the current working directory is generated. It must be set before running any `slacube` command.

`$SLACUBE_WORKDIR`
:   The current working directory. Most of the `slacube` commands are executed inside this directory. It is available after sourcing the setup script. See [EXAMPLES](#examples).

FILES
=====
The following files are generated when creating the working directory. **DO NOT** edit them, unless you know what you are doing.

`$SLACUBE_WORKDIR/setup.sh`
:   Setup script that exports `$SLACUBE_WORKDIR`. Activate with `source $(slacube env curr)`.

`$SLACUBE_WORKDIR/bad_channels-default.json`
:   Default bad-channel list, copied from `$SLACUBE_QC_SCRIPTS/bad_channels.json` and set as the initial `$BAD_CHANNEL_FILE`.

`$SLACUBE_WORKDIR/io/`
:   I/O configuration copied from `$SLACUBE_QC_SCRIPTS/io`, including `pacman.json` (PACMAN address).

`$SLACUBE_WORKDIR/.slacuberc`
:   Run config recording values set by other `slacube` commands (e.g. `$BAD_CHANNEL_FILE`, `$CTRL_FILE`, `$CFG_DIR`) for the current working directory.

SEE ALSO
========
`slacube help`
