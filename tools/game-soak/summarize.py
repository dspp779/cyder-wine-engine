#!/usr/bin/env python3
"""Summarize private sampler data without copying process names, paths or game text."""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import re
import statistics


def distribution(values):
    values=sorted(v for v in values if v is not None)
    if not values:return None
    return dict(samples=len(values),mean=statistics.fmean(values),p50=values[math.ceil(len(values)*.5)-1],p95=values[math.ceil(len(values)*.95)-1],max=values[-1])


def histogram_percentile(bins, fraction):
    """Return the exclusive upper bound, or None for the >=2000ms overflow bin."""
    total=sum(bins.values())
    if not total:return None
    target=math.ceil(total*fraction);seen=0
    for bucket,count in sorted(bins.items()):
        seen+=count
        if seen>=target:return bucket+1 if bucket<2000 else None


def surface_rows(text, drop_first=True):
    rows=[];seen=set()
    lines=text.splitlines()
    if text and not text.endswith('\n'):lines=lines[:-1] # byte boundary can cut a report in flight
    for line in lines:
        if not line.startswith('CYDER_SURFACE_PROFILE '):continue
        fields=dict(re.findall(r'(\w+)=([^ ]*)',line))
        try:
            bins={int(k):int(v) for k,v in re.findall(r'(\d+):(\d+),',fields['bins'])}
            if sum(bins.values())!=int(fields['intervals']):raise ValueError('incomplete histogram')
            row={k:int(v) for k,v in fields.items() if k not in ('surface','bins')}
        except (KeyError,ValueError) as exc:
            raise ValueError('malformed surface aggregate; preserve the raw log') from exc
        key=(row['pid'],fields['surface']);first=key not in seen;seen.add(key)
        if row['final']:seen.discard(key)
        if first and drop_first:continue # first report can straddle phase start
        row['bins']=bins;rows.append(row)
    return rows


def summarize_monitor(rows, expected_pids=()):
    if not rows:raise ValueError('empty monitor data')
    by_pid=defaultdict(list)
    for sample in rows:
        for row in sample['processes']:by_pid[row['pid']].append(dict(row,sample_elapsed_s=sample['elapsed_s']))
    processes={}
    for pid,values in sorted(by_pid.items()):
        processes[str(pid)]=dict(kind=values[0]['kind'],samples=len(values),cpu_percent=distribution(x['cpu_percent'] for x in values),rss_bytes=distribution(x['rss_bytes'] for x in values),footprint_bytes=distribution(x['footprint_bytes'] for x in values),footprint_first=values[0]['footprint_bytes'],footprint_last=values[-1]['footprint_bytes'])
    totals={}
    for label in ('all_engine','games','wineservers'):
        values=[]
        for sample in rows:
            selected=[p for p in sample['processes'] if label=='all_engine' or (label=='games' and p['pid'] in expected_pids) or (label=='wineservers' and p['kind']=='wineserver')]
            valid=[p['cpu_percent'] for p in selected if p['cpu_percent'] is not None]
            values.append(sum(valid) if valid else None)
        totals[label]=distribution(values)
    gpu=defaultdict(list)
    for sample in rows:
        if sample.get('gpu_sample_age_s')!=0:continue
        for index,device in enumerate(sample.get('gpu') or []):
            for key,value in device.items():gpu[str(index)+':'+key].append(value)
    return dict(cpu_percent_totals=totals,samples=len(rows),observed_span_s=rows[-1]['elapsed_s']-rows[0]['elapsed_s'],expected_pid_missing_samples={str(pid):len(rows)-len(by_pid[pid]) for pid in expected_pids},processes=processes,gpu_scope='whole_device_not_per_process',gpu={k:distribution(v) for k,v in gpu.items()})


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('samples',type=Path)
    parser.add_argument('--phase-metadata',type=Path)
    args=parser.parse_args()
    meta=json.loads(args.phase_metadata.read_text()) if args.phase_metadata else {}
    rows=[json.loads(x) for x in args.samples.read_text().splitlines() if x]
    result=summarize_monitor(rows,meta.get('pids',()))
    groups=defaultdict(list)
    for name,start in meta.get('profile_start_offsets',{}).items():
        path=args.phase_metadata.parent/name
        end=meta.get('profile_end_offsets',{}).get(name)
        text=path.read_bytes()[start:end].decode(errors='replace')
        for row in surface_rows(text):groups[(row['pid'],row['width'],row['height'])].append(row)
    result['surface_submission']={}
    for (pid,width,height),values in sorted(groups.items()):
        bins=defaultdict(int)
        for row in values:
            for k,v in row['bins'].items():bins[k]+=v
        totals={k:sum(x[k] for x in values) for k in ('updates','intervals','submit_ns','interval_ns','over_50ms','over_100ms')}
        totals.update(interval_p50_upper_ms=histogram_percentile(bins,.5),interval_p95_upper_ms=histogram_percentile(bins,.95),interval_p99_upper_ms=histogram_percentile(bins,.99),overflow_intervals=bins[2000],report_count=len(values),first_straddling_report_discarded=True)
        totals.update(pid=pid,width=width,height=height)
        result['surface_submission'][f'{pid}@{width}x{height}']=totals
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
