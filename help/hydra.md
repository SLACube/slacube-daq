NAME
====
**slacube hydra** - manage hydra network tile config

SYNOPSIS
========
**slacube hydra [ create | set | plot | help ]**

DESCRIPTION
===========
**slacube hydra** creates and assigns the hydra network tile config file for SLACube operation. It works under `$SLACUBE_WORKDIR`.

COMMAND
=======
create
:   Create a hydra network config in json format. Takes 2-3 minutes.

set [_json-file_]
:   Select a hydra network config for further operations. If _json-file_ is not given, choose from an interactive list of `tile-*.json` files under `$SLACUBE_WORKDIR`.

plot [_json-file_]
:   Plot the hydra network config to `hydra_<timestamp>.png` under `$SLACUBE_WORKDIR`. Defaults to the active `$CTRL_FILE` if _json-file_ is not given.

help
:   Show this text.

EXAMPLES
========
Create a hydra network
```
   $ slacube hydra create
   $ ls *.json
   tile-id_1-autoconfig.json
```

Select tile config from the interactive list under `$SLACUBE_WORKDIR`
```
   $ slacube hydra set
```

Select tile config from a file
```
   $ slacube hydra set tile-id_1-autoconfig.json
```

Plot the active hydra network config
```
   $ slacube hydra plot
```

ENVIRONMENT
===========
`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube env help`
