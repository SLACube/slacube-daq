NAME
====
**slacube** - operates SLACube LArPix DAQ

SYNOPSIS
========
**slacube [ _COMMAND_ ] [ _OPTIONS_ ]... [ _ARGS_ ]...**

DESCRIPTION
===========
**slacube** is a collection of scripts and wrapper functions for the SLACube DAQ. The **slacube** utility provides a series of commands for generating run configuration for LArPix readouts, running diagnostics and quality-control tests, and collecting data.

This page summarizes the list of _COMMAND_. See `slacube COMMAND` or `slacube COMMAND help` for details.

COMMAND
=======
env [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Manage working directory. Most functions work only under `$SLACUBE_WORKDIR`.

hydra [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Manage hydra network about tile controller file for LArPix operation.

bad-channel [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Manage bad channels list.

rate-test [ _OPTIONS_ ]... [ _ARGS_ ]...
::   QC test for trigger rate.

pedestal [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Take pedestal data, QC test, and manage reference pedestal file

threshold [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Manage trigger threshold.

selftrig [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Take self-triggered data and QC test.

exttrig [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Take data from external triggers.

ped-mon [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Monitor pedestal drift over long periods.

run [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Take data for a series of pedestal and self-triggered runs.

cfg [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Manage run configuration.

power [ _OPTIONS_ ]... [ _ARGS_ ]...
::   LArPix power management.

queue [ _OPTIONS_ ]... [ _ARGS_ ]...
::   Interface to the `slacube-convertd` daemon (raw-file spool, status, install/uninstall). See `slacube queue help`.

ENVIRONMENT
===========
`$SLACUBE_PACMAN_ADDR`
::   Address of the PACMAN board.

`$SLACUBE_DEFAULT_WORKDIR`
::   The default location where the current working directory is generated. Defaults to the current directory (not recommended).

`$SLACUBE_WORKDIR`
::   The current working directory. Most `slacube` commands require this to be set (and `cd` into it before running). It is available after sourcing the setup script. See `slacube env help`.

`$SLACUBE_HELP_DIR`
::   Location for the help pages.

`$SLACUBE_GIT_DIR`
::   Git repository for book-keeping run configs.

`$SLACUBE_QC_SCRIPTS`
::   A collection of scripts for the QC tests and data taking. See [larpix-10x10-scripts](https://github.com/slac-larpix/larpix-10x10-scripts.git).

`$SLACUBE_DROPBOX`
::   Location of data files. Only files obtained from `slacube ped-mon` and `slacube run` are moved to the dropbox. Files from other QC tests (e.g. `pedestal` or `selftrig`) are stored in `$SLACUBE_WORKDIR`, but **NOT** in the dropbox.

`$SLACUBE_SPOOL`
::   Spool directory used by `slacube-convertd` (running per-user via systemd `--user`) to convert raw files produced by `slacube run` into `$SLACUBE_DROPBOX`. Layout: `$SLACUBE_SPOOL/{incoming,running,failed,done}/<job>.json`. See `slacube queue help`.

`$SLACUBE_RAW_CACHE`
::   Shared on-store raw-file staging area. The convertd pipeline renames each raw file into here on first dispatch, then converts and renames into `$SLACUBE_DROPBOX` — the raw file crosses `/scratch` → `/scratch` and only the converted output crosses `/scratch` → `/data`.

`$SLACUBE_MAX_CONSECUTIVE_FAIL`, `$SLACUBE_MAX_BACKLOG`, `$SLACUBE_MIN_FREE`, `$SLACUBE_MIN_FREE_DROPBOX`, `$SLACUBE_RESUME_FREE`, `$SLACUBE_RESUME_FREE_DROPBOX`, `$SLACUBE_GUARD_POLL`, `$SLACUBE_MAX_HOLD`
::   Guardrail knobs read by `guard_acquisition` in `bin/slacube`. `run start` and `ped-mon start` call `guard_acquisition` before each acquisition: it holds the loop when the spool backlog exceeds `MAX_BACKLOG` or either filesystem falls below its `MIN_FREE*`, prints one line per `GUARD_POLL` seconds, and resumes once the backlog and free-space thresholds recover. Consecutive convertd failures at or above `MAX_CONSECUTIVE_FAIL`, a failed `df`, or holding longer than `MAX_HOLD` set `.state=0` and exit the loop cleanly.

`$SLACUBE_PAGER`
::   (Optional) Pager for showing help, default: `less`.

`$SLACUBE_LAYOUT`
::   Tile layout (in simplified `npy` format) for diagnostics plots.

`$SLACUBE_APP_DIR`
::   Root of the deployed release (or dev worktree). Set by the release's `env.sh`.

SEE ALSO
========
`slacube help`, `slacube queue help`
