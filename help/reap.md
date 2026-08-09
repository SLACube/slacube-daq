NAME
====
**slacube reap** - evict old raw files from the raw cache once free space drops below the LOW watermark

SYNOPSIS
========
**slacube reap [ help ]**

DESCRIPTION
===========
**slacube reap** evicts raw files from `$SLACUBE_RAW_CACHE` once
free space drops below `$SLACUBE_RAW_CACHE_LOW` (default 500 GiB),
until free space reaches `$SLACUBE_RAW_CACHE_HIGH` (default 750
GiB). Eviction is oldest-mtime-first. A raw is deleted only if its
converted twin exists in either `$SLACUBE_DROPBOX` or anywhere under
`dirname($SLACUBE_DROPBOX)/pool/` (D1's invariant). A raw with no
twin anywhere is logged and left in place, unconditionally -- even
under capacity pressure. Twin-check logic is shared with
`slacube fsck` via `scripts/_slacube_paths.py`.

The legacy `pool/raw/` subtree (D7) is never consulted as a twin
source: the shared `walk_pool()` helper prunes it at the top of
every walk, so the reap decision is unaffected by any pre-scheme
data that may still be present.

COMMAND
=======
help
:   Show this text.

ENVIRONMENT
===========
`$SLACUBE_RAW_CACHE`
:   Required. The raw cache to evict from. Missing directory is a
      fatal error.

`$SLACUBE_DROPBOX`
:   Required. The dropbox whose contents count as converted
      twins; `dirname($SLACUBE_DROPBOX)/pool/` is the other twin
      source.

`$SLACUBE_RAW_CACHE_LOW`
:   Free-space low watermark in bytes (default `500 GiB`).
      Absolute bytes; never percentages (D3, D6).

`$SLACUBE_RAW_CACHE_HIGH`
:   Free-space high watermark in bytes (default `750 GiB`).
      Reaping stops once free space reaches this value. Must
      exceed `LOW`; if not, `HIGH` is clamped to `LOW + 250 GiB`.

`$SLACUBE_REAP_POLL`
:   Poll interval (seconds) between `df` re-checks once free
      space is below `LOW`. Default `5`.

NOTES
=====
- Absolute-byte watermarks only (D3, D6); no percentages.
- A raw whose converted twin does not exist anywhere is **never**
  evicted, even if the cache is at zero bytes free. This protects
  conversion work in progress (the converter may be about to
  publish the corresponding dropbox file).
- The reap loop exits 0 in every case (it is a periodic service,
  not a one-shot gate). A summary line is printed to stderr:
  `slacube-reap: evicted=N twin_less_skipped=M`.
- This is a daemon intended to be run from cron or systemd on a
  short interval (`SLACUBE_REAP_POLL`); it is not a one-shot CLI.

SEE ALSO
========
`slacube help`, `slacube fsck`, `slacube stage`
