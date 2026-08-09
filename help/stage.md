NAME
====
**slacube stage** - move converted files from the dropbox into the long-term pool

SYNOPSIS
========
**slacube stage [ --once | help ]**

DESCRIPTION
===========
**slacube stage** walks every file in `$SLACUBE_DROPBOX` whose basename
matches `*.h5` and renames it into
`dirname($SLACUBE_DROPBOX)/pool/<type>/<year>/<date>/<basename>`.
Type prefixes recognised (matching the spec's file-type list):

- `selftrigger_` -> `pool/selftrigger/`
- `pedestal_`    -> `pool/pedestal/`
- `exttrig_`     -> `pool/exttrig/`

A file whose mtime is younger than 60 seconds is left alone (still being
written by the conversion daemon). Dotfiles and any non-`.h5` names are
skipped. A basename that does not match a known type prefix is reported
on stderr and the script exits non-zero after attempting every other
file -- the empty-type `pool/<type>//` path bug that the host-only
`/data/slacube/stage-file` script was working around is intentionally
not reintroduced.

This is the bridge between the conversion daemon's dropbox publish
(small `*.h5` files under `$SLACUBE_DROPBOX`) and the long-term pool
hierarchy under `dirname($SLACUBE_DROPBOX)/pool/`.

COMMAND
=======
--once
:::   (default behaviour) stage every classifiable file once and exit.

help
:::   Show this text.

EXAMPLES
========
Run once after the conversion daemon finishes a batch
```
   $ slacube stage
```

ENVIRONMENT
===========
`$SLACUBE_DROPBOX`
:::   Directory holding converted `*.h5` files awaiting staging. Required.

NOTES
=====
- The 60 s mtime floor is the simplest possible guard against racing
  with the converter's `.part` -> final rename. On the production
  `/scratch` filesystem (NVMe on-store) this is well below the
  observed publish latency.
- An unclassifiable basename produces stderr noise on the first run
  after a rename mistake in upstream tooling. The error exit
  surfaces it to cron/systemd without losing the staging work for
  the classifiable files in the same dropbox.
- The `pool/raw/` subtree is never produced by stage (D7) and is
  ignored by `slacube fsck`; only the three type-prefixed buckets
  are written.

SEE ALSO
========
`slacube help`, `slacube fsck`, `slacube reap`
