#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
def module(name):
 spec=importlib.util.spec_from_file_location(name,ROOT/'tools/game-soak'/f'{name}.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
monitor=module('monitor');summary=module('summarize')
class GameSoakTests(unittest.TestCase):
 def test_mach_units(self):
  self.assertEqual(monitor.ticks_to_ns(24_000_000,125,3),1_000_000_000)
  self.assertEqual(monitor.ticks_to_ns(123,1,1),123)
  self.assertEqual(monitor.cpu_percent(2_000_000_000,1_000_000_000,2),50)
  self.assertEqual(monitor.cpu_percent(4_000_000_000,0,2),200)
  self.assertIsNone(monitor.cpu_percent(1,2,1))
  self.assertIsNone(monitor.cpu_percent(2,1,0))
  with self.assertRaises(ValueError):monitor.ticks_to_ns(1,1,0)
 def test_histogram_bounds(self):
  self.assertEqual(summary.histogram_percentile({16:95,99:4,2000:1},.95),17)
  self.assertEqual(summary.histogram_percentile({16:95,99:4,2000:1},.99),100)
  self.assertIsNone(summary.histogram_percentile({16:95,2000:5},.99))
 def test_phase_boundary_and_truncation(self):
  row='CYDER_SURFACE_PROFILE pid=1 surface=0x42 final=0 width=960 height=720 elapsed_ns=5000000000 updates=2 intervals=2 submit_ns=123 interval_ns=33333333 max_interval_ns=16666667 over_50ms=0 over_100ms=0 bins=16:2,\n'
  self.assertEqual(len(summary.surface_rows(row*3)),2)
  self.assertEqual(summary.surface_rows(row[:-1],False),[])
  self.assertEqual(len(summary.surface_rows(row,False)),1)
  self.assertEqual(len(summary.surface_rows(row+row.replace('final=0','final=1')+row)),1)
  self.assertEqual(summary.surface_rows(row.replace('intervals=2','intervals=0').replace('16:2,',''),False)[0]['bins'],{})
  with self.assertRaises(ValueError):summary.surface_rows(row.replace('16:2,','16:1,'))
 def test_missing_process_and_gpu_sample_deduplication(self):
  process=dict(pid=1,kind='wine',cpu_percent=50,rss_bytes=100,footprint_bytes=200)
  rows=[dict(elapsed_s=0,processes=[process],gpu_sample_age_s=0,gpu=[{'Device Utilization %':10}]),dict(elapsed_s=1,processes=[],gpu_sample_age_s=1,gpu=[{'Device Utilization %':10}])]
  result=summary.summarize_monitor(rows,[1,2])
  self.assertEqual(result['expected_pid_missing_samples'],{'1':1,'2':2})
  self.assertEqual(result['gpu']['0:Device Utilization %']['samples'],1)
  self.assertEqual(result['processes']['1']['cpu_percent']['mean'],50)
  self.assertEqual(result['cpu_percent_totals']['games']['mean'],50)
  self.assertIsNone(result['cpu_percent_totals']['wineservers'])
if __name__=='__main__':unittest.main()
