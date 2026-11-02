#!/usr/bin/env python3
"""Summarize CYDER_GL_PROFILE aggregate lines without interpreting them as frames."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re


def summarize(text):
    groups=defaultdict(list)
    for line in text.splitlines():
        if not line.startswith('CYDER_GL_PROFILE '):
            continue
        row=dict(re.findall(r'(\w+)=([^ ]+)',line))
        key=tuple(row[k] for k in ('pid','context','phase','interval','double_buffer'))
        for k,v in list(row.items()):
            if k not in ('context','phase'):row[k]=int(v)
        if row['elapsed_ns']<=0 or row['callbacks']<row['native']:
            raise ValueError('invalid GL profiling row')
        groups[key].append(row)
    result=[]
    for key,rows in groups.items():
        sums={k:sum(row[k] for row in rows) for k in ('elapsed_ns','callbacks','native','callback_ns','native_ns','present_ns','le_100us','le_1ms','le_4ms','le_16ms','gt_16ms')}
        seconds=sums['elapsed_ns']/1e9
        result.append(dict(pid=int(key[0]),context=key[1],phase=key[2],interval=int(key[3]),double_buffer=int(key[4]),windows=len(rows),**sums,
                           seconds=seconds,native_per_second=sums['native']/seconds,
                           native_mean_us=sums['native_ns']/max(sums['native'],1)/1000,
                           callback_mean_us=sums['callback_ns']/max(sums['callbacks'],1)/1000,
                           native_wall_ms_per_second=sums['native_ns']/seconds/1e6,
                           callback_wall_ms_per_second=sums['callback_ns']/seconds/1e6,
                           native_max_us=max(row['native_max_ns'] for row in rows)/1000))
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('logs',nargs='+',type=Path)
    args=parser.parse_args()
    rows=summarize('\n'.join(p.read_text(errors='replace') for p in args.logs))
    if not rows:parser.error('no CYDER_GL_PROFILE aggregate rows found')
    print(json.dumps(rows,indent=2))


if __name__=='__main__':main()
