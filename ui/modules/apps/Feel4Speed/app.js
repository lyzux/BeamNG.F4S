(function () {
  'use strict';

  angular.module('beamng.apps').directive('feel4Speed', ['$timeout', function ($timeout) {
    var limits = {
      extraFov: [0, 60], startSpeed: [0, 150], fullSpeed: [40, 400],
      curve: [0.5, 3], response: [0.05, 2], vignette: [0, 0.8],
      blur: [0, 0.1], wobble: [0, 1], fovLimit: [80, 140],
      accelerationFov: [0, 20], brakingFov: [0, 20],
      accelerationDistance: [0, 1], brakingDistance: [0, 1],
      accelReference: [1, 20], accelDeadzone: [0, 3],
      springTime: [0.08, 1.5], springDamping: [0.3, 2],
      rpmWobble: [0, 1], rpmStart: [0, 10000], rpmFull: [1000, 20000],
      corneringStrength: [0, 6], corneringLimit: [0, 15],
      corneringDeadzone: [0, 1], corneringResponse: [0.05, 1]
    };
    var booleans = {
      enabled: true, postfxEnabled: true, orbitOnly: true,
      activeEnabled: true, activeWhileDrifting: true,
      corneringEnabled: true, corneringWhileDrifting: true, corneringInvert: true
    };
    var defaults = {
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
    };

    function number(value) {
      return typeof value === 'number' && isFinite(value);
    }

    function sanitize(key, value) {
      if (Object.prototype.hasOwnProperty.call(booleans, key)) {
        return typeof value === 'boolean' ? value : undefined;
      }
      if (!Object.prototype.hasOwnProperty.call(limits, key) || !number(value)) return undefined;
      return Math.max(limits[key][0], Math.min(limits[key][1], value));
    }

    return {
      restrict: 'EA',
      replace: true,
      scope: true,
      templateUrl: '/ui/modules/apps/Feel4Speed/app-v100.html',
      link: function (scope) {
        var timers = {};
        var dirty = {};
        var alive = true;
        var stateReceived = false;
        var initTimer;

        scope.f4s = {
          settings: angular.copy(defaults), telemetry: {},
          status: { message: 'Connecting to the camera extension...', postfx: '' },
          compact: true, tab: 'camera', ready: false, version: '1.0.0'
        };

        scope.f4sToggleCompact = function () {
          scope.f4s.compact = !scope.f4s.compact;
        };

        scope.f4sTab = function (tab) {
          if (tab === 'camera' || tab === 'active' || tab === 'cornering' || tab === 'effects') scope.f4s.tab = tab;
        };

        function engineLua(command) {
          if (alive && typeof bngApi !== 'undefined' && typeof bngApi.engineLua === 'function') {
            bngApi.engineLua(command);
            return true;
          }
          scope.f4s.status.message = 'The BeamNG UI bridge is unavailable.';
          return false;
        }

        // Only fixed method names, whitelisted keys and finite numeric/boolean
        // literals cross the JavaScript-to-Lua bridge. Never interpolate UI text.
        function sendSetting(key, value) {
          var valid = sanitize(key, value);
          if (valid === undefined) return;
          var literal = typeof valid === 'boolean' ? (valid ? 'true' : 'false') : String(valid);
          engineLua("if feel4speed_main then feel4speed_main.setSetting('" + key + "'," + literal + ") end");
        }

        function cancelChanges() {
          Object.keys(timers).forEach(function (key) { $timeout.cancel(timers[key]); });
          timers = {};
          dirty = {};
        }

        function queue(key, value, immediate) {
          if (timers[key]) $timeout.cancel(timers[key]);
          dirty[key] = { value: value, until: Date.now() + 1500 };
          if (immediate) {
            delete timers[key];
            sendSetting(key, value);
          } else {
            timers[key] = $timeout(function () {
              delete timers[key];
              sendSetting(key, value);
            }, 80, false);
          }
        }

        scope.f4sChange = function (key) {
          var input = scope.f4s.settings[key];
          // BeamNG's AngularJS 1.5.8 treats range inputs as text, so actual
          // slider edits can arrive as strings. Coerce only decimal strings
          // from a known numeric UI control; engine state stays strictly typed.
          if (Object.prototype.hasOwnProperty.call(limits, key) && typeof input === 'string') {
            input = input.trim();
            if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(input)) return;
            input = Number(input);
          }
          var value = sanitize(key, input);
          if (value === undefined) return;
          scope.f4s.settings[key] = value;
          // Keep the speed interval nonempty while moving either threshold.
          if (key === 'startSpeed' && value + 5 > scope.f4s.settings.fullSpeed) {
            scope.f4s.settings.fullSpeed = Math.min(400, value + 5);
            queue('fullSpeed', scope.f4s.settings.fullSpeed, true);
          } else if (key === 'fullSpeed' && value < scope.f4s.settings.startSpeed + 5) {
            scope.f4s.settings.fullSpeed = value = Math.min(400, scope.f4s.settings.startSpeed + 5);
          }
          // Engine-speed feedback needs a nonempty RPM interval too.
          if (key === 'rpmStart' && value + 100 > scope.f4s.settings.rpmFull) {
            scope.f4s.settings.rpmFull = Math.min(20000, value + 100);
            queue('rpmFull', scope.f4s.settings.rpmFull, true);
          } else if (key === 'rpmFull' && value < scope.f4s.settings.rpmStart + 100) {
            scope.f4s.settings.rpmFull = value = Math.min(20000, scope.f4s.settings.rpmStart + 100);
          }
          // Keep the deadzone below the full-kick reference, matching Lua's
          // normalization before the optimistic UI value is queued.
          if (key === 'accelReference' && scope.f4s.settings.accelDeadzone > value - 0.1) {
            scope.f4s.settings.accelDeadzone = Math.max(0, value - 0.1);
            queue('accelDeadzone', scope.f4s.settings.accelDeadzone, true);
          } else if (key === 'accelDeadzone') {
            scope.f4s.settings.accelDeadzone = value = Math.min(value, Math.max(0, scope.f4s.settings.accelReference - 0.1));
          }
          queue(key, value, Object.prototype.hasOwnProperty.call(booleans, key));
        };

        scope.f4sEnabled = function () {
          var enabled = scope.f4s.settings.enabled === true;
          dirty.enabled = { value: enabled, until: Date.now() + 1500 };
          engineLua('if feel4speed_main then feel4speed_main.setEnabled(' + (enabled ? 'true' : 'false') + ') end');
        };

        scope.f4sPreset = function (preset) {
          if (preset !== 'standard' && preset !== 'balanced' && preset !== 'intense' && preset !== 'clean') return;
          cancelChanges();
          engineLua("if feel4speed_main then feel4speed_main.applyPreset('" + preset + "') end");
        };

        scope.f4sReset = function () {
          cancelChanges();
          engineLua('if feel4speed_main then feel4speed_main.resetDefaults() end');
        };

        scope.f4sConnect = function () {
          engineLua("extensions.load('feel4speed_main'); if feel4speed_main then feel4speed_main.requestState() end");
        };

        scope.f4sNumber = function (value, decimals) {
          return number(value) ? value.toFixed(decimals || 0) : '--';
        };

        scope.f4sSigned = function (value, decimals) {
          return number(value) ? (value > 0 ? '+' : '') + value.toFixed(decimals || 0) : '--';
        };

        scope.f4sRpmStatus = function () {
          if (scope.f4s.settings.rpmWobble <= 0) return 'RPM wobble off';
          return scope.f4s.telemetry.rpmAvailable ? 'Engine RPM ready' : 'Engine RPM unavailable';
        };

        scope.f4sDriftStatus = function () {
          if (!scope.f4s.settings.activeEnabled || !scope.f4s.ready) return '';
          var telemetry = scope.f4s.telemetry;
          if (!telemetry.driftAvailable) {
            // At rest there is no velocity heading to compare with the car.
            // Show an unavailable warning only once motion can define it.
            return number(telemetry.speedKph) && telemetry.speedKph < 1 ? '' : 'Drift detection unavailable';
          }
          if (telemetry.drifting) {
            return scope.f4s.settings.activeWhileDrifting ? 'Drifting: active feedback' : 'Drifting: passive blend';
          }
          if (!scope.f4s.settings.activeWhileDrifting && number(telemetry.activeBlend) && telemetry.activeBlend < 0.99) {
            return 'Returning to active feedback';
          }
          return '';
        };

        scope.f4sCorneringHint = function () {
          return scope.f4s.settings.corneringInvert ?
            'Inward (Standard): force left leans left; right leans right.' :
            'Outward: force left leans right; right leans left.';
        };

        scope.f4sCorneringStatus = function () {
          if (!scope.f4s.settings.corneringEnabled) return 'G-force camera roll off';
          if (!scope.f4s.ready) return '';
          var telemetry = scope.f4s.telemetry;
          if (!telemetry.corneringAvailable) {
            var status = (scope.f4s.status.cornering || '').toLowerCase();
            if (status === 'disabled') return 'G-force camera roll off';
            if (number(telemetry.speedKph) && telemetry.speedKph < 1) return '';
            if (status === 'priming' || status === 'idle' || status.indexOf('waiting') === 0) return 'Waiting for cornering motion';
            return 'Cornering feedback unavailable';
          }
          if (telemetry.drifting) {
            return scope.f4s.settings.corneringWhileDrifting ? 'Drifting: G-force roll' : 'Drifting: roll fades to neutral';
          }
          if (!scope.f4s.settings.corneringWhileDrifting && number(telemetry.corneringBlend) && telemetry.corneringBlend < 0.99) {
            return 'Returning to G-force roll';
          }
          return 'G-force camera roll ready';
        };

        scope.f4sStrength = function () {
          var strength = scope.f4s.telemetry.strength;
          return number(strength) ? Math.round(Math.max(0, Math.min(1, strength)) * 100) : 0;
        };

        scope.f4sPostfxStatus = function () {
          var message = scope.f4s.status.postfx || '';
          if (!scope.f4s.settings.postfxEnabled || message === 'disabled') return 'Speed post effects off';
          if (message.indexOf('unavailable') === 0) return 'Speed post effects unavailable';
          if (message.indexOf('enabled') === 0) return 'Speed post effects active';
          return 'Speed post effects ready';
        };

        scope.f4sStatusSummary = function () {
          var status = scope.f4s.status;
          if (status.saveError) return 'Settings could not be saved';
          if (status.message && status.message !== 'Active') return status.message;
          return 'Auto-saved';
        };

        var unsubscribe = scope.$on('Feel4SpeedState', function (event, state) {
          if (!state || typeof state !== 'object') return;
          scope.$evalAsync(function () {
            if (!alive) return;
            var settings = state.settings || {};
            Object.keys(defaults).forEach(function (key) {
              var value = sanitize(key, settings[key]);
              if (value === undefined) return;
              var pending = dirty[key];
              if (pending && pending.value !== value && pending.until > Date.now()) return;
              delete dirty[key];
              scope.f4s.settings[key] = value;
            });
            var telemetry = state.telemetry || {};
            var safeTelemetry = {};
            ['speedKph', 'extraFov', 'fov', 'strength', 'acceleration', 'kickFov', 'distanceOffset', 'rpm', 'slipAngle', 'lateralG', 'corneringRoll'].forEach(function (key) {
              if (number(telemetry[key])) safeTelemetry[key] = telemetry[key];
            });
            safeTelemetry.camera = typeof telemetry.camera === 'string' ? telemetry.camera : '';
            safeTelemetry.active = telemetry.active === true;
            safeTelemetry.rpmAvailable = telemetry.rpmAvailable === true;
            safeTelemetry.drifting = telemetry.drifting === true;
            safeTelemetry.driftAvailable = telemetry.driftAvailable === true;
            safeTelemetry.corneringAvailable = telemetry.corneringAvailable === true;
            if (number(telemetry.activeBlend)) safeTelemetry.activeBlend = Math.max(0, Math.min(1, telemetry.activeBlend));
            if (number(telemetry.corneringBlend)) safeTelemetry.corneringBlend = Math.max(0, Math.min(1, telemetry.corneringBlend));
            scope.f4s.telemetry = safeTelemetry;
            var status = state.status || {};
            scope.f4s.status = {
              message: typeof status.message === 'string' ? status.message : '',
              postfx: typeof status.postfx === 'string' ? status.postfx : '',
              rpm: typeof status.rpm === 'string' ? status.rpm : '',
              drift: typeof status.drift === 'string' ? status.drift : '',
              cornering: typeof status.cornering === 'string' ? status.cornering : '',
              saveError: typeof status.saveError === 'string' ? status.saveError : ''
            };
            if (typeof state.version === 'string') scope.f4s.version = state.version;
            scope.f4s.ready = stateReceived = true;
          });
        });

        scope.f4sConnect();
        // Offer a visible retry if extension initialization could not complete.
        initTimer = $timeout(function () {
          if (!stateReceived) scope.f4s.status.message = 'No extension response. Reload the mod or select Reconnect.';
        }, 5000);

        scope.$on('$destroy', function () {
          // Flush edits once before removing the app. The global extension and
          // its persisted settings intentionally remain active after closing UI.
          Object.keys(timers).forEach(function (key) {
            $timeout.cancel(timers[key]);
            if (dirty[key]) sendSetting(key, dirty[key].value);
          });
          alive = false;
          timers = {};
          dirty = {};
          $timeout.cancel(initTimer);
          unsubscribe();
        });
      }
    };
  }]);
}());
