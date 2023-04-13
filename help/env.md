NAME
====
**slacube env** - manage SLACube DAQ working environment

SYNOPSIS
========
**slacube env [ create | last | help ]**

DESCRIPTION
===========
**slacube env** creates and setup working environment for SLACube data taking.

COMMAND
=======
create [_NAME_]
:   Create a working directory under `$SLACUBE_DEFAULT_WORKDIR`.

last
:   Print the setup script for the most recent (by modification time) working directory.

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

Setup the most recent working environment 
```
   $ source $(slacube env last)
```

Setup a previous working environment
```
  $ source path_to_workdir/setup.sh
```

ENVIRONMENT
===========
`$SLACUBE_DEFAULT_WORKDIR`
:   The default location where current working directory is generated. It should be defined beferoe running `slacube` commmand.

`$SLACUBE_WORKDIR`
:   The current working directory. Most of the `slacube` commands are executed inside this directory. It is available after sourcing the setup script. See [EXAMPLES](#examples).

FILES
=====
Following files are generated when creating the working directory. __DO NOT__ edit, unless you know what you are doing.

`$SLACUBE_WORDIR/setup.sh`
:   Setup script for data taking.

`$SLACUBE_WORDIR/blacklist_default.json`
:   Default blacklist for non-routed channels.

`$SLACUBE_WORDIR/io/pacman.json`
:   PACMAN address.  

`$SLACUBE_WORDIR/.slacuberc`
:   Run config for the current settings.

SEE ALSO
========
`slacube help`
