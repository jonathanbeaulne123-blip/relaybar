#!/usr/bin/env python3
"""Execute the actual Bash recovery flow with explicitly doubled macOS commands.
This is not a macOS/TCC test. Absolute Apple command paths in a temporary copy
are replaced with stand-ins; the delivered .command has no test overrides.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Repair_Permission.command"
MOCK = r'''#!/usr/bin/env python3
import hashlib, json, os, pathlib, plistlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
base = pathlib.Path(os.environ["FIXTURE_BASE"])
config = json.loads((base / "config.json").read_text())
with (base / "calls.jsonl").open("a") as f:
    f.write(json.dumps([name, *args])+"\n")
app = pathlib.Path(os.environ["HOME"]) / "Applications" / "RelayBar.app"
if name == "uname":
    print(config.get("platform", "Darwin"))
elif name == "id":
    print(config.get("uid", "501"))
elif name == "PlistBuddy":
    try:
        key=args[1].split(":",1)[1]
        print(plistlib.loads(pathlib.Path(args[2]).read_bytes())[key])
    except Exception:
        sys.exit(1)
elif name == "codesign":
    if "--verify" in args:
        sys.exit(config.get("signature_exit",0))
    digest=hashlib.sha256((app/"Contents/MacOS/RelayBar").read_bytes()).hexdigest()[:40]
    if "-r-" in args:
        print('Executable='+str(app/'Contents/MacOS/RelayBar'),file=sys.stderr)
        print('designated => cdhash H"'+digest+'"',file=sys.stderr)
    else:
        print('Executable='+str(app/'Contents/MacOS/RelayBar'),file=sys.stderr)
        print('Identifier=local.relaybar\nSignature=adhoc\nCDHash='+digest+'\nTeamIdentifier=not set',file=sys.stderr)
elif name == "pgrep":
    if config.get("pgrep_error"):
        sys.exit(2)
    statefile=base/("pgrep-"+args[-1].replace(" ","_"))
    count=int(statefile.read_text())+1 if statefile.exists() else 1
    statefile.write_text(str(count))
    running=config.get("running",{})
    sequence=running.get(args[-1],[])
    active=sequence[min(count-1,len(sequence)-1)] if sequence else False
    if active: print(1234)
    sys.exit(0 if active else 1)
elif name == "tccutil":
    assert args == ["reset","Accessibility","local.relaybar"], args
    status=config.get("reset_exit",0)
    print('Synthetic reset failure' if status else 'Synthetic: reset Accessibility for local.relaybar')
    sys.exit(status)
elif name == "open":
    status=config.get("open_exit",0)
    if args and args[0].startswith("x-apple.") and config.get("change_after_reset"):
        with (app/"Contents/MacOS/RelayBar").open("ab") as f:
            f.write(b'fixture-changed-after-approval')
    sys.exit(status)
else:
    raise SystemExit('unknown stand-in '+name)
'''

class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="relaybar-recovery-test-")
        self.base = Path(self.tmp.name)
        # Deliberately awkward path to exercise quoting; no command is executed.
        self.home = self.base / "User Home ; literal $NOT_A_VAR"
        self.app = self.home / "Applications/RelayBar.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        self.bin = self.app / "Contents/MacOS/RelayBar"
        self.bin.write_bytes(b"synthetic fixture executable; never run\n")
        self.bin.chmod(0o755)
        self.plist = self.app / "Contents/Info.plist"
        self.data = {"CFBundleIdentifier":"local.relaybar", "CFBundleExecutable":"RelayBar",
                     "CFBundleShortVersionString":"0.9.1", "CFBundleVersion":"17"}
        self.write_plist()
        self.runroot = self.base / "Recovery Tool"
        self.runroot.mkdir()
        self.script = self.runroot / "Repair_Permission.command"
        self.mockroot = self.base / "mocks"
        self.mockroot.mkdir()
        text = SOURCE.read_text()
        for absolute in ("/usr/bin/uname", "/usr/bin/id", "/usr/libexec/PlistBuddy",
                         "/usr/bin/codesign", "/usr/bin/pgrep", "/usr/bin/tccutil", "/usr/bin/open"):
            path = self.mockroot / Path(absolute).name
            path.write_text(MOCK)
            path.chmod(0o755)
            text = text.replace(absolute, str(path))
        self.script.write_text(text)
        self.config: dict = {}

    def tearDown(self):
        self.tmp.cleanup()

    def write_plist(self):
        self.plist.write_bytes(plistlib.dumps(self.data))

    def run_flow(self, answers="", args=()):
        (self.base/"config.json").write_text(json.dumps(self.config))
        env = dict(os.environ, HOME=str(self.home), FIXTURE_BASE=str(self.base))
        self.before = {str(p.relative_to(self.app)):hashlib.sha256(p.read_bytes()).hexdigest()
                       for p in self.app.rglob("*") if p.is_file()}
        self.result = subprocess.run(["/bin/bash",str(self.script),*args],input=answers,
            text=True,capture_output=True,env=env,timeout=8)
        log = self.base/"calls.jsonl"
        self.calls = [json.loads(s) for s in log.read_text().splitlines()] if log.exists() else []
        self.resets = [c for c in self.calls if c[0] == "tccutil"]
        self.launches = [c for c in self.calls if c[:2] == ["open","-a"]]
        return self.result

    def report(self):
        paths=list(self.runroot.glob("RecoveryReport.*/Report.txt"))
        return paths[0].read_text() if paths else ""

    def assert_untouched(self):
        after={str(p.relative_to(self.app)):hashlib.sha256(p.read_bytes()).hexdigest()
               for p in self.app.rglob("*") if p.is_file()}
        self.assertEqual(self.before,after)

    def assert_stopped_without_reset(self):
        self.assertNotEqual(self.result.returncode,0,self.result.stdout+self.result.stderr)
        self.assertEqual(self.resets,[])
        self.assertEqual(self.launches,[])

    def test_success_sequence_exact_reset_and_exact_launch_no_success_claim(self):
        r=self.run_flow("RESET\nOPEN\n")
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(self.resets,[["tccutil","reset","Accessibility","local.relaybar"]])
        self.assertEqual(self.launches,[["open","-a",str(self.app)]])
        opened=[c for c in self.calls if c[0]=="open"]
        self.assertEqual(len(opened),3)
        self.assertEqual(opened[1],["open","-R",str(self.app)])
        self.assertIn("NOT VERIFIED",self.report())
        self.assertNotIn(str(self.home),self.report())
        self.assert_untouched()

    def test_cancel_does_not_reset_or_launch(self):
        r=self.run_flow("\n")
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.resets,[]);self.assertEqual(self.launches,[])
        self.assert_untouched()

    def test_reset_word_is_explicit(self):
        self.run_flow("yes\n")
        self.assertEqual(self.resets,[])

    def test_eof_before_consent_is_cancel(self):
        self.run_flow("")
        self.assertEqual(self.resets,[])
        self.assertEqual(self.result.returncode,0)

    def test_linux_refused_before_mac_calls(self):
        self.config["platform"]="Linux"
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()
        self.assertEqual(self.calls,[["uname","-s"]])

    def test_root_refused(self):
        self.config["uid"]="0"
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_wrong_version_refused(self):
        self.data["CFBundleShortVersionString"]="0.6.0"; self.write_plist()
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_wrong_build_refused(self):
        self.data["CFBundleVersion"]="9"; self.write_plist()
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_unrelated_bundle_refused(self):
        self.data["CFBundleIdentifier"]="com.example.other"; self.write_plist()
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_unexpected_executable_refused(self):
        self.data["CFBundleExecutable"]="Other"; self.write_plist()
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_app_symlink_refused(self):
        target=self.app.with_name("Actual.app");self.app.rename(target);self.app.symlink_to(target)
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_executable_symlink_refused(self):
        target=self.bin.with_name("Other");self.bin.rename(target);self.bin.symlink_to(target)
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_invalid_signature_refused(self):
        self.config["signature_exit"]=1
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_running_app_refused_without_termination(self):
        self.config["running"]={"RelayBar":[True]}
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_settings_must_be_closed_before_reset(self):
        self.config["running"]={"System Settings":[True]}
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_process_query_failure_refused(self):
        self.config["pgrep_error"]=True
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_app_started_during_consent_refused(self):
        self.config["running"]={"RelayBar":[False,True]}
        self.run_flow("RESET\nOPEN\n"); self.assert_stopped_without_reset()

    def test_reset_failure_no_retry_or_open(self):
        self.config["reset_exit"]=1
        self.run_flow("RESET\nOPEN\n")
        self.assertNotEqual(self.result.returncode,0)
        self.assertEqual(len(self.resets),1);self.assertEqual(self.launches,[])
        self.assertFalse(any(c[0]=="open" for c in self.calls))
        self.assertIn("Synthetic reset failure",self.result.stdout)
        self.assert_untouched()

    def test_cancel_after_reset_does_not_launch(self):
        r=self.run_flow("RESET\n\n")
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(len(self.resets),1);self.assertEqual(self.launches,[])
        self.assert_untouched()

    def test_open_error_no_retry(self):
        self.config["open_exit"]=1
        self.run_flow("RESET\nOPEN\n")
        self.assertNotEqual(self.result.returncode,0)
        self.assertEqual(len(self.resets),1);self.assertEqual(self.launches,[])
        self.assertEqual(len([c for c in self.calls if c[0]=="open"]),1)

    def test_new_process_after_approval_no_reset_or_launch_retry(self):
        self.config["running"]={"RelayBar":[False,False,True]}
        self.run_flow("RESET\nOPEN\n")
        self.assertNotEqual(self.result.returncode,0)
        self.assertEqual(len(self.resets),1);self.assertEqual(self.launches,[])

    def test_app_changed_after_approval_blocks_launch(self):
        self.config["change_after_reset"]=True
        self.run_flow("RESET\nOPEN\n")
        self.assertNotEqual(self.result.returncode,0)
        self.assertEqual(len(self.resets),1);self.assertEqual(self.launches,[])
        self.assertIn("app changed after approval",self.result.stderr)

    def test_arguments_refused(self):
        self.run_flow("RESET\n",args=("--force",)); self.assert_stopped_without_reset()

    def test_delivered_script_no_signing_build_or_privilege_bypass(self):
        text=SOURCE.read_text()
        for prohibited in ["--sign ","--force ","xattr ","spctl ","csrutil ",
                           "killall ","pkill ","/bin/kill", "tccutil reset All",
                           '"$BIN" --diagnostics', "sqlite3 ","osascript ","swiftc "]:
            self.assertNotIn(prohibited,text)
        self.assertIsNone(re.search(r"(?m)^\s*(?:/usr/bin/)?sudo\s", text))
        self.assertEqual(text.count('RESET_OUTPUT="$(/usr/bin/tccutil reset Accessibility local.relaybar'),1)
        self.assertIn('/usr/bin/open -a "$APP"',text)

if __name__ == "__main__":
    unittest.main(verbosity=2)
