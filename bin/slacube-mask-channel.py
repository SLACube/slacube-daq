#!/usr/bin/env python3

import fire
import json
import sys

def load_json(fpath):
    with open(fpath, 'r') as f:
        output = json.load(f)
    return output

def save_json(fpath, data):
    with open(fpath, 'w') as f:
        json.dump(data, f, indent=4)
        
def add(fpath, chip_key, ch=None):
    blacklist = load_json(fpath)

    if ch is None:
        print(f'Masking Chip:{chip_key} ALL CHANNELS')
        ch_list = list(range(64))
    elif isinstance(ch, int):
        print(f'Masking Chip:{chip_key} Channel:{ch}')
        curr = set(blacklist.get(chip_key, []))
        curr.add(ch)
        ch_list = list(curr)
    else:
        print(
            'Usage: slacube-mask-channel.py FILE CHIP_KEY [CH]',
            file=sys.stderr
        )
        sys.exit(1)

    ch_list.sort()
    blacklist[chip_key] = ch_list
    save_json(fpath, blacklist)

if __name__ == '__main__':
    fire.Fire(add)
