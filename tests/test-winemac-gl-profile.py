#!/usr/bin/env python3
"""Compile actual profiled callbacks; verify accounting and the zero-clock disabled path."""
import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
def run(*args, **kwargs):
    return subprocess.run(args,check=True,**kwargs)
def func(source,name):
    begin=source.index(name);end=source.index('{',begin)+1;depth=1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[begin:end]+'\n'
with tempfile.TemporaryDirectory(prefix='cyder-gl-profile-') as tmp:
    tmp=Path(tmp);source=tmp/'dlls/winemac.drv/opengl.c';source.parent.mkdir(parents=True)
    original=(ROOT/'tests/fixtures/winemac-gl-profile/dlls/winemac.drv/opengl.c').read_bytes();source.write_bytes(original)
    patch=(ROOT/'patches/cyder-winemac-gl-profile.patch').read_bytes()
    run('patch','--forward','--batch','--fuzz=0','-s','-d',str(tmp),'-p1',input=patch)
    assert subprocess.run(['patch','--forward','--batch','--fuzz=0','--dry-run','-s','-d',str(tmp),'-p1'],input=patch,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode
    header=tmp/'dlls/winemac.drv/cyder_gl_profile.h'
    test=(ROOT/'tests/test-winemac-front-buffer.sh').read_text()
    prefix=re.search(r'cat > "\$TMP/probe.c" <<\'C\'\n(.*?)\nC\n',test,re.S)[1]
    main=re.search(r'cat >> "\$TMP/probe.c" <<\'C\'\n(.*?)\nC\n',test,re.S)[1]
    prefix='#include "'+str(header)+'"\n'+prefix
    prefix=prefix.replace('void *context, *cglcontext, *read_view;', 'void *context, *cglcontext, *read_view; int format, swap_interval; struct cyder_gl_profile profile;')
    prefix+='\nstatic const struct { unsigned double_buffer; } pixel_formats[]={{1}};\n'
    main=main.replace('struct macdrv_context context = { &token, &token, &token };','struct macdrv_context context = { .context=&token, .cglcontext=&token, .read_view=&token, .format=1, .swap_interval=2 };\n    cyder_gl_profile_init(&context.profile);')
    main=main.replace('    return 0;', '    cyder_gl_profile_report(&context.profile, cyder_gl_profile_now(&context.profile), 2, 1, 1);\n    return 0;')
    patched=source.read_text();code=prefix+func(patched,'static void macdrv_surface_flush(')+func(patched,'static BOOL macdrv_surface_swap(')+main
    (tmp/'callbacks.c').write_text(code)
    cc=os.environ.get('CYDER_HOST_CLANG','/usr/bin/clang')
    run(cc,'-std=c99','-Wall','-Wextra','-Werror',str(tmp/'callbacks.c'),'-o',str(tmp/'callbacks'))
    for enabled in ('0','1'):
        result=run(str(tmp/'callbacks'),env={**os.environ,'CYDER_GL_PROFILE':enabled},capture_output=True,text=True)
        if enabled=='0':assert result.stderr==''
        else:
            lines=result.stderr.splitlines();assert len(lines)==2
            counts=[dict(re.findall(r'(\w+)=([^ ]+)',line)) for line in lines]
            assert counts[0]['phase']=='flush' and counts[0]['callbacks']=='128' and counts[0]['native']=='64'
            assert counts[1]['phase']=='swap' and counts[1]['callbacks']=='2' and counts[1]['native']=='2'
            summary=runpy.run_path(str(ROOT/'tools/gl-profile/summarize.py'))['summarize'](result.stderr)
            assert len(summary)==2 and summary[0]['native']==64 and summary[1]['native']==2
            assert sum(summary[0][k] for k in ('le_100us','le_1ms','le_4ms','le_16ms','gt_16ms'))==64
    # Deterministic helper test: clock disabled, histogram edges, publication/reset.
    unit=r'''
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <time.h>
static int ticks, outputs;
static int fake_clock(clockid_t clock, struct timespec *t) { (void)clock; ++ticks; t->tv_sec=10; t->tv_nsec=0; return 0; }
static int fake_print(FILE *file,const char *fmt,...) { (void)file;(void)fmt;++outputs;return 0; }
#define clock_gettime fake_clock
#define fprintf fake_print
#include "HEADER"
int main(void) {
    struct cyder_gl_profile p={0};
    unsetenv("CYDER_GL_PROFILE"); cyder_gl_profile_init(&p);
    assert(cyder_gl_profile_now(&p)==0 && ticks==0);
    cyder_gl_profile_record(&p,0,31,1,2,3,4,0,1); assert(!p.phase[0].callbacks && !outputs);
    setenv("CYDER_GL_PROFILE","1",1); cyder_gl_profile_init(&p);
    assert(cyder_gl_profile_now(&p)==10000000000ULL && ticks==1);
    cyder_gl_profile_record(&p,0,31,100,200,300,400,0,1);
    assert(p.phase[0].callbacks==1 && p.phase[0].native==1 && p.phase[0].callback_ns==300);
    assert(p.phase[0].native_ns==100 && p.phase[0].present_ns==100 && p.phase[0].histogram[0]==1);
    for (int i=0;i<5;++i) assert(p.phase[0].flags[i]==1);
    const uint64_t durations[]={100001,1000001,4000001,16000001};
    for (int i=0;i<4;++i) cyder_gl_profile_record(&p,1,0,1000,1100,1100+durations[i],1200+durations[i],0,1);
    for (int i=1;i<5;++i) assert(p.phase[1].histogram[i]==1);
    assert(!outputs);
    cyder_gl_profile_record(&p,0,0,5000000000ULL,0,0,5000000100ULL,1,1);
    assert(outputs==2 && !p.start && !p.phase[0].callbacks && !p.phase[1].callbacks);
    cyder_gl_profile_report(&p,6000000000ULL,1,1,1); assert(outputs==2);
    setenv("CYDER_GL_PROFILE","yes",1); cyder_gl_profile_init(&p);assert(!p.enabled);
    return 0;
}
'''.replace('HEADER',str(header))
    (tmp/'unit.c').write_text(unit);run(cc,'-std=c99','-Wall','-Wextra','-Werror',str(tmp/'unit.c'),'-o',str(tmp/'unit'));run(str(tmp/'unit'))
    run('patch','--reverse','--forward','--batch','--fuzz=0','-s','-d',str(tmp),'-p1',input=patch)
    assert source.read_bytes()==original and not header.exists()
print('PASS GL profile: actual callbacks preserve all 32 flags/A6/null/order with profiling off/on; accounting, histogram, bounded reports, zero-clock disabled path, patch round-trip')
