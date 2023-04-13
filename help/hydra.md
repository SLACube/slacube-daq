NAME
====
**slacube hydra** - manage hydra network tile config

SYNOPSIS
========
**slacube hydra [ create | set | help ]**

DESCRIPTION
===========
**slacube hydra** creates and assigns the hydra network tile config file for SLACube operation. It works under `$SLACUBE_WORKDIR`. 

COMMAND
=======
create
:  Create a hdyra netork config in json format.

set [_json-file_]
:  Select a hydra netowrk for further operations. If _json-file_ is not given, a popup window will show up for file selection under `$SLACUBE_WORKDIR`.  

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

Select tile config from file picker under `$SLACUBE_WORKDIR`
```
  $ slacube hydra set
```

Select tile config from a file 
```
  $ slacube hydra set tile-id_1-autoconfig.json
```

ENVIRONMENT
===========
`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube env help`
