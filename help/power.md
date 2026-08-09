NAME
====
**slacube power** - LArPix power management

SYNOPSIS
========
**slacube power [ status | down | help ]**

DESCRIPTION
===========
**slacube power** controls power to the LArPix tile via the PACMAN board over ssh. Unlike most `slacube` commands, it does **not** require `$SLACUBE_WORKDIR` and requires only `$SLACUBE_PACMAN_ADDR` to be set.

COMMAND
=======
status
:   Report current power status by running `report_power0.sh` on the PACMAN.

down
:   Power down the LArPix tile. Prompts for confirmation twice before running `power_down.sh` on the PACMAN. Note: confirmation prompts auto-approve when standard input is not a terminal — never pipe input into this command.

help
:   Show this text.

EXAMPLES
========
Check power status
```
   $ slacube power status
```

Power down the tile
```
   $ slacube power down
```

ENVIRONMENT
===========
`$SLACUBE_PACMAN_ADDR`
:   ssh target for the PACMAN board. Controls only `slacube power`'s ssh target, not the DAQ data path, which always goes to the physical PACMAN regardless of this variable. See `slacube help`.

SEE ALSO
========
`slacube help`
