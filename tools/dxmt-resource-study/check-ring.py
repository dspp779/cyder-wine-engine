from pathlib import Path
import subprocess,json,hashlib,argparse
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args();src=args.source.resolve()
s=src.read_text()
a=s[s.index('template <typename Allocator,'):s.index('class GpuPrivateBufferBlockAllocator')]
b=s[s.index('template <typename Allocator, size_t BlockSize, class mutex>\nstd::pair'):s.rindex('} // namespace dxmt')]
pre='''#include <algorithm>
#include <cstdint>
#include <cstddef>
#include <mutex>
#include <queue>
#include <cstdio>
#define WARN(...) ((void)0)
namespace dxmt { using mutex=std::mutex;
constexpr size_t kStagingBlockSize=32; constexpr size_t kStagingBlockLifetime=300;
static size_t align(size_t n,size_t a){return (n+a-1)&~(a-1);}
'''
post='''
struct ProbeAllocator {struct Block {unsigned id;}; unsigned* count; Block allocate(size_t){return {++*count};}};
}
int main(){unsigned count=0; dxmt::RingBumpState<dxmt::ProbeAllocator,32> ring({&count});
 for(unsigned seq=1;seq<=20;seq++)ring.allocate(seq,seq-1,32,1);
 printf("allocations_for_20_completed_batches=%u\\n",count);
 return 0;}
'''
out=args.output.resolve()
if out.exists():raise SystemExit("Choose a new output directory.")
out.mkdir(parents=True)
results=[]
for name,body in [('baseline',a+b),('inclusive-boundary',a+b.replace('front.last_used_seq_id < coherent_id','front.last_used_seq_id <= coherent_id'))]:
 path=out/(name+'.cpp');path.write_text(pre+body+post)
 subprocess.run(['clang++','-std=c++20','-O2','-mmacosx-version-min=11.0',str(path),'-o',str(out/name)],check=True)
 r=subprocess.check_output([str(out/name)],text=True);print(name,r.strip());results.append(dict(case=name,output=r.strip()))
(out/'ring-results.json').write_text(json.dumps(dict(source=str(src),sha256=hashlib.sha256(s.encode()).hexdigest(),cases=results,scope='Extracted original allocator template with fake allocation; no GPU correctness claim'),indent=2)+'\n')
