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
release (where ``scripts/`` is on ``$PYTHONPATH`` per ``deploy/env.sh.template``
line 16) and a unit test (where the caller inserts the parent of this
file's directory into ``sys.path``).

Public surface:
  classify_basename(basename) -> str|None
  raw_basename_to_converted(raw_basename) -> str|None
  parse_year_date(basename) -> (year, date)
  pool_root_for(dropbox_root) -> str
  stage_target_path(dropbox_root, basename) -> str|None
  has_converted_twin(raw_basename, dropbox_root, pool_root) -> bool
"""

from __future__ import print_function

import os


# Converted-name prefixes, in longest-first order for safe matching.
# Matches the file-type list in the data-management spec §2.1
# (raw/selftrigger/exttrig/pedestal). The leading underscore is part of
# the prefix, matching the convention ``raw_2026_..._18.h5`` →
# ``selftrigger_2026_..._18.h5`` visible in
# ``slacube-convert-and-move`` (deleted in Task 2 but the convention it
# established lives on).
TYPE_PREFIXES = ("selftrigger_", "pedestal_", "exttrig_")

# Forward (raw → converted) map mirroring ``slacube-convertd.submit``'s
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


def pool_root_for(dropbox_root):
    """Return the pool root (parent of all type/<year>/<date>/ trees).

    Spec: pool root is ``dirname($SLACUBE_DROPBOX)/pool``.
    """
    return os.path.join(os.path.dirname(dropbox_root), "pool")


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


def has_converted_twin(raw_basename, dropbox_root, pool_root):
    """Return True iff a file matching the converted twin basename
    exists in either ``dropbox_root`` directly or anywhere under
    ``pool_root`` (recursively).

    ``pool_root`` is the parent ``pool/`` directory; the function
    walks every ``<type>/<year>/<date>/`` subdirectory under it. A
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
    for dirpath, _dirs, files in os.walk(pool_root):
        if converted in files:
            return True
    return False
