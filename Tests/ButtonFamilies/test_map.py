#!/usr/bin/env python3
"""Offline browser check for the interactive GUIDE, not native Touch Bar evidence."""
from pathlib import Path
import json, shutil
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[2]; out=R/'Docs/ButtonFamilies';out.mkdir(parents=True,exist_ok=True)
checks=[];requests=[];errors=[]
def check(value,name):
 if not value:raise AssertionError(name)
 checks.append(name)
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True, executable_path=shutil.which('chromium'))
 page=browser.new_page(viewport={'width':1280,'height':920})
 page.on('request',lambda r:requests.append(r.url));page.on('pageerror',lambda e:errors.append(str(e)))
 page.route('**/*',lambda route:route.abort())
 page.set_content((R/'Button_Families_Map.html').read_text(),wait_until='load')
 check(page.locator('#cards .card').count()==5,'Home has exactly five families')
 check(page.locator('#heading').inner_text()=='Home','Starts at Home')
 page.locator('#bar button',has_text='Prompting').click()
 check(page.locator('#heading').inner_text()=='Prompting','Prompting folder opens')
 for title in ['Next slice','Challenge','Handoff']:
  check(page.locator('#bar button',has_text=title).count()==1,title+' stays in Prompting')
 page.locator('#bar button',has_text='Challenge').click()
 check('Nothing was executed' in page.locator('#feedback').inner_text(),'Guide actions do not pretend to execute')
 check(page.locator('#heading').inner_text()=='Prompting','Action explanation keeps page')
 page.screenshot(path=str(out/'GUIDE_DESKTOP.png'),full_page=True)
 page.locator('#bar button',has_text='More prompts').click()
 page.locator('#bar button',has_text='Build & review').click()
 check(page.locator('#heading').inner_text()=='Build & review','Nested prompt family reachable')
 page.locator('#bar button',has_text='Back').click()
 check(page.locator('#heading').inner_text()=='More prompts','Back goes to parent not Home')
 page.keyboard.press('Escape');check(page.locator('#heading').inner_text()=='Prompting','Escape goes back')
 page.locator('#bar button',has_text='Home').click();check(page.locator('#heading').inner_text()=='Home','Home button goes to root')
 for item in json.loads((out/'FEATURE_MAP.json').read_text())['pages']:
  page.evaluate('(id)=>go(id)',item['id']);check(page.locator('#heading').inner_text()==item['title'],'Catalog page renders: '+item['id'])
 check(page.evaluate('document.documentElement.scrollWidth<=innerWidth'),'Desktop has no horizontal overflow')
 page.set_viewport_size({'width':390,'height':844});page.evaluate('go("prompting")')
 check(page.locator('#cards .card').count()==5,'Phone retains all Prompting items')
 check(page.evaluate('document.documentElement.scrollWidth<=innerWidth'),'Phone has no horizontal overflow')
 page.screenshot(path=str(out/'GUIDE_PHONE.png'),full_page=True)
 check(not requests,'Zero observed runtime network requests')
 check(not errors,'Zero observed JavaScript exceptions')
 browser.close()
result={'boundary':'Offline Chromium set_content of guide HTML only; NOT native AppKit, Touch Bar, installed Mac, or live provider validation.','passed':len(checks),'failed':0,'requests':requests,'errors':errors,'checks':checks}
(out/'MAP_TEST_RESULTS.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
