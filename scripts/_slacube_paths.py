#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Shared path/twin helpers for slacube-stage, slacube-fsck, slacube-reap.

A converted file basename carries two pieces of structure:
  - a type prefix (``selftrigger_``, ``pedestal_``, ``exttrig_``) which
    identifies which acquisition mode produced it, and
  - an embedded timestamp of the form ``YYYY_MM_DD_HH_MM_SS`` which
    controls its year/date bucket under ``pool/<type>/<year>/<date>/``.

The helpers in this module centralise parsing of both, so
``slacube-stage`` (which writes into the pool) and ``slacube-reap``
(which reads the raw cache and looks for converted twins) do not
reimplement the same regex/path code.

This module is deliberately stdlib-only and importable from both a
release (executed from systemd/cron with no env sourced) and a unit
test. The actual import mechanism used by every consumer in this
repo is **explicit** ``sys.path.insert`` of ``../scripts`` relative
to the consuming script's ``__file__`` (see the ``_HERE``/``_SCRIPTS``
blocks at the top of ``bin/slacube-stage`` / ``bin/slacube-fsck`` /
``bin/slacube-reap``); the ``PYTHONPATH`` entry in
``deploy/env.sh.template`` covers a *separate* sibling repo's
``scripts/`` directory and does not apply here.

Public surface:
  classify_basename(basename) -> str|None
  raw_basename_to_converted(raw_basename) -> str|None
  parse_year_date(basename) -> (year, date)
  pool_root_for(dropbox_root) -> str
  stage_target_path(dropbox_root, basename) -> str|None
  walk_pool(pool_root) -> generator
  has_converted_twin(raw_basename, dropbox_root, pool_root) -> bool
"""

from __future__ import print_function

import os


# Converted-name prefixes, in longest-first order for safe matching.
# Matches the file-type list in the data-management spec (D2.1):
# raw/selftrigger/exttrig/pedestal. The leading underscore is part of
# the prefix, matching the convention ``raw_2026_..._18.h5`` to
# ``selftrigger_2026_..._18.h5``.
TYPE_PREFIXES = ("selftrigger_", "pedestal_", "exttrig_")

# Forward (raw to converted) map mirroring ``slacube-convertd.submit``'s
# prefix substitution. A raw named ``exttrig_2026_..._18.h5`` produces a
# converted file named ``exttrig_2026_..._18.h5`` (identity mapping):
# exttrig acquisitions bypass the converter and land in dropbox verbatim.
# A raw named ``raw_...`` produces ``selftrigger_...``; ``pedestal_...``
# produces ``pedestal_...``. Unrecognised prefixes yield None.
RAW_TO_CONVERTED_PREFIX = (
    ("raw_", "selftrigger_"),
    ("pedestal_", "pedestal_"),
    ("exttrig_", "exttrig_"),
)


# Subdirectory name (directly under pool/) that is part of the legacy
# tree and must never be walked (D7). Exposed as a public constant so
# the per-script walks in ``bin/slacube-fsck`` and ``bin/slacube-reap``
# can share the same exclusion.
LEGACY_POOL_RAW_DIRNAME = "raw"


def classify_basename(basename):
    """Return the type name (``selftrigger``/``pedestal``/``exttrig``)
    embedded in a converted-file basename, or None if the basename
    does not start with a known type prefix.

    The returned name is the pool-directory name (no trailing
    underscore), matching ``pool/<type>/<year>/<date>/`` in the spec.
    """
    for prefix in TYPE_PREFIXES:
        if basename.startswith(prefix):
            return prefix[:-1]
    return None


def raw_basename_to_converted(raw_basename):
    """Given a raw basename (``raw_2026_02_21_21_52_18.h5`` etc.),
    return the converted basename (``selftrigger_2026_02_21_21_52_18.h5``)
    the way ``slacube-convertd.submit`` does for ``out``. Returns None
    if the raw basename does not start with a recognised raw prefix
    (i.e. would never have produced a converted twin).
    """
    for src, dst in RAW_TO_CONVERTED_PREFIX:
        if raw_basename.startswith(src):
            return dst + raw_basename[len(src):]
    return None


def parse_year_date(basename):
    """Extract ``(year, date)`` from a basename whose embedded
    timestamp is ``YYYY_MM_DD_HH_MM_SS``. ``date`` is returned in
    ``YYYY-MM-DD`` form. Raises ``ValueError`` if no such sequence is
    present.

    The function is prefix-agnostic: it scans the underscore-split
    tokens and returns the first valid (year, month, day) triple. This
    matches both raw (``raw_2026_02_21_...``) and converted
    (``selftrigger_2026_02_21_...``) basenames without coupling the
    parsing to either prefix list.
    """
    base = os.path.basename(basename)
    stripped = base[:-len(".h5")] if base.endswith(".h5") else base
    parts = stripped.split("_")
    if len(parts) < 3:
        raise ValueError(
            "basename %r does not carry a YYYY_MM_DD_* stamp" % base)
    for i in range(len(parts) - 2):
        year, month, day = parts[i], parts[i + 1], parts[i + 2]
        if (len(year) == 4 and year.isdigit()
                and len(month) == 2 and month.isdigit()
                and len(day) == 2 and day.isdigit()):
            return year, "%s-%s-%s" % (year, month, day)
    raise ValueError(
        "basename %r does not carry a YYYY_MM_DD_* stamp" % base)


def _strip_trailing_sep(path):
    """Strip any trailing separator(s) from `path`. Defensive only
    against a single trailing sep (typical `$SLACUBE_DROPBOX/` case);
    deeper normalisations belong to ``os.path.normpath``.
    """
    if not path:
        return path
    return path.rstrip(os.sep)


def pool_root_for(dropbox_root):
    """Return the pool root (parent of all type/<year>/<date>/ trees).

    Spec: pool root is ``dirname($SLACUBE_DROPBOX)/pool``.

    The trailing-slash trap: ``os.path.dirname("/x/y/")`` returns
    ``"/x/y"`` (the path itself, minus the trailing slash), not
    ``"/x"``. Strip any trailing separator before dirname to avoid
    silently nesting pool under dropbox.
    """
    return os.path.join(os.path.dirname(_strip_trailing_sep(dropbox_root)),
                        "pool")


def stage_target_path(dropbox_root, basename):
    """Return the absolute pool target path for a converted basename,
    or None if the basename has no recognised type prefix or no
    parseable timestamp.

    Layout: ``dirname(dropbox)/pool/<type>/<year>/<date>/<basename>``.
    """
    type_name = classify_basename(basename)
    if type_name is None:
        return None
    try:
        year, date = parse_year_date(basename)
    except ValueError:
        return None
    return os.path.join(
        pool_root_for(dropbox_root), type_name, year, date, basename)


def walk_pool(pool_root):
    """Yield ``(dirpath, dirnames, filenames)`` for every directory
    under ``pool_root`` EXCEPT a directory literally named ``raw``
    that sits directly under ``pool_root`` (D7: legacy tree).

    The exclusion is implemented by mutating the in-place
    ``dirnames`` list when ``pool_root`` is the parent of a
    ``raw`` entry, which is how ``os.walk`` honours pruning: a
    top-level yield with the legacy entry removed from ``dirnames``
    prevents the walk from descending into it at all (no I/O on the
    legacy tree).
    """
    if not pool_root or not os.path.isdir(pool_root):
        return
    for dirpath, dirnames, filenames in os.walk(pool_root):
        # Only the immediate children of pool_root are subject to the
        # D7 exclusion; a ``raw`` directory deeper in the tree (e.g.
        # ``pool/selftrigger/2026/raw/`` if a future task ever
        # produced one) is fair game.
        if os.path.normpath(dirpath) == os.path.normpath(pool_root):
            dirnames[:] = [
                d for d in dirnames if d != LEGACY_POOL_RAW_DIRNAME]
        yield dirpath, dirnames, filenames


def has_converted_twin(raw_basename, dropbox_root, pool_root):
    """Return True iff a file matching the converted twin basename
    exists in either ``dropbox_root`` directly or anywhere under
    ``pool_root`` (recursively).

    ``pool_root`` is the parent ``pool/`` directory; the function
    walks every ``<type>/<year>/<date>/`` subdirectory under it,
    **excluding** any directory literally named ``raw`` directly
    under the pool root (D7: legacy tree must never be entered). A
    raw whose twin would never exist (no mapping in
    ``RAW_TO_CONVERTED_PREFIX``) always returns False.
    """
    converted = raw_basename_to_converted(raw_basename)
    if converted is None:
        return False
    dropbox_path = os.path.join(dropbox_root, converted)
    if os.path.isfile(dropbox_path):
        return True
    if not pool_root or not os.path.isdir(pool_root):
        return False
    for _dirpath, _dirs, files in walk_pool(pool_root):
        if converted in files:
            return True
    return False
