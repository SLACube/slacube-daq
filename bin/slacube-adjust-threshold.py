#!/usr/bin/env python

import sys
import fire
import argparse

from larpix import Configuration_v2
from collections.abc import Iterable

def adjust_global(fpath, inc):
    print('loaded {}'.format(fpath))
    cfg = Configuration_v2()
    cfg.load(fpath)

    old_value = cfg.threshold_global
    new_value = min(max(0, old_value + inc), 255)

    cfg.threshold_global = new_value
    cfg.write(fpath, force=True)

    print(f'  global threshold {old_value} -> {new_value}')

def adjust_trim(fpath, inc, channels=range(64)):
    if not isinstance(channels, Iterable):
        channels = (channels,)

    channels = set(channels)
    for ch in channels:
        if isinstance(ch, int) and ch>=0 and ch<=63:
            continue

        print(f'Error invalid channel: {ch}', file=sys.stderr)
        sys.exit(1)

    print('loaded {}'.format(fpath))
    cfg = Configuration_v2()
    cfg.load(fpath)

    for ch in channels:
        if cfg.csa_enable[ch] == 0:
            continue

        old_value = cfg.pixel_trim_dac[ch]
        new_value = min(max(0, old_value + inc), 31)

        cfg.pixel_trim_dac[ch] = new_value
        print(f'  trim threshold ch:{ch} {old_value} -> {new_value}')
    cfg.write(fpath, force=True)

if __name__ == '__main__':
    fire.Fire({
        'global': adjust_global,
        'trim': adjust_trim,
    })
