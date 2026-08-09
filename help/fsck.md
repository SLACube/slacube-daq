NAME
====
**slacube fsck** - read-only health report for the data-management directories

SYNOPSIS
========
**slacube fsck [ help ]**

DESCRIPTION
===========
**slacube fsck** walks `$SLACUBE_RAW_CACHE`, `$SLACUBE_DROPBOX`,
`$SLACUBE_SPOOL`, and `dirname($SLACUBE_DROPBOX)/pool/`, and prints six
sections of findings. The legacy `pool/raw/` subtree (per D7) is
explicitly skipped: nothing in this scheme touches pre-existing data.
Exits 0 on a healthy run, 1 only if it cannot read one of its scoped
directories.

Sections:

  (a) raw files in raw cache with no converted twin in dropbox or
      pool/ (genuine finding -- should be rare per D1)
  (b) leftover `.part`/`.tmp` files in dropbox *and* the workdir tree
      under `dirname($SLACUBE_RAW_CACHE)` (Task 1's primary `.part`
      location during conversion, D2 step 1)
  (c) job records in `$SLACUBE_SPOOL/failed/`, with `last_error` and
      age (the age is computed against UTC, not host TZ)
  (d) files in `$SLACUBE_DROPBOX` older than 24 h (stage not running)
  (e) pool files not yet verified at S3DF -- not implemented here;
      printed as a documented limitation (Task 4's
      `slacube-sync-pool --verify` runs from `sdfcron001`, not this
      host)
  (f) free space per tier (workdir, dropbox, raw cache, spool) via df

Converted files in dropbox/pool whose raw is absent from the cache
are reported as a count only in section (f)'s vicinity (D5: expected
steady state, not a finding; never enumerated).

COMMAND
=======
help
:   Show this text.

ENVIRONMENT
===========
`$SLACUBE_DROPBOX`
:   Required. Directory holding converted `*.h5` files.

`$SLACUBE_RAW_CACHE`
:   Directory holding the raw file archive. If set and unreadable,
      fsck exits 1.

`$SLACUBE_SPOOL`
:   Root of the conversion spool. If set and unreadable, fsck exits 1.

`dirname($SLACUBE_DROPBOX)/pool/`
:   Long-term pool. If it does not exist or is unreadable, fsck
      exits 1.

NOTES
=====
- This is the bridge between the raw cache, the dropbox, and the
  long-term pool. Nothing here is destructive -- fsck never modifies
  files, only reports.
- The unreadable-scoped-directory check is a real `os.listdir`, not
  just `os.path.isdir`, so a `chmod 000` raw cache or pool is
  detected (and the report exits 1).
- The legacy `pool/raw/` subtree is pruned at the top of every
  walk via the shared `walk_pool()` helper in
  `scripts/_slacube_paths.py`; a stderr note is printed when it
  exists so the operator sees the exclusion fired.
- Failed-job ages are reported against UTC, regardless of host
  `$TZ` (the timestamps are naive-UTC strings from the converter
  daemon).

SEE ALSO
========
`slacube help`, `slacube stage`, `slacube reap`
