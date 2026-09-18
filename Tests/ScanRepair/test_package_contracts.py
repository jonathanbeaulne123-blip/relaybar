#!/usr/bin/env python3
"""Source/packaging checks, not live Mac installation."""
import unittest, subprocess, re, plistlib, hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[2]
E=(R/'Sources/Core/NativeMenus.swift').read_text(); M=(R/'Sources/Mac/NativeAXSource.swift').read_text()
C=(R/'Sources/Mac/NativeMenuController.swift').read_text(); I=(R/'Install.command').read_text()
class RepairContracts(unittest.TestCase):
 def test_batch_contains_only_shape_metadata(self):
  self.assertIn('let names = ["AXRole", "AXSubrole", "AXHidden"] as CFArray',M)
 def test_shape_cache_cleared_before_every_scan(self):
  self.assertIn('headers.removeAll(keepingCapacity: true)',M)
  self.assertIn('source.beginRead()',E)
 def test_scalars_remain_uncached_for_final_identity_checks(self):
  block=M.split('func element(',1)[1].split('func string(',1)[0]
  self.assertIn('value(node, attribute.rawValue)',block)
  block=M.split('func string(',1)[1].split('func flag(',1)[0]
  self.assertNotIn('attribute == .url',block)
 def test_children_are_paged_and_verified_not_truncated(self):
  for token in ['while offset < count','array.count == length','finalCount == count','seen.insert(child).inserted']:
   self.assertIn(token,M)
 def test_all_failures_clear_candidate_actions(self):
  block=E.split('public func scan(',1)[1].split('private func scanBody',1)[0]
  self.assertIn('result.roots = []; result.openItems = []',block)
 def test_toolbar_pruning_excludes_actual_menu_descendants(self):
  self.assertIn('!inBar && !inMenu && NativeMenuPolicy.chromeRoles.contains(role)',E)
 def test_report_has_numeric_shape_details_no_labels_or_urls(self):
  report=C.split('var connectionReport:',1)[1]
  for token in ['AX queries:','Scan duration ms:','Metadata batches / fallbacks:','Child pages / widest branch:','Stop reason:']:
   self.assertIn(token,report)
  for token in ['.url','.label','FileManager','write(to:']: self.assertNotIn(token,report)
 def test_installer_never_resets_or_writes_permissions(self):
  for token in ['tccutil','TCC.db','osascript','defaults write','sudo']:self.assertNotIn(token,I)
 def test_installer_version_gate_accepts_merged_lineage_and_rejects_downgrades(self):
  gate=I[I.index('  case "$CURRENT:$CURRENT_BUILD" in'):I.index('\n  esac',I.index('  case "$CURRENT:$CURRENT_BUILD" in'))+len('\n  esac')]
  for version,build,accepted in [('0.5.0','7',True),('0.5.1','10',True),('0.5.2','12',True),('0.6.0','9',True),('0.7.0','11',True),('0.8.0','13',True),('0.8.1','14',True),('0.8.2','15',True),('0.8.2','16',False),('0.8.0','15',False),('0.7.0','12',False),('0.9.0','1',True),('0.9.0','16',True),('0.9.0','18',False),('0.9.1','17',True),('0.9.1','18',False),('','',False)]:
   p=subprocess.run(['bash','-c',f'TARGET_BUILD=17; CURRENT={version!r}; CURRENT_BUILD={build!r};\n'+gate],capture_output=True)
   self.assertEqual(p.returncode==0,accepted,(version,build))
 def test_installer_backs_up_app_and_keeps_local_data(self):
  self.assertIn('mv "$APP" "$BACKUP"',I)
  for token in ['rm -rf','ScreenshotShelf/','UserDefaults']:self.assertNotIn(token,I)
 def test_source_version_matches_plist(self):
  d=plistlib.loads((R/'Resources/Info.plist').read_bytes())
  self.assertEqual(d['CFBundleShortVersionString'],'0.9.1');self.assertEqual(d['CFBundleVersion'],'17')
  self.assertIn('RelayBar 0.9.1 · Native Sheets engine 0.5.4 · Menu Cascade + Lean Scan + Verified Click + Persistent Shell',C)
 def test_original_comparison_sources_are_exact(self):
  pins={'NativeMenus_0.5.swift':'476a5e470412fee3fc60c199ce80ed5a31d72290d43655c1324a4127c0b9944b','NativeAXSource_0.5.swift':'fc5ba3ccba50998e91ccc5816dc0748f18d868ec96090b925a42649ce5ebcaf5'}
  for n,v in pins.items():self.assertEqual(hashlib.sha256((R/'Tests/ScanRepair/Baseline'/n).read_bytes()).hexdigest(),v)
if __name__=='__main__':unittest.main(verbosity=2)
