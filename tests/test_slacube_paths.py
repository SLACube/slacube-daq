#!/usr/bin/env python3
"""Tests for scripts/_slacube_paths.py.

Standalone harness (no pytest required). Loads the helper module from
the sibling scripts/ directory, then exercises its public surface
against synthetic inputs. Exit 0 on success, non-zero otherwise.

Run as:
    python3 tests/test_slacube_paths.py
"""

from __future__ import print_function

import importlib.machinery as importlib_machinery
import importlib.util as importlib_util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(HERE, ".."))
HELPER_PATH = os.path.join(REPO_ROOT, "scripts", "_slacube_paths.py")


def _load_helper():
    loader = importlib_machinery.SourceFileLoader(
        "slacube_paths", HELPER_PATH)
    spec = importlib_util.spec_from_loader("slacube_paths", loader)
    mod = importlib_util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def _check(cond, msg, failures):
    if cond:
        print("  PASS: " + msg)
    else:
        print("  FAIL: " + msg)
        failures.append(msg)


def main():
    failures = []
    paths = _load_helper()

    print("=" * 60)
    print("test_slacube_paths")
    print("=" * 60)

    # ---- classify_basename ----
    print("\n[classify_basename: extracts type name from converted prefix]")
    _check(
        paths.classify_basename("selftrigger_2026_02_21_21_52_18.h5")
        == "selftrigger",
        "selftrigger_ prefix -> 'selftrigger'",
        failures,
    )
    _check(
        paths.classify_basename("pedestal_2026_02_21_21_52_18.h5")
        == "pedestal",
        "pedestal_ prefix -> 'pedestal'",
        failures,
    )
    _check(
        paths.classify_basename("exttrig_2026_02_21_21_52_18.h5")
        == "exttrig",
        "exttrig_ prefix -> 'exttrig'",
        failures,
    )
    _check(
        paths.classify_basename("raw_2026_02_21_21_52_18.h5") is None,
        "raw_ prefix -> None (not a converted name)",
        failures,
    )
    _check(
        paths.classify_basename("garbage_2026_02_21_21_52_18.h5") is None,
        "unknown prefix -> None",
        failures,
    )

    # ---- raw_basename_to_converted ----
    print("\n[raw_basename_to_converted: maps raw prefix to converted prefix]")
    _check(
        paths.raw_basename_to_converted("raw_2026_02_21_21_52_18.h5")
        == "selftrigger_2026_02_21_21_52_18.h5",
        "raw_ -> selftrigger_",
        failures,
    )
    _check(
        paths.raw_basename_to_converted("pedestal_2026_02_21_21_52_18.h5")
        == "pedestal_2026_02_21_21_52_18.h5",
        "pedestal_ -> pedestal_ (identity)",
        failures,
    )
    _check(
        paths.raw_basename_to_converted("exttrig_2026_02_21_21_52_18.h5")
        == "exttrig_2026_02_21_21_52_18.h5",
        "exttrig_ -> exttrig_ (identity)",
        failures,
    )
    _check(
        paths.raw_basename_to_converted("selftrigger_2026_02_21_21_52_18.h5")
        is None,
        "already-converted name -> None",
        failures,
    )
    _check(
        paths.raw_basename_to_converted("garbage.h5") is None,
        "unknown raw prefix -> None",
        failures,
    )

    # ---- parse_year_date ----
    print("\n[parse_year_date: extracts year/date from basename]")
    y, d = paths.parse_year_date("selftrigger_2026_02_21_21_52_18.h5")
    _check(y == "2026" and d == "2026-02-21", "year=2026 date=2026-02-21",
           failures)
    y, d = paths.parse_year_date("raw_2025_12_31_00_00_00.h5")
    _check(y == "2025" and d == "2025-12-31", "year=2025 date=2025-12-31",
           failures)
    # Path-like input is handled by basename()
    y, d = paths.parse_year_date(
        "/scratch/foo/selftrigger_2026_02_21_21_52_18.h5")
    _check(y == "2026" and d == "2026-02-21", "parses basename from full path",
           failures)
    raised = False
    try:
        paths.parse_year_date("garbage.h5")
    except ValueError:
        raised = True
    _check(raised, "garbage.h5 raises ValueError", failures)
    raised = False
    try:
        paths.parse_year_date("pedestal.h5")
    except ValueError:
        raised = True
    _check(raised, "single-token name raises ValueError", failures)

    # ---- pool_root_for ----
    print("\n[pool_root_for: derives pool root from dropbox]")
    _check(
        paths.pool_root_for("/data/slacube/dropbox")
        == "/data/slacube/pool",
        "/data/slacube/dropbox -> /data/slacube/pool",
        failures,
    )
    _check(
        paths.pool_root_for("/scratch/foo/dropbox")
        == "/scratch/foo/pool",
        "/scratch/foo/dropbox -> /scratch/foo/pool",
        failures,
    )

    # ---- stage_target_path ----
    print("\n[stage_target_path: composes pool/<type>/<year>/<date>/<basename>]")
    target = paths.stage_target_path(
        "/data/slacube/dropbox", "selftrigger_2026_02_21_21_52_18.h5")
    _check(
        target == "/data/slacube/pool/selftrigger/2026/2026-02-21"
                  "/selftrigger_2026_02_21_21_52_18.h5",
        "stage target for selftrigger file",
        failures,
    )
    target = paths.stage_target_path(
        "/data/slacube/dropbox", "pedestal_2026_02_21_21_52_18.h5")
    _check(
        target == "/data/slacube/pool/pedestal/2026/2026-02-21"
                  "/pedestal_2026_02_21_21_52_18.h5",
        "stage target for pedestal file",
        failures,
    )
    _check(
        paths.stage_target_path(
            "/data/slacube/dropbox", "raw_2026_02_21_21_52_18.h5") is None,
        "stage target for raw_ prefix -> None (not a converted name)",
        failures,
    )
    _check(
        paths.stage_target_path(
            "/data/slacube/dropbox",
            "garbage_2026_02_21_21_52_18.h5") is None,
        "stage target for unknown prefix -> None",
        failures,
    )
    _check(
        paths.stage_target_path(
            "/data/slacube/dropbox", "selftrigger_no_timestamp.h5") is None,
        "stage target without timestamp -> None",
        failures,
    )

    # ---- has_converted_twin ----
    print("\n[has_converted_twin: raw twin in dropbox or anywhere under pool/]")
    root = tempfile.mkdtemp(prefix="slacube_paths_test_")
    dropbox = os.path.join(root, "dropbox")
    pool = os.path.join(root, "pool")
    os.makedirs(dropbox)
    try:
        # Case 1: twin in dropbox
        open(os.path.join(dropbox,
                          "selftrigger_2026_02_21_21_52_18.h5"),
             "w").close()
        _check(
            paths.has_converted_twin(
                "raw_2026_02_21_21_52_18.h5", dropbox, pool),
            "twin present in dropbox",
            failures,
        )
        os.remove(os.path.join(dropbox,
                               "selftrigger_2026_02_21_21_52_18.h5"))

        # Case 2: twin only in pool/ (nested)
        bucket = os.path.join(pool, "selftrigger", "2026", "2026-02-21")
        os.makedirs(bucket)
        open(os.path.join(bucket,
                          "selftrigger_2026_02_21_21_52_18.h5"),
             "w").close()
        _check(
            paths.has_converted_twin(
                "raw_2026_02_21_21_52_18.h5", dropbox, pool),
            "twin present nested under pool/",
            failures,
        )

        # Case 3: twin nowhere
        os.remove(os.path.join(bucket,
                               "selftrigger_2026_02_21_21_52_18.h5"))
        _check(
            not paths.has_converted_twin(
                "raw_2026_02_21_21_52_18.h5", dropbox, pool),
            "twin absent -> False",
            failures,
        )

        # Case 4: raw basename with no recognised source prefix -> False
        _check(
            not paths.has_converted_twin("garbage.h5", dropbox, pool),
            "unknown raw basename -> False",
            failures,
        )

        # Case 5: pool root missing -> walk is skipped; dropbox-only check
        open(os.path.join(dropbox,
                          "pedestal_2026_02_21_21_52_18.h5"),
             "w").close()
        _check(
            paths.has_converted_twin(
                "pedestal_2026_02_21_21_52_18.h5",
                dropbox, "/nonexistent/pool"),
            "missing pool root: dropbox twin still found",
            failures,
        )

        # Case 6: pool root is None
        _check(
            paths.has_converted_twin(
                "pedestal_2026_02_21_21_52_18.h5",
                dropbox, None),
            "None pool root: dropbox twin still found",
            failures,
        )
        _check(
            not paths.has_converted_twin(
                "raw_2026_02_21_21_52_18.h5",
                dropbox, None),
            "None pool root, twin only in pool: False",
            failures,
        )
    finally:
        shutil.rmtree(root, ignore_errors=True)

    # ---- result ----
    print("\n" + "=" * 60)
    if failures:
        print("FAILED (%d)" % len(failures))
        for f in failures:
            print("  - " + f)
        return 1
    print("ALL PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
