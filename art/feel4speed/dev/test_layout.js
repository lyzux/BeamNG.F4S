/* Real Chromium/AngularJS 1.5.8 UI regression. This is not a BeamNG runtime test.
 * Usage: node art/feel4speed/dev/test_layout.js PROJECT_ROOT ANGULAR_1_5_8_JS [OUTPUT_DIR]
 * Requires Playwright and Chromium. Set CHROMIUM_PATH to use a local browser.
 * Obtain AngularJS 1.5.8 separately from its official distribution, for example
 * https://ajax.googleapis.com/ajax/libs/angularjs/1.5.8/angular.min.js
 * The game bridge and host are representative fixtures, not BeamNG internals.
 * Browser screenshots, downloaded libraries and browser binaries are not
 * part of the installable mod.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { chromium } = require('playwright');

const root = path.resolve(process.argv[2] || path.resolve(__dirname, '../../..'));
assert(process.argv[3], 'Supply the path to AngularJS 1.5.8: test_layout.js PROJECT_ROOT ANGULAR_1_5_8_JS [OUTPUT_DIR]');
const angularPath = path.resolve(process.argv[3]);
const output = path.resolve(process.argv[4] || path.join(require('os').tmpdir(), 'feel4speed-layout-results'));
// Focused fixture from Feel4Speed 0.1.0. The obsolete rules reproduce the
// full-height panel, large header and spacing seen in the reported screenshots.
// Loading these both before and after the release stylesheet catches accidental
// reliance on cascade order and missing release-specific selector specificity.
const oldCss = `
.f4s-app { color:#f6f7fa; background:rgba(16,21,28,.95); border:1px solid rgba(255,255,255,.14); border-radius:12px; font:13px/1.4 Arial,sans-serif; width:100%; height:100%; min-width:260px; box-sizing:border-box; display:flex; flex-direction:column; overflow:hidden; box-shadow:0 6px 22px rgba(0,0,0,.25); }
.f4s-app *, .f4s-app *:before, .f4s-app *:after { box-sizing:border-box; }
.f4s-app button, .f4s-app input { font:inherit; }
.f4s-app button { color:inherit; cursor:pointer; }
.f4s-app .f4s-header { display:flex; gap:10px; align-items:center; padding:16px; border-bottom:1px solid rgba(255,255,255,.08); }
.f4s-app .f4s-switch { width:36px; height:20px; display:block; position:relative; }
.f4s-app .f4s-scroll { overflow-y:auto; overflow-x:hidden; flex:1; min-height:0; padding:0 16px; }
.f4s-app .f4s-primary { padding:19px 0 17px; }
.f4s-app .f4s-telemetry { background:rgba(255,255,255,.035); border:1px solid rgba(255,255,255,.08); border-radius:8px; padding:12px; margin:0 0 15px; }
.f4s-app .f4s-camera { color:#9eabb9; font-size:11px; }
.f4s-app .f4s-presets { display:flex; gap:6px; margin-bottom:15px; }
.f4s-app .f4s-presets button { flex:1; padding:8px 2px; font-size:11px; border:1px solid #424d5a; background:#252e39; border-radius:5px; }
.f4s-app .f4s-intensity-bar { height:3px; margin:11px 0 9px; }
.f4s-app .f4s-slider-label { display:block; margin:0 0 18px; font-size:11px; }
.f4s-app .f4s-check { display:flex; gap:8px; align-items:center; font-size:11px; margin:12px 0 17px; }
.f4s-app .f4s-reset { width:100%; padding:8px; }
.f4s-app .f4s-footer { display:flex; gap:8px; align-items:center; padding:10px 16px; background:rgba(0,0,0,.1); }
.f4s-app.f4s-compact .f4s-header { padding:11px 16px; }
.f4s-app.f4s-compact .f4s-scroll { padding-top:14px; flex:0 0 auto; }
.f4s-app.f4s-compact .f4s-footer { flex:1; align-items:flex-start; }
`;
const angularSource = fs.readFileSync(angularPath, 'utf8');
const appDir = path.join(root, 'ui/modules/apps/Feel4Speed');
for (const name of ['app.js', 'app-v100.html', 'app-v100.css']) {
  assert(fs.existsSync(path.join(appDir, name)), 'Missing new UI asset: ' + name);
}
assert(angularSource.includes('1.5.8'), 'Harness must use actual AngularJS 1.5.8');
fs.mkdirSync(output, { recursive: true });

const standard = {
  enabled: true, extraFov: 40, startSpeed: 20, fullSpeed: 280,
  curve: 1.45, response: 0.25, vignette: 0.15, blur: 0.074,
  wobble: 0.12, postfxEnabled: true, fovLimit: 120, orbitOnly: true,
  activeEnabled: true, activeWhileDrifting: false, accelerationFov: 3.5, brakingFov: 3.5,
  accelerationDistance: 0.80, brakingDistance: 0.59,
  accelReference: 13.5, accelDeadzone: 1.4,
  springTime: 0.34, springDamping: 2,
  rpmWobble: 0.03, rpmStart: 1000, rpmFull: 6700,
  corneringEnabled: true, corneringStrength: 1.5, corneringLimit: 6,
  corneringDeadzone: 0.08, corneringResponse: 0.18, corneringWhileDrifting: false,
  corneringInvert: true
};
assert.strictEqual(Object.keys(standard).length,32,'Release fixture includes all 32 Standard settings');
const state = {
  settings: standard,
  telemetry: {
    speedKph: 80, extraFov: 9.3, fov: 75.3, strength: 0.23,
    camera: 'orbit', active: true, acceleration: 1.8, kickFov: 2,
    distanceOffset: 0.1, rpm: 4200, rpmAvailable: true,
    drifting: true, driftAvailable: true, slipAngle: 25, activeBlend: 0.2,
    lateralG: 0.65, corneringRoll: -1.5, corneringBlend: 0.2, corneringAvailable: true
  },
  status: {
    message: 'Active', postfx: 'enabled (GPU compilation not verified)', rpm: 'Engine RPM available',
    drift: 'Sliding: active feedback reduced', cornering: 'active'
  },
  version: '1.0.0'
};

function document(width, height) {
  return `<!doctype html><html><head><meta charset="utf-8">
  <style>
  html,body { margin:0; width:100%; height:100%; font-family:Arial,sans-serif; }
  body { background:linear-gradient(120deg,#94b977,#a58f64 55%,#75968f); }
  #game { position:fixed; inset:0; border:0; background:transparent; color:transparent; }
  #app-host { position:absolute; top:30px; left:30px; width:${width}px; height:${height}px; background:transparent; pointer-events:none; }
  #outside-target { position:absolute; top:180px; left:260px; width:80px; height:35px; background:#1f584d; color:#fff; }
  </style><style id="old-before">${oldCss}</style>
  <script src="/angular.js"></script><script>
  window.errors=[]; window.commands=[]; window.gameClicks=0;
  window.fixtureState=${JSON.stringify(state)};
  angular.module('beamng.apps',[]);
  window.bngApi={engineLua:function(command){
    window.commands.push(command);
    if(command.indexOf('requestState')!==-1 || command.indexOf('applyPreset')!==-1){
      setTimeout(function(){
        var root=angular.element(document.body).injector().get('$rootScope');
        root.$apply(function(){root.$broadcast('Feel4SpeedState',window.fixtureState)});
      },0);
    }
  }};
  </script><script src="/ui/modules/apps/Feel4Speed/app.js"></script>
  </head><body ng-app="beamng.apps">
  <button id="game" onclick="window.gameClicks++">Game view</button>
  <button id="outside-target" onclick="window.gameClicks++">Outside</button>
  <div id="app-host"><feel4-speed></feel4-speed></div>
  </body></html>`;
}

function rgb(str) {
  const m = str.match(/rgba?\(([^)]+)\)/);
  assert(m, 'Unrecognized computed color: ' + str);
  return m[1].split(',').map(Number);
}
function contrast(fg, bg) {
  function luminance(c) {
    const linear = c.slice(0,3).map(v => v/255).map(v => v<=0.04045 ? v/12.92 : Math.pow((v+0.055)/1.055,2.4));
    return 0.2126*linear[0]+0.7152*linear[1]+0.0722*linear[2];
  }
  const a=luminance(rgb(fg)), b=luminance(rgb(bg));
  return (Math.max(a,b)+0.05)/(Math.min(a,b)+0.05);
}

async function exerciseSliders(page, keys, label) {
  // Real pointer and keyboard actions verify every control can be reached
  // inside each host height; synthetic input alone would miss overlays.
  for(const key of keys) {
    const control=page.locator('input[ng-model="f4s.settings.'+key+'"]');
    await control.evaluate(el=>{
      const scroll=el.closest('.f4s-scroll'),a=el.parentElement.getBoundingClientRect(),b=scroll.getBoundingClientRect();
      scroll.scrollTop+=(a.top+a.bottom-b.top-b.bottom)/2;
    });
    const reachable=await control.evaluate(el=>{
      const a=el.getBoundingClientRect(),b=el.closest('.f4s-scroll').getBoundingClientRect(),text=el.parentElement.getBoundingClientRect();
      const hit=document.elementFromPoint(a.left+a.width*0.62,a.top+a.height/2);
      return { reachable:text.top>=b.top-0.5&&text.bottom<=b.bottom+0.5&&!el.disabled&&hit===el,
        label:{top:text.top,bottom:text.bottom},viewport:{top:b.top,bottom:b.bottom},hit:hit&&hit.tagName };
    });
    assert(reachable.reachable,label+': slider reachable and unobscured: '+key+' '+JSON.stringify(reachable));
    const before=await page.evaluate(key=>window.commands.filter(s=>s.includes("setSetting('"+key+"',")).length,key);
    const box=await control.boundingBox();
    await page.mouse.click(box.x+box.width*0.62,box.y+box.height/2);
    await control.press('ArrowRight');
    await page.waitForFunction(({key,before})=>window.commands.filter(s=>s.includes("setSetting('"+key+"',")).length>before,{key,before});
  }
}

(async () => {
  const browser = await chromium.launch({ headless:true, args:['--no-sandbox'],
    ...(process.env.CHROMIUM_PATH ? { executablePath:process.env.CHROMIUM_PATH } : {}) });
  const results=[];
  try {
    for (const scenario of [
      { name:'old-host', width:360, height:430 },
      { name:'new-host', width:320, height:350 },
      { name:'short-host', width:320, height:240 }
    ]) {
      const page=await browser.newPage({ viewport:{width:850,height:650}, deviceScaleFactor:1 });
      const errors=[];
      page.on('pageerror', e=>errors.push(e.message));
      await page.route('http://feel4speed.test/**', async route=>{
        const pathname=new URL(route.request().url()).pathname;
        if(pathname==='/') return route.fulfill({contentType:'text/html',body:document(scenario.width,scenario.height)});
        if(pathname==='/angular.js') return route.fulfill({contentType:'application/javascript',body:angularSource});
        const prefix='/ui/modules/apps/Feel4Speed/';
        if(pathname.startsWith(prefix)) {
          const name=path.basename(pathname);
          const file=path.join(appDir,name);
          if(fs.existsSync(file)) return route.fulfill({contentType:name.endsWith('.css')?'text/css':name.endsWith('.js')?'application/javascript':'text/html',body:fs.readFileSync(file)});
        }
        return route.fulfill({status:404,body:'Missing fixture route: '+pathname});
      });
      await page.goto('http://feel4speed.test/');
      assert.strictEqual(await page.evaluate(()=>angular.version.full),'1.5.8','Actual fixture Angular version');
      const app=page.locator('.f4s-v100');
      await app.waitFor();
      await page.waitForFunction(()=>angular.element(document.querySelector('.f4s-v100')).scope().f4s.ready);
      await page.waitForFunction(()=>[...document.styleSheets].some(s=>s.href&&s.href.includes('app-v100.css')));
      // Load an obsolete release AFTER the new release too, plus hostile global
      // native-button styling. A release-specific root must remain unaffected.
      await page.evaluate(css=>{
        const style=document.createElement('style'); style.id='old-after'; style.textContent=css; document.body.appendChild(style);
        const buttons=document.createElement('style'); buttons.textContent='button { background:#fff; color:#fff; border:2px solid #ddd; padding:4px 8px; }'; document.body.appendChild(buttons);
      },oldCss);
      // Applying the late old stylesheet can start the menu's 150ms background
      // transition. Observe the settled state, rather than an animation frame.
      await page.waitForFunction(()=>{
        const bg=getComputedStyle(document.querySelector('.f4s-v100')).backgroundColor;
        const numbers=bg.match(/[\d.]+/g).map(Number);
        return numbers.length===4 && numbers[3]<=0.3;
      });
      let bounds=await app.boundingBox();
      assert.strictEqual(Math.round(bounds.width),210,scenario.name+': compact width');
      assert.strictEqual(Math.round(bounds.height),28,scenario.name+': compact height');
      assert.strictEqual(await page.locator('.f4s-panel').count(),0,scenario.name+': body removed when minimized');
      const alpha=await app.evaluate(el=>getComputedStyle(el).backgroundColor);
      assert(rgb(alpha)[3]<=0.3,scenario.name+': compact background translucent: '+alpha);
      await page.locator('#outside-target').click();
      assert.strictEqual(await page.evaluate(()=>window.gameClicks),1,scenario.name+': unused saved-host space permits click');
      await page.locator('#outside-target').evaluate(el=>{el.style.visibility='hidden'});
      await page.mouse.move(700,550);
      await page.screenshot({path:path.join(output,scenario.name+'-compact.png')});

      await page.locator('.f4s-title').click();
      await page.locator('.f4s-panel').waitFor();
      assert.deepStrictEqual(await page.getByRole('tab').allTextContents(),['Camera','Active','Cornering','Effects'],scenario.name+': four compact tabs');
      bounds=await app.boundingBox();
      assert(Math.round(bounds.width)<=scenario.width,scenario.name+': expanded width fits host');
      assert(Math.round(bounds.height)<=scenario.height,scenario.name+': expanded height fits host');
      for(const selector of ['.f4s-title','.f4s-tabs button']) {
        const colors=await page.locator(selector).evaluateAll(els=>els.map(el=>({color:getComputedStyle(el).color,bg:getComputedStyle(el).backgroundColor,parentBg:getComputedStyle(el.closest('.f4s-v100')).backgroundColor})));
        for(const c of colors) {
          const bg=rgb(c.bg)[3]===0?c.parentBg:c.bg;
          assert(contrast(c.color,bg)>=4.5,scenario.name+': readable '+selector+' '+JSON.stringify(c));
        }
      }
      await page.screenshot({path:path.join(output,scenario.name+'-camera.png')});
      const scroll=page.locator('.f4s-scroll');
      const measurements=await scroll.evaluate(el=>({client:el.clientHeight,total:el.scrollHeight,overflow:getComputedStyle(el).overflowY}));
      assert(measurements.client>0,scenario.name+': positive settings scroll viewport');
      assert(measurements.overflow==='auto'||measurements.overflow==='scroll',scenario.name+': scroll enabled');
      if(scenario.height===240) {
        assert(measurements.total>measurements.client,scenario.name+': content exceeds short viewport');
        await scroll.hover(); await page.mouse.wheel(0,900);
        await page.waitForFunction(()=>document.querySelector('.f4s-scroll').scrollTop>0);
        const shown=await page.locator('input[aria-label="Speed wobble in degrees"]').evaluate(el=>{const a=el.getBoundingClientRect(),b=el.closest('.f4s-scroll').getBoundingClientRect();return a.top>=b.top&&a.bottom<=b.bottom});
        assert(shown,scenario.name+': wobble accessible after wheel scroll');
        const orbit=page.getByText('Orbit camera only',{exact:true});
        await orbit.click();
        assert((await page.evaluate(()=>window.commands)).some(s=>s.includes("setSetting('orbitOnly',false)")),scenario.name+': bottom control interactive');
        await page.screenshot({path:path.join(output,scenario.name+'-camera-scrolled.png')});
      }
      await page.getByRole('tab',{name:'Active',exact:true}).click();
      await page.locator('#f4s-active-panel').waitFor();
      await scroll.evaluate(el=>{el.scrollTop=0});
      const activeMeasurements=await scroll.evaluate(el=>({client:el.clientHeight,total:el.scrollHeight,overflow:getComputedStyle(el).overflowY}));
      assert(activeMeasurements.client>0,scenario.name+': positive Active scroll viewport');
      const activeKeys=['accelerationFov','brakingFov','accelerationDistance','brakingDistance',
        'accelReference','accelDeadzone','springTime','springDamping','rpmWobble','rpmStart','rpmFull'];
      const corneringKeys=['corneringStrength','corneringLimit','corneringDeadzone','corneringResponse'];
      assert.strictEqual(await page.locator('#f4s-active-panel input[type="range"]').count(),activeKeys.length,scenario.name+': all acceleration and RPM sliders present');
      for(const key of activeKeys) {
        assert.strictEqual(Number(await page.locator('input[ng-model="f4s.settings.'+key+'"]').inputValue()),standard[key],scenario.name+': Standard '+key);
      }
      assert.strictEqual(await page.getByRole('checkbox',{name:'Enable acceleration and braking feedback',exact:true}).isChecked(),true,scenario.name+': Active enabled by Standard');
      const driftCheckbox=page.getByRole('checkbox',{name:'Active feedback while drifting',exact:true});
      assert.strictEqual(await driftCheckbox.isChecked(),false,scenario.name+': feedback while drifting off by Standard');
      assert.strictEqual(await driftCheckbox.isDisabled(),false,scenario.name+': drift override available while feedback enabled');
      assert.strictEqual(await page.locator('#f4s-active-panel input[type="checkbox"]').count(),2,scenario.name+': both Active toggles present');
      assert.strictEqual(await page.locator('input[aria-label="RPM wobble in degrees"]').count(),1,scenario.name+': RPM wobble accessible name');
      assert.strictEqual(await page.locator('input[aria-label="Full RPM effect at"]').count(),1,scenario.name+': full RPM accessible name');
      const activeTelemetry=await app.evaluate(el=>angular.element(el).scope().f4s.telemetry);
      for(const key of ['acceleration','kickFov','distanceOffset','rpm','rpmAvailable','drifting','driftAvailable','slipAngle','activeBlend']) {
        assert.strictEqual(activeTelemetry[key],state.telemetry[key],scenario.name+': sanitized Active telemetry '+key);
      }
      assert.strictEqual(await app.evaluate(el=>angular.element(el).scope().f4s.status.drift),state.status.drift,scenario.name+': sanitized drift status');
      const driftStatus=page.locator('.f4s-drift-status');
      assert.strictEqual(await driftStatus.textContent(),'Drifting: passive blend',scenario.name+': clear reason for reduced active feedback while drifting');
      if(scenario.height>=350) {
        const firstVisible=await page.locator('input[ng-model="f4s.settings.accelerationFov"]').evaluate(el=>{
          const label=el.parentElement.getBoundingClientRect(),track=el.getBoundingClientRect(),viewport=el.closest('.f4s-scroll').getBoundingClientRect();
          return { visible:label.top>=viewport.top&&label.bottom<=viewport.bottom&&track.top>=viewport.top&&track.bottom<=viewport.bottom,
            label:{top:label.top,bottom:label.bottom},viewport:{top:viewport.top,bottom:viewport.bottom} };
        });
        assert(firstVisible.visible,scenario.name+': initial Active view shows first FOV label and track '+JSON.stringify(firstVisible));
      }
      await page.screenshot({path:path.join(output,scenario.name+'-active.png')});
      await driftCheckbox.check();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('activeWhileDrifting',true)")));
      assert.strictEqual(await driftStatus.textContent(),'Drifting: active feedback',scenario.name+': override changes the visible drift reason');
      await driftCheckbox.uncheck();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('activeWhileDrifting',false)")));
      assert.strictEqual(await driftStatus.textContent(),'Drifting: passive blend',scenario.name+': default drift reason restored');
      await page.evaluate(()=>{
        const echoed=angular.copy(window.fixtureState);
        echoed.telemetry.drifting=false;
        const scope=angular.element(document.body).injector().get('$rootScope');
        scope.$apply(()=>scope.$broadcast('Feel4SpeedState',echoed));
      });
      await page.waitForFunction(()=>document.querySelector('.f4s-drift-status').textContent==='Returning to active feedback');
      await scroll.evaluate(el=>{el.scrollTop=0});
      await page.screenshot({path:path.join(output,scenario.name+'-active-returning.png')});
      await page.evaluate(()=>{
        const scope=angular.element(document.body).injector().get('$rootScope');
        scope.$apply(()=>scope.$broadcast('Feel4SpeedState',window.fixtureState));
      });
      await page.waitForFunction(()=>document.querySelector('.f4s-drift-status').textContent==='Drifting: passive blend');
      if(scenario.height===240) {
        assert(activeMeasurements.total>activeMeasurements.client,scenario.name+': Active content exceeds short viewport');
        await scroll.hover(); await page.mouse.wheel(0,1800);
        await page.waitForFunction(()=>{
          const el=document.querySelector('.f4s-scroll');
          return el.scrollTop>0 && el.scrollTop+el.clientHeight>=el.scrollHeight-1;
        });
        // At absolute bottom the threshold row must be visible. The independent
        // wobble slider above is reached and exercised separately below.
        for(const key of ['rpmStart','rpmFull']) {
          const shown=await page.locator('input[ng-model="f4s.settings.'+key+'"]').evaluate(el=>{
            const a=el.parentElement.getBoundingClientRect(),b=el.closest('.f4s-scroll').getBoundingClientRect();
            return a.top>=b.top&&a.bottom<=b.bottom;
          });
          assert(shown,scenario.name+': bottom RPM control and label visible after wheel scroll: '+key);
        }
        // Include the threshold labels as well as their range tracks in the
        // visual evidence. A few pixels above absolute bottom keeps them whole.
        await page.locator('input[aria-label="Full RPM effect at"]').locator('..').scrollIntoViewIfNeeded();
        await page.screenshot({path:path.join(output,scenario.name+'-active-scrolled.png')});
      }
      await exerciseSliders(page,activeKeys,scenario.name+': Active');
      const activeCheckbox=page.getByRole('checkbox',{name:'Enable acceleration and braking feedback',exact:true});
      await activeCheckbox.uncheck();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('activeEnabled',false)")));
      assert.strictEqual(await driftCheckbox.isDisabled(),true,scenario.name+': drift override disabled with acceleration feedback off');
      for(const key of activeKeys.slice(0,8)) {
        assert.strictEqual(await page.locator('input[ng-model="f4s.settings.'+key+'"]').isDisabled(),true,scenario.name+': acceleration slider disabled with feedback off: '+key);
      }
      for(const key of activeKeys.slice(8)) {
        assert.strictEqual(await page.locator('input[ng-model="f4s.settings.'+key+'"]').isDisabled(),false,scenario.name+': RPM remains independent of feedback toggle: '+key);
      }
      await page.getByRole('tab',{name:'Cornering',exact:true}).click();
      await page.locator('#f4s-cornering-panel').waitFor();
      assert.strictEqual(await page.getByRole('checkbox',{name:'G-force camera roll',exact:true}).isChecked(),true,scenario.name+': Cornering stays enabled with Active feedback off');
      assert.strictEqual(await page.getByRole('checkbox',{name:'Roll while drifting',exact:true}).isDisabled(),false,scenario.name+': Cornering drift toggle independent of Active master');
      assert.strictEqual(await page.getByRole('checkbox',{name:'Invert roll direction',exact:true}).isDisabled(),false,scenario.name+': Cornering direction toggle independent of Active master');
      for(const key of corneringKeys) {
        assert.strictEqual(await page.locator('input[ng-model="f4s.settings.'+key+'"]').isDisabled(),false,scenario.name+': Cornering slider independent of Active master: '+key);
      }
      await page.getByRole('tab',{name:'Active',exact:true}).click();
      await page.locator('#f4s-active-panel').waitFor();
      const rpmCommands=await page.evaluate(()=>window.commands.filter(s=>s.includes("setSetting('rpmWobble',")).length);
      const independentRpm=page.locator('input[aria-label="RPM wobble in degrees"]');
      await independentRpm.scrollIntoViewIfNeeded();
      await independentRpm.click();
      await independentRpm.press('ArrowLeft');
      await page.waitForFunction(count=>window.commands.filter(s=>s.includes("setSetting('rpmWobble',")).length>count,rpmCommands);
      await activeCheckbox.check();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('activeEnabled',true)")));
      assert.strictEqual(await driftCheckbox.isDisabled(),false,scenario.name+': drift override available after acceleration feedback enabled');
      await page.getByRole('tab',{name:'Cornering',exact:true}).click();
      await page.locator('#f4s-cornering-panel').waitFor();
      await scroll.evaluate(el=>{el.scrollTop=0});
      const corneringMeasurements=await scroll.evaluate(el=>({client:el.clientHeight,total:el.scrollHeight,overflow:getComputedStyle(el).overflowY}));
      assert(corneringMeasurements.client>0,scenario.name+': positive Cornering viewport');
      const corneringMaster=page.getByRole('checkbox',{name:'G-force camera roll',exact:true});
      const corneringDrift=page.getByRole('checkbox',{name:'Roll while drifting',exact:true});
      const corneringInvert=page.getByRole('checkbox',{name:'Invert roll direction',exact:true});
      assert.strictEqual(await corneringMaster.isChecked(),true,scenario.name+': Cornering enabled by Standard');
      assert.strictEqual(await corneringDrift.isChecked(),false,scenario.name+': Cornering fades during drifting by Standard');
      assert.strictEqual(await corneringInvert.isChecked(),true,scenario.name+': inward roll direction enabled by Standard');
      assert.strictEqual(await corneringInvert.isDisabled(),false,scenario.name+': roll direction toggle available with Cornering enabled');
      const directionHint=page.locator('.f4s-cornering-hint');
      assert.strictEqual(await directionHint.textContent(),'Inward (Standard): force left leans left; right leans right.',scenario.name+': Standard direction explained by the visible hint');
      assert.strictEqual(await page.locator('#f4s-cornering-panel input[type="checkbox"]').count(),3,scenario.name+': all three Cornering toggles present');
      assert.strictEqual(await page.locator('#f4s-cornering-panel input[type="range"]').count(),4,scenario.name+': all four Cornering sliders present');
      for(const [key,aria] of Object.entries({
        corneringStrength:'Roll strength in degrees per G',corneringLimit:'Maximum cornering roll in degrees',
        corneringDeadzone:'Cornering G-force deadzone',corneringResponse:'Cornering smoothing in seconds'
      })) {
        assert.strictEqual(await page.locator('input[aria-label="'+aria+'"]').count(),1,scenario.name+': Cornering accessible name '+key);
        assert.strictEqual(Number(await page.locator('input[ng-model="f4s.settings.'+key+'"]').inputValue()),standard[key],scenario.name+': Standard '+key);
      }
      const corneringTelemetry=await app.evaluate(el=>angular.element(el).scope().f4s.telemetry);
      for(const key of ['lateralG','corneringRoll','corneringBlend','corneringAvailable']) {
        assert.strictEqual(corneringTelemetry[key],state.telemetry[key],scenario.name+': sanitized Cornering telemetry '+key);
      }
      assert.strictEqual(await app.evaluate(el=>angular.element(el).scope().f4s.status.cornering),state.status.cornering,scenario.name+': sanitized Cornering status');
      const corneringLive=await page.locator('.f4s-cornering-telemetry').textContent();
      assert(corneringLive.includes('Lateral force +0.65 g'),scenario.name+': signed lateral force visible');
      assert(corneringLive.includes('Applied roll -1.50\u00b0'),scenario.name+': signed applied roll visible');
      const corneringStatus=page.locator('.f4s-cornering-status');
      assert.strictEqual(await corneringStatus.textContent(),'Drifting: roll fades to neutral',scenario.name+': clear Cornering drift suppression reason');
      if(scenario.height>=350) {
        const firstVisible=await page.locator('input[ng-model="f4s.settings.corneringStrength"]').evaluate(el=>{
          const label=el.parentElement.getBoundingClientRect(),track=el.getBoundingClientRect(),viewport=el.closest('.f4s-scroll').getBoundingClientRect();
          return { visible:label.top>=viewport.top&&label.bottom<=viewport.bottom&&track.top>=viewport.top&&track.bottom<=viewport.bottom,
            label:{top:label.top,bottom:label.bottom},viewport:{top:viewport.top,bottom:viewport.bottom} };
        });
        assert(firstVisible.visible,scenario.name+': initial Cornering view shows first slider label and track '+JSON.stringify(firstVisible));
      }
      await page.screenshot({path:path.join(output,scenario.name+'-cornering.png')});
      if(scenario.height===240) {
        assert(corneringMeasurements.total>corneringMeasurements.client,scenario.name+': Cornering content exceeds short viewport');
        await scroll.hover(); await page.mouse.wheel(0,1800);
        await page.waitForFunction(()=>{
          const el=document.querySelector('.f4s-scroll');
          return el.scrollTop>0&&el.scrollTop+el.clientHeight>=el.scrollHeight-1;
        });
        const last=await page.locator('input[aria-label="Cornering smoothing in seconds"]').evaluate(el=>{
          const control=el.parentElement.getBoundingClientRect(),viewport=el.closest('.f4s-scroll').getBoundingClientRect();
          return control.top>=viewport.top&&control.bottom<=viewport.bottom;
        });
        assert(last,scenario.name+': last Cornering control and label visible at scroll bottom');
        assert(await corneringStatus.evaluate(el=>{
          const status=el.getBoundingClientRect(),viewport=el.closest('.f4s-scroll').getBoundingClientRect();
          return status.top>=viewport.top&&status.bottom<=viewport.bottom;
        }),scenario.name+': Cornering status fully reachable at 240px scroll bottom');
        await page.screenshot({path:path.join(output,scenario.name+'-cornering-scrolled.png')});
      }
      await corneringInvert.uncheck();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('corneringInvert',false)")));
      assert.strictEqual(await directionHint.textContent(),'Outward: force left leans right; right leans left.',scenario.name+': disabling inversion displays the previous outward direction');
      await scroll.evaluate(el=>{el.scrollTop=0});
      await page.screenshot({path:path.join(output,scenario.name+'-cornering-outward.png')});
      await corneringInvert.check();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('corneringInvert',true)")));
      assert.strictEqual(await directionHint.textContent(),'Inward (Standard): force left leans left; right leans right.',scenario.name+': restoring inversion displays Standard inward direction');
      await corneringDrift.check();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('corneringWhileDrifting',true)")));
      assert.strictEqual(await corneringStatus.textContent(),'Drifting: G-force roll',scenario.name+': Cornering override changes visible drift reason');
      await corneringDrift.uncheck();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('corneringWhileDrifting',false)")));
      await exerciseSliders(page,corneringKeys,scenario.name+': Cornering');
      await corneringMaster.uncheck();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('corneringEnabled',false)")));
      assert.strictEqual(await corneringStatus.textContent(),'G-force camera roll off',scenario.name+': clear Cornering off status');
      assert.strictEqual(await corneringDrift.isDisabled(),true,scenario.name+': Cornering drift toggle disabled by its master');
      assert.strictEqual(await corneringInvert.isDisabled(),true,scenario.name+': Cornering direction toggle disabled by its master');
      for(const key of corneringKeys) {
        assert.strictEqual(await page.locator('input[ng-model="f4s.settings.'+key+'"]').isDisabled(),true,scenario.name+': Cornering slider disabled by its master: '+key);
      }
      await page.getByRole('tab',{name:'Active',exact:true}).click();
      await page.locator('#f4s-active-panel').waitFor();
      assert.strictEqual(await activeCheckbox.isChecked(),true,scenario.name+': Active stays enabled with Cornering off');
      assert.strictEqual(await driftCheckbox.isDisabled(),false,scenario.name+': Active drift override independent of Cornering master');
      for(const key of activeKeys) {
        assert.strictEqual(await page.locator('input[ng-model="f4s.settings.'+key+'"]').isDisabled(),false,scenario.name+': Active/RPM slider independent of Cornering master: '+key);
      }
      await exerciseSliders(page,['accelerationFov','rpmWobble'],scenario.name+': Active/RPM with Cornering off');
      await page.getByRole('tab',{name:'Cornering',exact:true}).click();
      await page.locator('#f4s-cornering-panel').waitFor();
      await corneringMaster.check();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('corneringEnabled',true)")));
      assert.strictEqual(await corneringInvert.isDisabled(),false,scenario.name+': roll direction toggle restored with Cornering master');
      for(const key of corneringKeys) {
        assert.strictEqual(await page.locator('input[ng-model="f4s.settings.'+key+'"]').isDisabled(),false,scenario.name+': Cornering restored after master enabled: '+key);
      }
      await page.getByRole('tab',{name:'Effects',exact:true}).click();
      await page.locator('#f4s-effects-panel').waitFor();
      assert.strictEqual(await page.locator('input[aria-label="Vignette intensity"]').inputValue(),'0.15',scenario.name+': Standard vignette15%');
      assert.strictEqual(await page.locator('input[aria-label="Edge blur amount"]').inputValue(),'0.074',scenario.name+': Standard blur');
      await scroll.evaluate(el=>{el.scrollTop=0});
      await page.screenshot({path:path.join(output,scenario.name+'-effects.png')});
      await page.locator('input[aria-label="Vignette intensity"]').evaluate(el=>{el.value='0.16';el.dispatchEvent(new Event('input',{bubbles:true}));});
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("setSetting('vignette',0.16)")));
      await page.getByRole('button',{name:'Standard',exact:true}).click();
      await page.waitForFunction(()=>window.commands.some(s=>s.includes("applyPreset('standard')")));
      await page.waitForFunction(()=>document.querySelector('input[aria-label="Vignette intensity"]').value==='0.15');
      assert.deepStrictEqual(await app.evaluate(el=>angular.element(el).scope().f4s.settings),standard,scenario.name+': Standard echo restores the exact complete profile');
      await page.locator('.f4s-title').click();
      bounds=await app.boundingBox();
      assert.strictEqual(Math.round(bounds.height),28,scenario.name+': compact after Effects');
      assert.deepStrictEqual(errors,[],scenario.name+': Angular/browser errors');
      results.push({scenario:scenario.name,compact:{width:210,height:28},scroll:measurements,activeScroll:activeMeasurements,activeControls:activeKeys.length+2,corneringScroll:corneringMeasurements,corneringControls:corneringKeys.length+3,errors});
      await page.close();
    }
    fs.writeFileSync(path.join(output,'results.json'),JSON.stringify({angular:'1.5.8',chromium:browser.version(),passed:results.length,results},null,2));
    console.log(JSON.stringify({passed:results.length,angular:'1.5.8',chromium:browser.version(),output,results},null,2));
  } finally { await browser.close(); }
})().catch(e=>{console.error(e.stack);process.exitCode=1});
