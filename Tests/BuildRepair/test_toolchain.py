#!/usr/bin/env python3
"""Build-workaround regressions. No Mac SDK, system writes or network required.
The real compiler tests use artificial header/module files in TemporaryDirectory.
They do NOT certify macOS or physical Touch Bar behavior.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'Scripts/toolchain.sh'
MAP = '// comment\nmodule SwiftBridging {\n    header "bridging"\n    export *\n}\n'

class RepairTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='relaybar repair ')
        self.base = Path(self.tmp.name)
        self.inc = self.base / 'toolchain' / 'usr' / 'include' / 'swift'
        self.inc.mkdir(parents=True)
        (self.inc / 'module.modulemap').write_text(MAP)
        (self.inc / 'bridging.modulemap').write_text(MAP.replace('// comment', '// newer comment'))
        (self.inc / 'bridging').write_text('enum { RBProbeValue = 17 };\n')
        self.out = self.base / 'local-view'
        self.before = self.hashes()

    def tearDown(self):
        self.tmp.cleanup()

    def hashes(self):
        return {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.inc.iterdir() if p.is_file()}

    def overlay(self):
        return subprocess.run(['bash', '-c',
            'set -euo pipefail; source "$1"; rb_create_bridging_overlay "$2" "$3"',
            'test', str(HELPER), str(self.inc), str(self.out)],
            capture_output=True, text=True, timeout=10)

    def test_verified_pair_creates_one_file_overlay(self):
        p = self.overlay()
        self.assertEqual(p.returncode, 0, p.stderr)
        data = json.loads((self.out/'overlay.json').read_text())
        self.assertEqual(len(data['roots']), 1)
        self.assertEqual(data['roots'][0]['name'], str(self.inc/'module.modulemap'))
        self.assertFalse(data['use-external-names'])
        self.assertEqual(self.hashes(), self.before)

    def test_different_comments_and_whitespace_are_allowed(self):
        (self.inc/'module.modulemap').write_text('module SwiftBridging { header "bridging" export * }\n')
        self.assertEqual(self.overlay().returncode, 0)

    def test_extra_module_refused(self):
        p = self.inc/'module.modulemap'
        p.write_text(MAP + '\nmodule OtherModule { header "bridging" }\n')
        self.assertNotEqual(self.overlay().returncode, 0)
        self.assertFalse(self.out.exists())

    def test_different_header_refused(self):
        (self.inc/'module.modulemap').write_text(MAP.replace('header "bridging"', 'header "different"'))
        self.assertNotEqual(self.overlay().returncode, 0)
        self.assertFalse(self.out.exists())

    def test_missing_current_map_refused(self):
        (self.inc/'bridging.modulemap').unlink()
        self.assertNotEqual(self.overlay().returncode, 0)
        self.assertFalse(self.out.exists())

    def test_symlink_map_refused(self):
        (self.inc/'module.modulemap').unlink()
        (self.inc/'module.modulemap').symlink_to('bridging.modulemap')
        self.assertNotEqual(self.overlay().returncode, 0)
        self.assertFalse(self.out.exists())

    def test_missing_header_refused(self):
        (self.inc/'bridging').unlink()
        self.assertNotEqual(self.overlay().returncode, 0)

    def test_existing_output_preserved(self):
        self.out.mkdir()
        sentinel = self.out/'overlay.json'
        sentinel.write_text('keep me')
        self.assertNotEqual(self.overlay().returncode, 0)
        self.assertEqual(sentinel.read_text(), 'keep me')

    def test_quoted_and_space_paths(self):
        new_inc = self.inc.parent/'include with "quote" and \\slash'
        self.inc.rename(new_inc)
        self.inc = new_inc
        self.assertEqual(self.overlay().returncode, 0)
        data = json.loads((self.out/'overlay.json').read_text())
        self.assertEqual(data['roots'][0]['name'], str(self.inc/'module.modulemap'))

    def run_preflight_fixture(self, fixture):
        run = self.base/'run'
        run.mkdir()
        shell = r'''set -euo pipefail
source "$1"
RB_RUN="$2"; RB_INCLUDE="$3"; RB_SDK=/synthetic-sdk; RB_VFS=""; RB_BRIDGING_MAP=""
FIXTURE="$4"
rb_probe() {
  local arch="$1" log="$2"
  if [[ "$FIXTURE" == "success" ]]; then : > "$log"; return 0; fi
  if [[ "$FIXTURE" == "unrelated" ]]; then echo "error: some other compiler problem" > "$log"; return 1; fi
  if [[ -n "$RB_VFS" ]]; then
    if [[ "$FIXTURE" == "retry-fails" ]]; then echo "error: retry also failed" > "$log"; return 1; fi
    : > "$log"; return 0
  fi
  printf "%s/module.modulemap:13:8: error: redefinition of module 'SwiftBridging'\n" "$RB_INCLUDE" > "$log"
  printf "%s/bridging.modulemap:13:8: note: previously defined here\n" "$RB_INCLUDE" >> "$log"
  return 1
}
rb_preflight arm64
'''
        return subprocess.run(['bash','-c',shell,'fixture',str(HELPER),str(run),str(self.inc),fixture],
                              capture_output=True,text=True,timeout=10),run

    def test_passing_preflight_does_not_make_overlay(self):
        result,run=self.run_preflight_fixture('success')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse((run/'compatibility').exists())

    def test_exact_error_retries_and_gates_success(self):
        result,run=self.run_preflight_fixture('duplicate')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue((run/'compatibility/overlay.json').exists())
        self.assertIn('PASS: compiler probe with the project-local',result.stdout)
        self.assertEqual(self.hashes(),self.before)

    def test_unrelated_error_never_masks_map(self):
        result,run=self.run_preflight_fixture('unrelated')
        self.assertEqual(result.returncode,2)
        self.assertFalse((run/'compatibility').exists())

    def test_retry_failure_is_not_reported_as_success(self):
        result,run=self.run_preflight_fixture('retry-fails')
        self.assertEqual(result.returncode,2)
        self.assertNotIn('PASS:',result.stdout)
        self.assertIn('retry also failed',result.stderr)

    def test_duplicate_error_with_unknown_map_stops(self):
        (self.inc/'module.modulemap').write_text(MAP+'module Important { header "bridging" }')
        result,run=self.run_preflight_fixture('duplicate')
        self.assertEqual(result.returncode,2)
        self.assertFalse((run/'compatibility').exists())

    @unittest.skipUnless(shutil.which('clang'), 'clang not installed')
    def test_clang_duplicate_fails_then_overlay_passes(self):
        source = self.base/'probe.c'
        source.write_text('#include "bridging"\nint answer(void) { return RBProbeValue; }\n')
        args = ['clang', '-fmodules', '-fimplicit-module-maps',
                '-fmodule-map-file='+str(self.inc/'bridging.modulemap'),
                '-fmodule-map-file='+str(self.inc/'module.modulemap'),
                '-I', str(self.inc), '-fsyntax-only', str(source)]
        before = subprocess.run(args+['-fmodules-cache-path='+str(self.base/'clang-baseline')],
                                capture_output=True, text=True, timeout=20)
        self.assertNotEqual(before.returncode, 0)
        self.assertIn("redefinition of module 'SwiftBridging'", before.stderr)
        self.assertEqual(self.overlay().returncode, 0)
        after = subprocess.run(args+['-ivfsoverlay', str(self.out/'overlay.json'),
                                '-fmodules-cache-path='+str(self.base/'clang-retry')],
                               capture_output=True, text=True, timeout=20)
        self.assertEqual(after.returncode, 0, after.stderr)
        self.assertEqual(self.hashes(), self.before)

    @unittest.skipUnless(shutil.which('swiftc'), 'swiftc not installed')
    def test_swift_duplicate_fails_then_overlay_passes(self):
        source = self.base/'probe.swift'
        source.write_text('import SwiftBridging\nlet answer = RBProbeValue\n')
        args = ['swiftc', '-typecheck', str(source), '-I', str(self.inc),
                '-Xcc', '-fmodule-map-file='+str(self.inc/'bridging.modulemap'),
                '-Xcc', '-fmodule-map-file='+str(self.inc/'module.modulemap')]
        before = subprocess.run(args+['-module-cache-path',str(self.base/'swift-baseline')],
                                capture_output=True, text=True, timeout=30)
        self.assertNotEqual(before.returncode, 0)
        self.assertIn("redefinition of module 'SwiftBridging'", before.stderr)
        self.assertEqual(self.overlay().returncode, 0)
        overlay = str(self.out/'overlay.json')
        after = subprocess.run(args+['-vfsoverlay',overlay,'-Xcc','-ivfsoverlay','-Xcc',overlay,
                                     '-module-cache-path',str(self.base/'swift-retry')],
                               capture_output=True, text=True, timeout=30)
        self.assertEqual(after.returncode, 0, after.stderr)
        self.assertEqual(self.hashes(), self.before)

if __name__ == '__main__':
    unittest.main(verbosity=2)
