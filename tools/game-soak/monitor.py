#!/usr/bin/env python3
"""Read-only macOS CPU/RSS/footprint sampler plus explicitly system-wide GPU utilization."""
import argparse
import ctypes as C
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import time


def ticks_to_ns(ticks, numer, denom):
    if ticks < 0 or numer <= 0 or denom <= 0:
        raise ValueError('invalid Mach timebase or tick count')
    return ticks * numer // denom


def cpu_percent(cpu_ns, previous_ns, elapsed_seconds):
    if elapsed_seconds <= 0 or cpu_ns < previous_ns:
        return None
    return (cpu_ns - previous_ns) / 1e9 / elapsed_seconds * 100


def usage_type():
    header=Path('/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/resource.h').read_text()
    body=re.search(r'struct rusage_info_v4 \{(.*?)\n\};',header,re.S)[1]
    fields=[('ri_uuid',C.c_uint8*16)]+[(name,C.c_uint64) for name in re.findall(r'uint64_t\s+(\w+);',body)]
    return type('RUsageV4',(C.Structure,),{'_fields_':fields})


def gpu_stats():
    try:
        nodes=plistlib.loads(subprocess.check_output(['/usr/sbin/ioreg','-r','-c','IOAccelerator','-a'],stderr=subprocess.DEVNULL))
        found=[]
        def visit(value):
            if isinstance(value,dict):
                perf=value.get('PerformanceStatistics',{})
                keys=('Device Utilization %','Renderer Utilization %','Tiler Utilization %')
                if any(k in perf for k in keys):found.append({k:perf[k] for k in keys if k in perf})
                for v in value.values():visit(v)
            elif isinstance(value,list):
                for v in value:visit(v)
        visit(nodes)
        return found
    except (OSError,ValueError,subprocess.SubprocessError):return None


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--engine',required=True,type=Path)
    p.add_argument('--output',required=True,type=Path)
    p.add_argument('--seconds',type=float,default=1800)
    p.add_argument('--interval',type=float,default=1)
    p.add_argument('--phase',required=True)
    p.add_argument('--stop-file',type=Path)
    args=p.parse_args()
    if args.interval <= 0 or args.seconds <= 0:p.error('seconds and interval must be positive')
    lib=C.CDLL('/usr/lib/libproc.dylib',use_errno=True);usage=usage_type()
    lib.proc_listallpids.argtypes=[C.c_void_p,C.c_int];lib.proc_listallpids.restype=C.c_int
    lib.proc_pidpath.argtypes=[C.c_int,C.c_void_p,C.c_uint32];lib.proc_pidpath.restype=C.c_int
    lib.proc_pid_rusage.argtypes=[C.c_int,C.c_int,C.c_void_p];lib.proc_pid_rusage.restype=C.c_int
    engine=str(args.engine.resolve())+'/'
    # rusage CPU times are Mach absolute ticks, not nanoseconds (125/3 on M4).
    class Timebase(C.Structure):_fields_=[('numer',C.c_uint32),('denom',C.c_uint32)]
    timebase=Timebase()
    system=C.CDLL('/usr/lib/libSystem.B.dylib')
    if system.mach_timebase_info(C.byref(timebase)) or not timebase.denom:raise RuntimeError('Mach timebase unavailable')
    def ns(ticks):return ticks_to_ns(ticks,timebase.numer,timebase.denom)
    previous={};start=time.monotonic();tick=0;last_gpu=None
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x') as out:
        while time.monotonic()-start<args.seconds:
            if args.stop_file and args.stop_file.exists():break
            now=time.monotonic();pids=(C.c_int*32768)();count=lib.proc_listallpids(pids,C.sizeof(pids));rows=[]
            for pid in list(pids)[:max(0,count)]:
                path=C.create_string_buffer(4096)
                if lib.proc_pidpath(pid,path,len(path))<=0:continue
                executable=path.value.decode(errors='replace')
                if not executable.startswith(engine):continue
                u=usage()
                if lib.proc_pid_rusage(pid,4,C.byref(u)):continue
                cpu=ns(u.ri_user_time+u.ri_system_time);old=previous.get(pid)
                percent=None
                if old and u.ri_proc_start_abstime==old[2] and now>old[0]:percent=cpu_percent(cpu,old[1],now-old[0])
                previous[pid]=(now,cpu,u.ri_proc_start_abstime)
                rows.append(dict(pid=pid,kind='wineserver' if executable.endswith('/wineserver') else 'wine',cpu_percent=percent,user_ns=ns(u.ri_user_time),system_ns=ns(u.ri_system_time),rss_bytes=u.ri_resident_size,footprint_bytes=u.ri_phys_footprint,lifetime_max_footprint_bytes=u.ri_lifetime_max_phys_footprint))
            if tick%5==0:last_gpu=gpu_stats()
            out.write(json.dumps(dict(epoch=time.time(),monotonic_ns=time.monotonic_ns(),phase=args.phase,elapsed_s=now-start,mach_timebase_numer=timebase.numer,mach_timebase_denom=timebase.denom,processes=rows,gpu_scope='whole_device_not_per_process',gpu_sample_age_s=tick%5*args.interval,gpu=last_gpu))+'\n');out.flush()
            tick+=1
            time.sleep(max(0,args.interval-(time.monotonic()-now)))
    print('Recorded phase',args.phase,'for',round(time.monotonic()-start,2),'seconds')


if __name__=='__main__':main()
