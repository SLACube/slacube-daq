NAME
====
**slacube** - operates SLACube LArPix DAQ

SYNOPSIS
========
**slacube [ _COMMAND_ ] [ _OPTIONS_ ]... [ _ARGS_ ]...**

DESCRIPTION
===========
**slacube** is a collection of scripts and wrapper functions for the SLACube DAQ. The **slacube** ultility provides a series of commands for generating run configuration for LArPix readouts, making diagnostics for quality control tests, and collecting data.

This page summarizes the list of _COMMAND_. See `slacube COMMAND` or `slacube COMMAND help` for deatils.

COMMAND
=======
env [ _OPTIONS_ ]... [ _ARGS_ ]...
:   Manage working directory. Most functions work only under `$SLACUBE_WORKDIR`.

hydra [ _OPTIONS_ ]... [ _ARGS_ ]...
:   Manage hydra network about tile controller file for LArPix operation.

blacklist [ _OPTIONS_ ]... [ _ARGS_ ]...
:   Manage bad channels list.

rate-test [ _OPTIONS_ ]... [ _ARGS_ ]...
:   QC test for trigger rate.

pedestal [ _OPTIONS_ ]... [ _ARGS_ ]...
:   Take pedestal data, QC test, and manage reference pedestal file

threshold [ _OPTIONS_ ]... [ _ARGS_ ]...
:   Manage trigger threshold.

selftrig [ _OPTIONS_ ]... [ _ARGS_ ]...
:   Take self-triggered data and QC test.

ped-mon [ _OPTIONS_ ]... [ _ARGS_ ]...
:   Monitor pedestal for a long term.

run [ _OPTIONS_ ]... [ _ARGS_ ]...
:   Take data for series of pedstal and self-triggered runs.

cfg [ _OPTIONS_ ]... [ _ARGS_ ]...
:   Manage run configuration.

ENVIRONMENT
===========
`$SLACUBE_DEFAULT_WORKDIR`
:   The default location where current working directory is generated. Default to current directory (not recommanded).

`$SLACUBE_WORKDIR`
:   The current working directory.  Most of the `slacube` commands requires to be executed inside this directory. It is available after sourcing the setup script. See `slacube env help`.

`SLACUBE_HELP_DIR`
:   Location for the help pages.

`SLACUBE_GIT_DIR`
:   Git repository for book-keeping run configs.

`SLACUBE_QC_SCRIPTS`
:   A collection of scripts for the QC tests and data taking. See [larpix-10x10-scripts](https://github.com/slac-larpix/larpix-10x10-scripts.git).

`SLACUBE_DROPBOX`
:   Location of data files. Only files obtained from `slacube ped-mon` and `slacube run` are moved to the dropbox. Files from other QC tests (e.g. `pedestal` or `selftrig` are stored in `$SLACUBE_WORKDIR`, but **NOT** in the dropbox.

`SLACUBE_PAGER`
:   (Optional) Pager for showing help, default: `less`.

`SLACUBE_LAYOUT`
:   Tile layout (in simplified `npy` format) for diagnostics plots.

SEE ALSO
========
`slacube help`
