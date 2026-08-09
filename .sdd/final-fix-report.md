# Final Whole-Branch Fix Report

## Implemented

- Reworked `sync/slacube-sync-pool` report enumeration to walk the verified local destination mirror rather than invoking `ssh find` against the source. Default runs now use only the existing pull and verify rsync connections. Source connection failures remain fatal through the checked pull/verify rsync exits, with clear step/exit diagnostics; the separate unchecked SSH enumeration path was eliminated entirely.
- Normalized every `help/*.md` definition-list marker to the pre-existing single-colon `:   ` convention without changing wording.
- Removed `bin/slacube-fsck`'s duplicated reverse-prefix table; it now derives the inverse from imported `RAW_TO_CONVERTED_PREFIX`.
- Kept `bin/slacube-convertd` standalone, added reciprocal one-line comments linking its parallel classification/date implementation with `scripts/_slacube_paths.py`, aligned date parsing behavior, and added fixture-based parity tests.
- Removed the dead `workers` parameter from `_dispatch_pass` and updated both call sites.

## TDD Evidence

- Sync RED: `bash tests/test_slacube_sync_pool.sh` failed at `restricted remote source: no SSH enumeration`, proving default report building still invoked SSH. GREEN: the same command passed after local-mirror enumeration replaced source SSH enumeration.
- Help RED: `bash tests/test_slacube_help.sh` failed at `all help files use the pre-existing single-colon marker`. GREEN: the same command passed after marker normalization.
- Convertd parity RED: `python3 tests/test_slacube_convertd.py` failed at `date parsing agrees for archive_raw_2026_02_21_21_52_18.h5`, proving behavioral drift. GREEN: the same command passed after convertd adopted the shared scan-for-date semantics.

## Verification

Full suite command:

`bash tests/test_guard_acquisition.sh && python3 tests/test_slacube_convertd.py && bash tests/test_slacube_fsck.sh && bash tests/test_slacube_help.sh && python3 tests/test_slacube_paths.py && bash tests/test_slacube_reap.sh && bash tests/test_slacube_stage.sh && bash tests/test_slacube_sync_pool.sh`

Result: exit 0; all eight test suites reported `ALL PASSED` (wall time 25.45 seconds). The guard suite emitted its existing temporary-directory `getcwd` warning during the run-loop scenario, but all assertions passed.

## Files Changed

- `sync/slacube-sync-pool`
- `bin/slacube-fsck`
- `bin/slacube-convertd`
- `scripts/_slacube_paths.py`
- `tests/test_slacube_sync_pool.sh`
- `tests/test_slacube_help.sh`
- `tests/test_slacube_convertd.py`
- `help/*.md` files that had non-single-colon markers
- `.sdd/final-fix-report.md`

## Self-Check

- Confirmed no multi-colon definition-list markers remain in `help/*.md`.
- Confirmed restricted-source sync test uses an SSH sentinel and fails if any SSH enumeration occurs.
- Confirmed failed source connection exits 1 and reports `pull failed` rather than producing an empty eligible set.
- Preserved the standalone convertd constraint: no production import dependency was introduced.

## Open Follow-Ups (Explicitly Out of Scope)

- `cmd_run`/`cmd_pedmon` pedestal-acquisition guard asymmetry.
- Unreachable `pedestal_`/`exttrig_` code findings.
- `guard_acquisition` rule-3 message wording.
- `SLACUBE_WORKDIR` daemon-environment gap.

## Concerns

None within this fix round's scope.
