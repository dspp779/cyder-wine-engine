#include <cstdint>
#include <cassert>
#include <cstdio>
#include "dxmt_statistics.hpp"
int main() {
  dxmt::FrameStatisticsContainer s;
  s.compute(0); assert(s.min().event_stall == 0 && s.average().command_buffer_count == 0);
  auto &a=s.at(0);a.command_buffer_count=3;a.sync_count=7;a.event_stall=11;
  a.initializer_interval=std::chrono::milliseconds(5);
  s.compute(1);assert(s.min().command_buffer_count==3);assert(s.average().command_buffer_count==3);
  assert(s.min().event_stall==11);assert(s.average().initializer_interval==std::chrono::milliseconds(5));
  auto &b=s.at(1);b.command_buffer_count=9;b.sync_count=13;b.event_stall=2;
  b.initializer_interval=std::chrono::milliseconds(15);
  s.compute(2);assert(s.min().event_stall==2);assert(s.max().event_stall==11);
  assert(s.average().command_buffer_count==6);assert(s.average().initializer_interval==std::chrono::milliseconds(10));
  for(unsigned i=1;i<=15;i++){s.at(i).command_buffer_count=2*i;s.at(i).event_stall=100+i;}
  s.at(16).command_buffer_count=9999;s.at(16).event_stall=9999;
  s.compute(16);assert(s.min().command_buffer_count==2);assert(s.max().command_buffer_count==30);
  assert(s.average().command_buffer_count==16);assert(s.min().event_stall==101);assert(s.max().event_stall==115);
  puts("PASS statistics startup, nonzero minimum, independent event minimum, average, ring wrap and current exclusion");
}
