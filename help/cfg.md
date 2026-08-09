NAME
====
**slacube cfg** - manage run configuration

SYNOPSIS
========
**slacube cfg [ archive | help ]**

DESCRIPTION
===========
**slacube cfg** with no argument prints every `SLACUBE_*` environment variable and the contents of `.slacuberc`, for quick inspection of the current working environment. **slacube cfg archive** commits the active threshold configuration, controller file, and bad-channel list into `$SLACUBE_GIT_DIR` for long-term bookkeeping.

COMMAND
=======
(no argument)
:   Print every `SLACUBE_*` environment variable and `.slacuberc`.

archive [_CONFIG_NAME_]
:   Archive the active `$CFG_DIR`, `$CTRL_FILE`, and `$BAD_CHANNEL_FILE` into `$SLACUBE_GIT_DIR/configs/<year>/<date>__<name>`, then commit. All three, plus `$SLACUBE_GIT_DIR`, must already be set. Defaults _CONFIG_NAME_ to the basename of `$CFG_DIR`. Prompts for author name and a one-line comment, then confirms before committing. Fails if that name is already archived on that date.

help
:   Show this text.

EXAMPLES
========
Inspect the current environment
```
   $ slacube cfg
```

Archive the active configuration under its own directory name
```
   $ slacube cfg archive
```

Archive the active configuration under a custom name
```
   $ slacube cfg archive tile2-warm-run3
```

ENVIRONMENT
===========
`$SLACUBE_GIT_DIR`
:   Git repository for archived run configurations. See `slacube help`.

`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube help`, `slacube env help`, `slacube threshold help`
