#!/usr/bin/env python3
"""Build a no-network interactive GUIDE from the actual Swift catalog.
This is not RelayBar's native UI and deliberately executes no app actions.
"""
from pathlib import Path
import json, subprocess, tempfile
R=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
 exe=Path(tmp)/'catalog'
 subprocess.run(['swiftc','-swift-version','5','-parse-as-library',*map(str,sorted((R/'Sources/Core').glob('*.swift'))),str(R/'Scripts/export_button_families.swift'),'-o',str(exe)],check=True)
 catalog=json.loads(subprocess.check_output([str(exe)],text=True))
(R/'Docs/ButtonFamilies/FEATURE_MAP.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
template=(R/'Scripts/FamilyMap.template.html').read_text()
(R/'Button_Families_Map.html').write_text(template.replace('__CATALOG__',json.dumps(catalog,ensure_ascii=False).replace('</','<\\/')))
print('Built Button_Families_Map.html from',catalog['source'])
