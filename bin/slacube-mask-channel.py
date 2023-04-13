#!/usr/bin/env python3

import fire
import json
import sys

from collections.abc import Iterable

def load_json(fpath):
    with open(fpath, 'r') as f:
        output = json.load(f)
    return output

def save_json(fpath, data):
    with open(fpath, 'w') as f:
        json.dump(data, f, indent=4)
        
def as_set(channels):
    if isinstance(channels, Iterable):
        return set(channels)
    return {channels}

def check(channels):
    for ch in channels:
        if isinstance(ch, int) and ch>=0 and ch<=63:
            continue
        print(f'Error: invalid channel {ch}', file=sys.stderr)
        sys.exit(1)

def add(fpath, chip_key, channels=None):
    bad_list = load_json(fpath)

    if channels is None:
        print(f'Masking Chip:{chip_key} ALL CHANNELS')
        updated_list = list(range(64))
    else:
        channels = as_set(channels)
        check(channels)

        print(f'Masking Chip:{chip_key} Channel: {channels}')
        curr = set(bad_list.get(chip_key, []))
        curr.update(channels)

        updated_list = list(curr)


    updated_list.sort()
    bad_list[chip_key] = updated_list
    save_json(fpath, bad_list)

if __name__ == '__main__':
    fire.Fire(add)
