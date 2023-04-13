NAME
====
**slacube pedestal** - script for pedestal data.

SYNOPSIS
========
**slacube pedestal [ start | start-qc | set | plot | help ]**

DESCRIPTION
===========
**slacube pedestal** takes pedestal data and manages reference pedestal file. It also run QC tests to identify bad channels. The data-taking function is a wrapper of `pedestal_qc.py`. It works under `$SLACUBE_WORKDIR`.  For commands with _ped-file_, either providing a file path, or choosing from a interactive list of files under `$SLACUBE_WORKDIR`.

COMMAND
=======
start [-h] [_OPTIONS_]
:   Take a pedestal run. Default runtime is 120 seconds (as of 2023-04-10). Additional _OPTIONS_ are pass through to `pedestal_qc.py`. See `slacube pedestal start -h`.

start_qc [-h] [_OPTIONS_]
:   Perform a QC test on pedestal. Bad channels (mean ADC > 125, as of 2023-04-10) are marked.

set [_ped-file_]
:   Set a reference pedestal for threshold scan.

plot [_ped-file_]
:   Plot the mean and std of a pedestal file. Use `analyze_ped.py` for additional options.

help
:   Show this text.

EXAMPLES
========
Start a pedestal run
```
   $ slacube pedestal start
```

Start a pedestal QC test
```
   $ slacube pedestal start-qc
```

Set reference pedestal from file picker
```
   $ slacube pedestal set
```

Set reference pedestal from a given file
```
   $ slacube pedestal set pedestal.h5
```

Plot the mean and std of a pedestal file 
```
   $ slacube pedestal plot pedestal.h5
```

ENVIRONMENT
===========
`$SLACUBE_QC_SCRIPTS`
:   Location of `pedestal_qc.py` script. See `slacube help`

`$SLACUBE_WORKDIR`
:   Current working directory. See `slacube env help`.

SEE ALSO
========
`slacube help`, `slacube env help`
