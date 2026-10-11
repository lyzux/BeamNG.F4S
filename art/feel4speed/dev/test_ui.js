'use strict';

// Run from the mod root: node art/feel4speed/dev/test_ui.js
// This verifies the app's bridge and state logic without pretending to run
// BeamNG's AngularJS host or renderer.
var fs = require('fs');
var path = require('path');
var vm = require('vm');
var assert = require('assert');
var modRoot = path.resolve(__dirname, '../../..');
var source = fs.readFileSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app.js'), 'utf8');
var metadata = JSON.parse(fs.readFileSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app.json'), 'utf8'));
var template = fs.readFileSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v100.html'), 'utf8');
var css = fs.readFileSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v100.css'), 'utf8');
var timers = new Set();
var listeners = {};
var sent = [];
var directive;

function timeout(fn, ms) {
  var timer = { fn: fn, ms: ms };
  timers.add(timer);
  return timer;
}
timeout.cancel = function (timer) { return timers.delete(timer); };
function tick(ms) {
  Array.from(timers).forEach(function (timer) {
    if (timer.ms <= ms) { timers.delete(timer); timer.fn(); }
  });
}

var scope = {
  $on: function (name, fn) {
    listeners[name] = fn;
    return function () { delete listeners[name]; };
  },
  $evalAsync: function (fn) { fn(); }
};
vm.runInNewContext(source, {
  angular: {
    copy: function (obj) { return JSON.parse(JSON.stringify(obj)); },
    module: function (name) {
      assert.equal(name, 'beamng.apps');
      return { directive: function (name, definition) {
        assert.equal(name, metadata.directive);
        directive = definition[definition.length - 1](timeout);
      } };
    }
  },
  bngApi: { engineLua: function (command) { sent.push(command); } },
  Date: Date, Object: Object, Math: Math, String: String, isFinite: isFinite
});
assert.equal(directive.templateUrl, '/ui/modules/apps/Feel4Speed/app-v100.html');
assert.equal(directive.require, undefined, 'the app does not depend on host controller internals');
directive.link(scope);
assert.equal(sent[0], "extensions.load('feel4speed_main'); if feel4speed_main then feel4speed_main.requestState() end");
assert.equal(scope.f4s.version, metadata.version);
assert.equal(metadata.version, '1.0.0');
assert.equal(metadata.css.width, '320px');
assert.equal(metadata.css.height, '350px');
assert.deepStrictEqual(scope.f4s.settings, {
  enabled: true, extraFov: 40, startSpeed: 20, fullSpeed: 280,
  curve: 1.45, response: 0.25, vignette: 0.15, blur: 0.074,
  wobble: 0.12, postfxEnabled: true, fovLimit: 120, orbitOnly: true,
  activeEnabled: true, activeWhileDrifting: false, accelerationFov: 3.5, brakingFov: 3.5,
  accelerationDistance: 0.80, brakingDistance: 0.59,
  accelReference: 13.5, accelDeadzone: 1.4, springTime: 0.34,
  springDamping: 2.00, rpmWobble: 0.03, rpmStart: 1000, rpmFull: 6700,
  corneringEnabled: true, corneringStrength: 1.5, corneringLimit: 6,
  corneringDeadzone: 0.08, corneringResponse: 0.18, corneringWhileDrifting: false,
  corneringInvert: true
}, 'UI starts with the user-approved Standard settings');
assert.equal(Object.keys(scope.f4s.settings).length, 32, 'complete drift/cornering settings contract');
assert.equal(scope.f4sCorneringHint(), 'Inward (Standard): force left leans left; right leans right.', 'Standard explains its inward roll');
scope.f4s.settings.corneringInvert = false;
assert.equal(scope.f4sCorneringHint(), 'Outward: force left leans right; right leans left.', 'the unchecked option explains legacy outward roll');
scope.f4s.settings.corneringInvert = true;
assert.equal(scope.f4s.compact, true, 'app opens as a small minimized titlebar');
assert.equal(scope.f4s.tab, 'camera');
scope.f4sToggleCompact();
assert.equal(scope.f4s.compact, false);
scope.f4sTab('active');
assert.equal(scope.f4s.tab, 'active');
scope.f4sTab('cornering');
assert.equal(scope.f4s.tab, 'cornering');
scope.f4sTab('effects');
assert.equal(scope.f4s.tab, 'effects');
scope.f4sTab('injected');
assert.equal(scope.f4s.tab, 'effects', 'only known tabs are accepted');
scope.f4sToggleCompact();
assert.equal(scope.f4s.compact, true);
assert.equal(scope.f4s.tab, 'effects', 'minimizing preserves the active tab');
scope.f4sTab('camera');
assert.equal(sent.length, 1, 'local menu navigation does not modify the engine');
assert.ok(template.includes('class="f4s-panel" ng-if="!f4s.compact"'), 'compact mode removes the whole body from the DOM');
assert.ok(template.includes("f4sPreset('standard')"));
assert.ok(template.includes("ng-if=\"f4s.tab === 'effects'\""));
assert.ok(template.includes("ng-if=\"f4s.tab === 'active'\""));
assert.ok(template.includes("ng-if=\"f4s.tab === 'cornering'\""));
assert.ok(template.includes('Speed wobble'), 'road-speed wobble is distinguished from engine RPM wobble');
assert.ok(template.includes('aria-label="Active feedback while drifting"'));
assert.ok(template.includes('aria-label="G-force camera roll"'));
assert.ok(template.includes('aria-label="Roll while drifting"'));
assert.ok(template.includes('aria-label="Invert roll direction"'));
assert.ok(template.includes('ng-model="f4s.settings.corneringInvert" ng-change="f4sChange(\'corneringInvert\')" ng-disabled="!f4s.settings.corneringEnabled"'), 'roll inversion follows only the cornering master');
assert.ok(template.includes('class="f4s-hint f4s-cornering-hint">{{f4sCorneringHint()}}'));
assert.ok(template.includes('Standard leans into corners: force left leans left; force right leans right.'), 'the tooltip communicates the new inward Standard');
assert.ok(/\.f4s-app\.f4s-v100\.f4s-compact \{[^}]*width: 210px;[^}]*height: 28px;[^}]*rgba\(15, 20, 26, 0\.20\)/.test(css), 'transparent compact panel is 210x28');
assert.ok(template.includes('class="f4s-app f4s-v100"'), 'new selectors do not share the old stylesheet namespace');
assert.ok(template.includes('/ui/modules/apps/Feel4Speed/app-v100.css'));
assert.ok(template.includes('Feel4Speed UI 1.0.0'), 'titlebar tooltip identifies the actual UI release');
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app.html')));
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app.css')), 'old cache-prone asset names are not shipped');
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v012.html')));
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v012.css')));
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v020.html')));
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v020.css')));
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v021.html')));
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v021.css')));
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v022.html')));
assert.ok(!fs.existsSync(path.join(modRoot, 'ui/modules/apps/Feel4Speed/app-v022.css')));
assert.ok(!/beta/i.test(source + template + css + JSON.stringify(metadata)), 'the stable UI release contains no beta strings');
assert.ok(css.includes('-webkit-appearance: none; appearance: none; color: #f2f5f7; background: transparent;'));
assert.ok(css.includes('.f4s-panel { display: flex; flex: 1 1 0; overflow: hidden; flex-direction: column; min-height: 0; }'));
assert.ok(css.includes('overflow-y: auto; overflow-x: hidden; flex: 1 1 0; min-height: 0;'));
assert.ok(!source.includes('appHost') && !css.includes('f4s-host'), 'do not mutate BeamNG host styles or controllers');

var state = {
  settings: {extraFov: 40, fullSpeed: 280, startSpeed: 20, enabled: true},
  telemetry: {speedKph: 130, extraFov: 15.2, fov: 105, strength: 0.4, camera: 'orbit', active: true,
    acceleration: 1.8, kickFov: 2, distanceOffset: 0.1, rpm: 4200, rpmAvailable: true,
    drifting: true, driftAvailable: true, slipAngle: 25, activeBlend: 0.2,
    lateralG: 0.65, corneringRoll: -1.5, corneringBlend: 0.2, corneringAvailable: true},
  status: {message: 'Active', postfx: 'Ready', rpm: 'Engine sensor available', drift: 'Drift blend active', cornering: 'Cornering sensor ready'}
};
listeners.Feel4SpeedState(null, state);
assert.equal(scope.f4s.ready, true);
assert.equal(scope.f4sStrength(), 40);
assert.equal(scope.f4sNumber(NaN), '--');
assert.equal(scope.f4sSigned(NaN, 2), '--');
assert.equal(scope.f4sSigned(0.1, 2), '+0.10');
assert.equal(scope.f4sSigned(-0.1, 2), '-0.10');
assert.equal(scope.f4s.telemetry.acceleration, 1.8);
assert.equal(scope.f4s.telemetry.kickFov, 2);
assert.equal(scope.f4s.telemetry.distanceOffset, 0.1);
assert.equal(scope.f4s.telemetry.rpm, 4200);
assert.equal(scope.f4s.telemetry.rpmAvailable, true);
assert.equal(scope.f4s.status.rpm, 'Engine sensor available');
assert.equal(scope.f4s.telemetry.drifting, true);
assert.equal(scope.f4s.telemetry.driftAvailable, true);
assert.equal(scope.f4s.telemetry.slipAngle, 25);
assert.equal(scope.f4s.telemetry.activeBlend, 0.2);
assert.equal(scope.f4s.status.drift, 'Drift blend active');
assert.equal(scope.f4s.telemetry.lateralG, 0.65);
assert.equal(scope.f4s.telemetry.corneringRoll, -1.5);
assert.equal(scope.f4s.telemetry.corneringBlend, 0.2);
assert.equal(scope.f4s.telemetry.corneringAvailable, true);
assert.equal(scope.f4s.status.cornering, 'Cornering sensor ready');
assert.equal(scope.f4sCorneringStatus(), 'Drifting: roll fades to neutral');
scope.f4s.settings.corneringWhileDrifting = true;
assert.equal(scope.f4sCorneringStatus(), 'Drifting: G-force roll');
scope.f4s.settings.corneringWhileDrifting = false;
scope.f4s.telemetry.drifting = false;
assert.equal(scope.f4sCorneringStatus(), 'Returning to G-force roll');
scope.f4s.telemetry.corneringBlend = 1;
assert.equal(scope.f4sCorneringStatus(), 'G-force camera roll ready');
scope.f4s.telemetry.corneringAvailable = false;
scope.f4s.telemetry.speedKph = 0;
assert.equal(scope.f4sCorneringStatus(), '', 'cornering does not warn at normal standstill');
scope.f4s.telemetry.speedKph = 80;
scope.f4s.status.cornering = 'Waiting for motion sample';
assert.equal(scope.f4sCorneringStatus(), 'Waiting for cornering motion', 'first motion sample is not a sensor failure');
scope.f4s.status.cornering = 'priming';
assert.equal(scope.f4sCorneringStatus(), 'Waiting for cornering motion');
scope.f4s.status.cornering = 'idle';
assert.equal(scope.f4sCorneringStatus(), 'Waiting for cornering motion');
scope.f4s.status.cornering = 'disabled';
assert.equal(scope.f4sCorneringStatus(), 'G-force camera roll off');
scope.f4s.status.cornering = 'Invalid velocity API';
assert.equal(scope.f4sCorneringStatus(), 'Cornering feedback unavailable');
scope.f4s.status.cornering = 'rotation unavailable';
assert.equal(scope.f4sCorneringStatus(), 'Cornering feedback unavailable');
scope.f4s.settings.corneringEnabled = false;
assert.equal(scope.f4sCorneringStatus(), 'G-force camera roll off');
assert.equal(scope.f4s.settings.activeEnabled, true, 'disabling cornering leaves acceleration feedback unchanged');
assert.equal(scope.f4s.settings.rpmWobble, 0.03, 'disabling cornering leaves RPM settings unchanged');
scope.f4s.settings.corneringEnabled = true;
scope.f4s.telemetry.corneringAvailable = true;
scope.f4s.telemetry.speedKph = 130;
scope.f4s.telemetry.drifting = true;
assert.equal(scope.f4sDriftStatus(), 'Drifting: passive blend');
scope.f4s.settings.activeWhileDrifting = true;
assert.equal(scope.f4sDriftStatus(), 'Drifting: active feedback');
scope.f4s.settings.activeWhileDrifting = false;
scope.f4s.telemetry.drifting = false;
assert.equal(scope.f4sDriftStatus(), 'Returning to active feedback');
scope.f4s.telemetry.activeBlend = 1;
assert.equal(scope.f4sDriftStatus(), '', 'settled feedback does not show an old blend warning');
scope.f4s.telemetry.driftAvailable = false;
assert.equal(scope.f4sDriftStatus(), 'Drift detection unavailable');
scope.f4s.telemetry.speedKph = 0;
assert.equal(scope.f4sDriftStatus(), '', 'standstill has no velocity heading and is not a drift API failure');
scope.f4s.telemetry.speedKph = 0.9;
assert.equal(scope.f4sDriftStatus(), '', 'near standstill also suppresses the false warning');
scope.f4s.telemetry.speedKph = 1;
assert.equal(scope.f4sDriftStatus(), 'Drift detection unavailable', 'moving cars still report unavailable drift information');
scope.f4s.telemetry.speedKph = 130;
scope.f4s.telemetry.driftAvailable = true;
scope.f4s.telemetry.drifting = true;
assert.equal(scope.f4sRpmStatus(), 'Engine RPM ready');
scope.f4s.settings.activeEnabled = false;
assert.equal(scope.f4sDriftStatus(), '', 'disabled acceleration feedback suppresses drift blend status');
assert.equal(scope.f4sCorneringStatus(), 'Drifting: roll fades to neutral', 'cornering stays active with acceleration feedback disabled');
assert.equal(scope.f4sRpmStatus(), 'Engine RPM ready', 'RPM is independent of acceleration/braking feedback');
scope.f4s.settings.activeEnabled = true;
scope.f4s.telemetry.rpmAvailable = false;
assert.equal(scope.f4sRpmStatus(), 'Engine RPM unavailable');
scope.f4s.settings.rpmWobble = 0;
assert.equal(scope.f4sRpmStatus(), 'RPM wobble off');
scope.f4s.settings.rpmWobble = 0.06;
scope.f4s.telemetry.rpmAvailable = true;
assert.equal(scope.f4sStatusSummary(), 'Auto-saved');
scope.f4s.status.message = 'Inactive in VR';
assert.equal(scope.f4sStatusSummary(), 'Inactive in VR');
scope.f4s.status.saveError = 'See beamng.log';
assert.equal(scope.f4sStatusSummary(), 'Settings could not be saved');
scope.f4s.status.saveError = '';
scope.f4s.status.postfx = 'enabled (GPU compilation not verified)';
assert.equal(scope.f4sPostfxStatus(), 'Speed post effects active');
assert.equal(scope.f4s.status.postfx, 'enabled (GPU compilation not verified)', 'preserve raw diagnostic detail for the tooltip');
scope.f4s.status.postfx = 'unavailable: Renderer init failure';
assert.equal(scope.f4sPostfxStatus(), 'Speed post effects unavailable');
scope.f4s.settings.postfxEnabled = false;
assert.equal(scope.f4sPostfxStatus(), 'Speed post effects off');
scope.f4s.settings.postfxEnabled = true;
scope.f4s.telemetry.strength = 2;
assert.equal(scope.f4sStrength(), 100);
scope.f4s.telemetry.strength = -1;
assert.equal(scope.f4sStrength(), 0);

scope.f4s.settings.extraFov = 25; scope.f4sChange('extraFov');
scope.f4s.settings.extraFov = 26; scope.f4sChange('extraFov');
assert.equal(sent.length, 1, 'sliders debounce bridge calls');
listeners.Feel4SpeedState(null, state);
assert.equal(scope.f4s.settings.extraFov, 26, 'stale telemetry must not clobber slider');
tick(80);
assert.equal(sent.length, 2);
assert.ok(sent[1].includes("setSetting('extraFov',26)"));
state.settings.extraFov = 26;
listeners.Feel4SpeedState(null, state);
assert.equal(scope.f4s.settings.extraFov, 26, 'matching echo accepted');

scope.f4s.settings.extraFov = '35'; scope.f4sChange('extraFov');
assert.strictEqual(scope.f4s.settings.extraFov, 35, 'AngularJS 1.5.8 range strings become finite numeric UI values');
tick(80);
assert.ok(sent[sent.length - 1].includes("setSetting('extraFov',35)"));
state.settings.extraFov = 35;

listeners.Feel4SpeedState(null, {
  telemetry: {acceleration: '1.2', kickFov: Infinity, distanceOffset: NaN, rpm: '4200', rpmAvailable: 'true',
    drifting: 'true', driftAvailable: 'true', slipAngle: Infinity, activeBlend: '0.2',
    lateralG: '0.65', corneringRoll: Infinity, corneringBlend: '0.2', corneringAvailable: 'true'},
  status: {rpm: 123, drift: 123, cornering: 123}
});
assert.equal(scope.f4s.telemetry.acceleration, undefined, 'engine acceleration must be finite numeric');
assert.equal(scope.f4s.telemetry.kickFov, undefined);
assert.equal(scope.f4s.telemetry.distanceOffset, undefined);
assert.equal(scope.f4s.telemetry.rpm, undefined);
assert.equal(scope.f4s.telemetry.rpmAvailable, false, 'engine sensor presence must be a boolean');
assert.equal(scope.f4s.status.rpm, '', 'engine status messages must be strings');
assert.equal(scope.f4s.telemetry.drifting, false);
assert.equal(scope.f4s.telemetry.driftAvailable, false);
assert.equal(scope.f4s.telemetry.slipAngle, undefined);
assert.equal(scope.f4s.telemetry.activeBlend, undefined);
assert.equal(scope.f4s.status.drift, '');
assert.equal(scope.f4s.telemetry.lateralG, undefined);
assert.equal(scope.f4s.telemetry.corneringRoll, undefined);
assert.equal(scope.f4s.telemetry.corneringBlend, undefined);
assert.equal(scope.f4s.telemetry.corneringAvailable, false);
assert.equal(scope.f4s.status.cornering, '');
listeners.Feel4SpeedState(null, {telemetry: {activeBlend: 2}});
assert.equal(scope.f4s.telemetry.activeBlend, 1, 'blend is clamped to a valid fraction');
listeners.Feel4SpeedState(null, {telemetry: {activeBlend: -2}});
assert.equal(scope.f4s.telemetry.activeBlend, 0);
listeners.Feel4SpeedState(null, {telemetry: {corneringBlend: 2}});
assert.equal(scope.f4s.telemetry.corneringBlend, 1);
listeners.Feel4SpeedState(null, {telemetry: {corneringBlend: -2}});
assert.equal(scope.f4s.telemetry.corneringBlend, 0);
listeners.Feel4SpeedState(null, state);

scope.f4s.settings.blur = '0.074'; scope.f4sChange('blur'); tick(80);
assert.strictEqual(scope.f4s.settings.blur, 0.074, 'edge blur precision is preserved');
assert.ok(sent[sent.length - 1].includes("setSetting('blur',0.074)"));
scope.f4s.settings.curve = '1.45'; scope.f4sChange('curve'); tick(80);
assert.strictEqual(scope.f4s.settings.curve, 1.45);
assert.ok(sent[sent.length - 1].includes("setSetting('curve',1.45)"));
listeners.Feel4SpeedState(null, state);
state.settings.extraFov = '36';
listeners.Feel4SpeedState(null, state);
assert.strictEqual(scope.f4s.settings.extraFov, 35, 'engine events still require numeric settings');
state.settings.extraFov = 35;

var before = sent.length;
scope.f4s.settings.extraFov = Infinity; scope.f4sChange('extraFov');
['', '  ', 'NaN', 'Infinity', '35); print("injected")', '0x35'].forEach(function (value) {
  scope.f4s.settings.extraFov = value; scope.f4sChange('extraFov');
});
scope.f4s.settings.postfxEnabled = 'true'; scope.f4sChange('postfxEnabled');
scope.f4sChange("evil'); print('injected");
scope.f4sPreset("balanced'); print('injected");
tick(80);
assert.equal(sent.length, before, 'invalid inputs must not reach Lua');

scope.f4s.settings.extraFov = 999; scope.f4sChange('extraFov'); tick(80);
assert.ok(sent[sent.length - 1].includes("setSetting('extraFov',60)"));
scope.f4s.settings.fullSpeed = 100;
scope.f4s.settings.startSpeed = 120;
scope.f4sChange('startSpeed');
assert.equal(scope.f4s.settings.fullSpeed, 125);
assert.ok(sent[sent.length - 1].includes("setSetting('fullSpeed',125)"));
tick(80);
scope.f4s.settings.fullSpeed = 121; scope.f4sChange('fullSpeed'); tick(80);
assert.equal(scope.f4s.settings.fullSpeed, 125, 'speed interval has a minimum 5 km/h gap');

[
  ['accelerationFov', '6.5', 6.5], ['brakingFov', '8.5', 8.5],
  ['accelerationDistance', '0.31', 0.31], ['brakingDistance', '0.36', 0.36],
  ['accelReference', '6.5', 6.5], ['accelDeadzone', '0.6', 0.6],
  ['springTime', '0.26', 0.26], ['springDamping', '0.9', 0.9],
  ['rpmWobble', '0.07', 0.07], ['rpmStart', '1100', 1100], ['rpmFull', '6600', 6600],
  ['corneringStrength', '1.6', 1.6], ['corneringLimit', '6.5', 6.5],
  ['corneringDeadzone', '0.09', 0.09], ['corneringResponse', '0.19', 0.19]
].forEach(function (entry) {
  scope.f4s.settings[entry[0]] = entry[1]; scope.f4sChange(entry[0]); tick(80);
  assert.strictEqual(scope.f4s.settings[entry[0]], entry[2], 'strict numeric string conversion for ' + entry[0]);
  assert.ok(sent[sent.length - 1].includes("setSetting('" + entry[0] + "'," + entry[2] + ")"));
});
scope.f4s.settings.activeEnabled = false; scope.f4sChange('activeEnabled');
assert.ok(sent[sent.length - 1].includes("setSetting('activeEnabled',false)"));
scope.f4s.settings.activeWhileDrifting = true; scope.f4sChange('activeWhileDrifting');
assert.ok(sent[sent.length - 1].includes("setSetting('activeWhileDrifting',true)"));
scope.f4s.settings.activeWhileDrifting = false; scope.f4sChange('activeWhileDrifting');
assert.ok(sent[sent.length - 1].includes("setSetting('activeWhileDrifting',false)"));
scope.f4s.settings.corneringWhileDrifting = true; scope.f4sChange('corneringWhileDrifting');
assert.ok(sent[sent.length - 1].includes("setSetting('corneringWhileDrifting',true)"));
scope.f4s.settings.corneringInvert = false; scope.f4sChange('corneringInvert');
assert.ok(sent[sent.length - 1].includes("setSetting('corneringInvert',false)"), 'inversion sends an immediate strict boolean');
listeners.Feel4SpeedState(null, { settings: {corneringInvert: true} });
assert.strictEqual(scope.f4s.settings.corneringInvert, false, 'a stale inversion echo does not undo a local edit');
listeners.Feel4SpeedState(null, { settings: {corneringInvert: false} });
assert.strictEqual(scope.f4s.settings.corneringInvert, false, 'the matching inversion echo is accepted');
listeners.Feel4SpeedState(null, { settings: {corneringInvert: 'true'} });
assert.strictEqual(scope.f4s.settings.corneringInvert, false, 'inversion state requires a boolean, not a string');
scope.f4s.settings.corneringInvert = true; scope.f4sChange('corneringInvert');
assert.ok(sent[sent.length - 1].includes("setSetting('corneringInvert',true)"));
listeners.Feel4SpeedState(null, { settings: {corneringInvert: true} });
assert.strictEqual(scope.f4s.settings.corneringInvert, true);
assert.ok(scope.f4sCorneringHint().indexOf('Inward (Standard)') === 0, 'matching Standard state restores the inward hint');
scope.f4s.settings.corneringEnabled = false; scope.f4sChange('corneringEnabled');
assert.ok(sent[sent.length - 1].includes("setSetting('corneringEnabled',false)"));
scope.f4s.settings.corneringStrength = 999; scope.f4sChange('corneringStrength'); tick(80);
assert.equal(scope.f4s.settings.corneringStrength, 6);
scope.f4s.settings.corneringLimit = 999; scope.f4sChange('corneringLimit'); tick(80);
assert.equal(scope.f4s.settings.corneringLimit, 15);
scope.f4s.settings.corneringDeadzone = -1; scope.f4sChange('corneringDeadzone'); tick(80);
assert.equal(scope.f4s.settings.corneringDeadzone, 0);
scope.f4s.settings.corneringResponse = 0; scope.f4sChange('corneringResponse'); tick(80);
assert.equal(scope.f4s.settings.corneringResponse, 0.05);
scope.f4s.settings.rpmWobble = 0.08; scope.f4sChange('rpmWobble'); tick(80);
assert.ok(sent[sent.length - 1].includes("setSetting('rpmWobble',0.08)"), 'RPM control works with acceleration feedback disabled');
scope.f4s.settings.rpmFull = 1500;
scope.f4s.settings.rpmStart = 2000; scope.f4sChange('rpmStart');
assert.equal(scope.f4s.settings.rpmFull, 2100);
assert.ok(sent[sent.length - 1].includes("setSetting('rpmFull',2100)"));
tick(80);
scope.f4s.settings.rpmFull = 2000; scope.f4sChange('rpmFull'); tick(80);
assert.equal(scope.f4s.settings.rpmFull, 2100, 'RPM interval has a minimum 100 RPM gap');
scope.f4s.settings.rpmStart = 99999; scope.f4sChange('rpmStart'); tick(80);
assert.equal(scope.f4s.settings.rpmStart, 10000);
assert.equal(scope.f4s.settings.rpmFull, 10100);
scope.f4s.settings.accelReference = 6;
scope.f4s.settings.accelDeadzone = 3;
scope.f4s.settings.accelReference = '1'; scope.f4sChange('accelReference');
assert.strictEqual(scope.f4s.settings.accelReference, 1);
assert.strictEqual(scope.f4s.settings.accelDeadzone, 0.9, 'lowering the full-kick reference immediately clamps the deadzone');
assert.ok(sent[sent.length - 1].includes("setSetting('accelDeadzone',0.9)"));
tick(80);
assert.ok(sent[sent.length - 1].includes("setSetting('accelReference',1)"));
scope.f4s.settings.accelDeadzone = '3'; scope.f4sChange('accelDeadzone');
assert.strictEqual(scope.f4s.settings.accelDeadzone, 0.9, 'editing the deadzone clamps the displayed and queued value before sending');
listeners.Feel4SpeedState(null, { settings: {accelReference: 1, accelDeadzone: 0.9} });
assert.strictEqual(scope.f4s.settings.accelDeadzone, 0.9, 'matching normalized engine state is accepted immediately');
tick(80);
assert.ok(sent[sent.length - 1].includes("setSetting('accelDeadzone',0.9)"), 'the bridge receives a finite deadzone literal');
scope.f4s.settings.accelerationFov = 999; scope.f4sChange('accelerationFov'); tick(80);
assert.equal(scope.f4s.settings.accelerationFov, 20);
scope.f4s.settings.springTime = 0; scope.f4sChange('springTime'); tick(80);
assert.equal(scope.f4s.settings.springTime, 0.08);
scope.f4s.settings.springDamping = Infinity; scope.f4sChange('springDamping');
before = sent.length;
scope.f4s.settings.rpmWobble = '0.07); injected()'; scope.f4sChange('rpmWobble');
scope.f4s.settings.activeEnabled = 'true'; scope.f4sChange('activeEnabled');
scope.f4s.settings.activeWhileDrifting = 'true'; scope.f4sChange('activeWhileDrifting');
scope.f4s.settings.corneringEnabled = 'true'; scope.f4sChange('corneringEnabled');
scope.f4s.settings.corneringWhileDrifting = 'true'; scope.f4sChange('corneringWhileDrifting');
['true', 'false', 1, 0, null, 'false); injected()'].forEach(function (value) {
  scope.f4s.settings.corneringInvert = value; scope.f4sChange('corneringInvert');
});
scope.f4s.settings.corneringStrength = '1); injected()'; scope.f4sChange('corneringStrength');
tick(80);
assert.equal(sent.length, before, 'active inputs preserve literal safety');

scope.f4sPreset('clean');
assert.ok(sent[sent.length - 1].includes("applyPreset('clean')"));
scope.f4sPreset('standard');
assert.ok(sent[sent.length - 1].includes("applyPreset('standard')"));
scope.f4s.settings.enabled = false; scope.f4sEnabled();
assert.ok(sent[sent.length - 1].includes('setEnabled(false)'));
scope.f4s.settings.postfxEnabled = false; scope.f4sChange('postfxEnabled');
assert.ok(sent[sent.length - 1].includes("setSetting('postfxEnabled',false)"));
scope.f4sReset();
assert.ok(sent[sent.length - 1].includes('resetDefaults()'));

scope.f4s.settings.wobble = 0.22; scope.f4sChange('wobble');
listeners.$destroy();
assert.ok(sent[sent.length - 1].includes("setSetting('wobble',0.22)"));
assert.equal(timers.size, 0, 'destroy must remove all timers');
assert.ok(!listeners.Feel4SpeedState, 'destroy must remove event listener');
console.log('Feel4Speed UI mocked integration passed: all 32 Standard defaults, stable 1.0.0 versioned assets and namespace, inward/outward roll hints and strict inversion booleans/echoes, readable controls, constrained flex scrolling, compact titlebar, Camera/Active/Cornering/Effects tabs, bootstrap, finite active/drift/cornering telemetry, bounded blends, drift overrides and return statuses, cornering/RPM independence, status summaries, debounce, stale echo protection, AngularJS 1.5.8 decimal range strings, setting limits, literal safety, speed/RPM/deadzone intervals, presets, toggles, reset and destroy.');
