-- Contract tests; BeamNG engine integrations are mocked deliberately.
local model = require('feel4speed/model')
local passed, failed = 0, 0
local function equal(actual, expected, message)
  if actual ~= expected then error((message or 'Values differ') .. ': expected ' ..
    tostring(expected) .. ', received ' .. tostring(actual), 2) end
end
local function near(actual, expected, tolerance, message)
  if not model.finite(actual) or math.abs(actual - expected) > (tolerance or 1e-10) then
    error((message or 'Values differ') .. ': expected approximately ' ..
      tostring(expected) .. ', received ' .. tostring(actual), 2)
  end
end
local function truthy(value, message) if not value then error(message or 'Expected truthy value', 2) end end
local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then passed = passed + 1; print('PASS ' .. name)
  else failed = failed + 1; print('FAIL ' .. name .. '\n' .. tostring(err)) end
end

local standardSettings = {
  enabled = true, orbitOnly = true, postfxEnabled = true,
  extraFov = 40, startSpeed = 20, fullSpeed = 280,
  curve = 1.45, response = 0.25, fovLimit = 120,
  wobble = 0.12, vignette = 0.15, blur = 0.074,
  activeEnabled = true, activeWhileDrifting = false,
  accelerationFov = 3.5, brakingFov = 3.5,
  accelerationDistance = 0.80, brakingDistance = 0.59,
  accelReference = 13.5, accelDeadzone = 1.4, springTime = 0.34,
  springDamping = 2, rpmWobble = 0.03, rpmStart = 1000, rpmFull = 6700,
  corneringEnabled = true, corneringStrength = 1.5, corneringLimit = 6,
  corneringDeadzone = 0.08, corneringResponse = 0.18, corneringWhileDrifting = false,
  corneringInvert = true
}
local function assertStandard(actual, enabled)
  local count = 0
  for key, expected in pairs(standardSettings) do
    if key == 'enabled' and enabled ~= nil then expected = enabled end
    equal(actual[key], expected, 'Standard setting ' .. key)
  end
  for _ in pairs(actual) do count = count + 1 end
  equal(count, 32, 'Complete validated setting count')
end

test('new installation defaults match the user-tested Standard profile', function()
  assertStandard(model.defaults())
  assertStandard(model.validate(nil))
  assertStandard(model.validate({}))
end)

test('Standard preset restores every camera and effect setting while preserving master toggle', function()
  for _, enabled in ipairs({true, false}) do
    local custom = {enabled = enabled, orbitOnly = false, postfxEnabled = false,
      extraFov = 1, startSpeed = 100, fullSpeed = 350, curve = 0.5,
      response = 2, fovLimit = 80, wobble = 1, vignette = 0, blur = 0,
      activeEnabled = false, activeWhileDrifting = true, accelerationFov = 1, brakingFov = 1,
      accelerationDistance = 1, brakingDistance = 1, accelReference = 2,
      accelDeadzone = 0, springTime = 1, springDamping = 1.5,
      rpmWobble = 1, rpmStart = 3000, rpmFull = 10000,
      corneringEnabled = false, corneringStrength = 5, corneringLimit = 12,
      corneringDeadzone = 0.5, corneringResponse = 1, corneringWhileDrifting = true,
      corneringInvert = false}
    assertStandard(model.preset(custom, 'standard'), enabled)
    equal(custom.extraFov, 1, 'Applying a preset must not mutate its input')
    equal(custom.corneringEnabled, false)
    equal(custom.corneringWhileDrifting, true)
    equal(custom.corneringInvert, false)
    equal(custom.orbitOnly, false)
    equal(custom.postfxEnabled, false)
  end
end)

test('existing presets keep their original values and preserve camera scope and toggles', function()
  local profiles = {
    balanced = {extraFov = 24, vignette = 0.28, blur = 0.025, wobble = 0.18,
      startSpeed = 25, fullSpeed = 200, curve = 1.15, response = 0.35},
    intense = {extraFov = 42, vignette = 0.45, blur = 0.055, wobble = 0.38,
      startSpeed = 20, fullSpeed = 180, curve = 0.95, response = 0.25},
    clean = {extraFov = 30, vignette = 0, blur = 0, wobble = 0,
      startSpeed = 25, fullSpeed = 200, curve = 1.15, response = 0.35,
      activeEnabled = false, rpmWobble = 0, corneringEnabled = false}
  }
  local custom = model.defaults()
  custom.enabled, custom.orbitOnly, custom.postfxEnabled = false, false, false
  custom.fovLimit = 140
  custom.accelerationFov, custom.brakingFov = 4, 9
  custom.accelerationDistance, custom.brakingDistance = 0.7, 0.8
  custom.rpmWobble = 0.3
  custom.corneringStrength, custom.corneringLimit = 4, 12
  custom.corneringDeadzone, custom.corneringResponse = 0.3, 0.6
  custom.corneringWhileDrifting = true
  custom.corneringInvert = false
  for name, expected in pairs(profiles) do
    local actual = model.preset(custom, name)
    for key, value in pairs(expected) do equal(actual[key], value, name .. ' ' .. key) end
    equal(actual.enabled, false)
    equal(actual.orbitOnly, false)
    equal(actual.postfxEnabled, false)
    equal(actual.fovLimit, 140)
    for _, key in ipairs({'accelerationFov', 'brakingFov', 'accelerationDistance',
      'brakingDistance', 'accelReference', 'accelDeadzone', 'springTime',
      'springDamping', 'rpmStart', 'rpmFull', 'activeWhileDrifting'}) do
      equal(actual[key], custom[key], name .. ' preserves ' .. key)
    end
    for _, key in ipairs({'corneringStrength', 'corneringLimit', 'corneringDeadzone',
      'corneringResponse', 'corneringWhileDrifting', 'corneringInvert'}) do
      equal(actual[key], custom[key], name .. ' preserves ' .. key)
    end
    if name ~= 'clean' then
      equal(actual.activeEnabled, custom.activeEnabled)
      equal(actual.rpmWobble, custom.rpmWobble)
      equal(actual.corneringEnabled, custom.corneringEnabled)
    end
  end
end)

test('cornering setting types and bounds are validated independently of the active layer', function()
  local cfg = model.validate({corneringEnabled = 'true', corneringWhileDrifting = 1,
    corneringInvert = 'false',
    corneringStrength = 99, corneringLimit = -1, corneringDeadzone = 99, corneringResponse = -1})
  equal(cfg.corneringEnabled, true)
  equal(cfg.corneringWhileDrifting, false)
  equal(cfg.corneringInvert, true)
  equal(cfg.corneringStrength, 6)
  equal(cfg.corneringLimit, 0)
  equal(cfg.corneringDeadzone, 1)
  equal(cfg.corneringResponse, 0.05)
  cfg = model.validate({corneringStrength = -1, corneringLimit = 99,
    corneringDeadzone = -1, corneringResponse = 99})
  equal(cfg.corneringStrength, 0); equal(cfg.corneringLimit, 15)
  equal(cfg.corneringDeadzone, 0); equal(cfg.corneringResponse, 1)
  assertStandard(model.validate({corneringStrength = 0/0, corneringLimit = math.huge,
    corneringDeadzone = -math.huge, corneringResponse = '0.18'}))
  equal(model.withSetting(model.defaults(), 'corneringEnabled', 1), nil)
  equal(model.withSetting(model.defaults(), 'corneringWhileDrifting', 'true'), nil)
  equal(model.withSetting(model.defaults(), 'corneringInvert', 0), nil)
  equal(model.withSetting(model.defaults(), 'corneringInvert', 'false'), nil)
  equal(model.withSetting(model.defaults(), 'corneringInvert', false).corneringInvert, false)
  equal(model.withSetting(model.defaults(), 'corneringStrength', 0/0), nil)
end)

test('active tuning validates types limits and coupled acceleration and RPM thresholds', function()
  local cfg = model.validate({activeEnabled = 'true', accelerationFov = 99,
    brakingFov = -1, accelerationDistance = 99, brakingDistance = -1,
    accelReference = 1, accelDeadzone = 5, springTime = -1,
    springDamping = 99, rpmWobble = 99, rpmStart = 9000, rpmFull = 1000})
  equal(cfg.activeEnabled, true)
  equal(cfg.accelerationFov, 20); equal(cfg.brakingFov, 0)
  equal(cfg.accelerationDistance, 1); equal(cfg.brakingDistance, 0)
  equal(cfg.accelReference, 1); near(cfg.accelDeadzone, 0.9)
  equal(cfg.springTime, 0.08); equal(cfg.springDamping, 2)
  equal(cfg.rpmWobble, 1)
  truthy(cfg.rpmFull >= cfg.rpmStart + 100)
  cfg = model.validate({activeWhileDrifting = 'true', accelerationFov = 0/0, brakingFov = math.huge,
    accelerationDistance = -math.huge, accelReference = '6',
    rpmWobble = 0/0, rpmStart = math.huge, rpmFull = -math.huge})
  assertStandard(cfg)
  equal(model.withSetting(model.defaults(), 'activeEnabled', 1), nil)
  equal(model.withSetting(model.defaults(), 'activeWhileDrifting', 1), nil)
  equal(model.withSetting(model.defaults(), 'rpmWobble', '0.1'), nil)
  equal(model.withSetting(model.defaults(), 'accelerationFov', 0/0), nil)
end)

test('envelope endpoints, monotonicity and boundedness across presets', function()
  for _, name in ipairs({'standard', 'balanced', 'intense', 'clean'}) do
    local cfg = model.preset(model.defaults(), name)
    equal(model.envelope(-100, cfg), 0)
    equal(model.envelope(cfg.startSpeed, cfg), 0)
    equal(model.envelope(cfg.fullSpeed, cfg), 1)
    equal(model.envelope(10000, cfg), 1)
    local last = 0
    for speed = 0, 500, 0.25 do
      local amount = model.envelope(speed, cfg)
      truthy(amount >= last and amount <= 1, 'Envelope must be monotonic and bounded')
      last = amount
    end
  end
end)

test('validation sanitizes NaN/infinity/types and enforces speed gap', function()
  local defaults = model.defaults()
  local cfg = model.validate({extraFov = 0/0, startSpeed = 99999, fullSpeed = -999,
    wobble = math.huge, curve = -math.huge, enabled = 'yes', response = 0,
    blur = 999, ignoredKey = 10})
  equal(cfg.extraFov, defaults.extraFov)
  equal(cfg.wobble, defaults.wobble)
  equal(cfg.curve, defaults.curve)
  equal(cfg.enabled, defaults.enabled)
  equal(cfg.startSpeed, 150)
  equal(cfg.fullSpeed, 155)
  equal(cfg.response, 0.05)
  equal(cfg.blur, 0.1)
  equal(cfg.ignoredKey, nil)
  equal(model.envelope(0/0, cfg), 0)
  equal(model.envelope(math.huge, cfg), 0)
  equal(model.withSetting(cfg, 'bogus', 1), nil)
  equal(model.withSetting(cfg, 'enabled', 1), nil)
  equal(model.withSetting(cfg, 'extraFov', 0/0), nil)
  equal(model.withSetting(cfg, 'extraFov', 100).extraFov, 60)
  equal(model.validate(false).extraFov, defaults.extraFov)
  local copy = model.defaults(); copy.extraFov = 123
  equal(model.defaults().extraFov, defaults.extraFov)
end)

test('FOV is additive, bounded and never narrows native FOV', function()
  local cfg = model.defaults()
  near(model.fov(56, 0.5, cfg), 76)
  local fov, extra = model.fov(115, 1, cfg)
  equal(fov, 120); equal(extra, 5)
  fov, extra = model.fov(135, 1, cfg)
  equal(fov, 135); equal(extra, 0)
  equal(model.fov(56, -99, cfg), 56)
  equal(model.fov(56, 99, cfg), 96)
  equal(model.fov(0/0, 1, cfg), nil)
end)

test('exponential response is frame-rate invariant at normal frame times', function()
  local outcomes = {}
  for _, fps in ipairs({20, 30, 60, 120, 240}) do
    local strength = 0
    for _ = 1, fps * 2 do strength = model.smooth(strength, 1, 1/fps, 0.35) end
    outcomes[#outcomes + 1] = strength
    near(strength, 1 - math.exp(-2/0.35), 1e-12)
  end
  for _, value in ipairs(outcomes) do near(value, outcomes[1], 1e-12) end
  equal(model.smooth(0.4, 1, 0, 0.35), 0.4)
  equal(model.smooth(0.4, 1, -1, 0.35), 0.4)
  equal(model.smooth(0.4, 1, 0/0, 0.35), 0.4)
  near(model.smooth(0, 1, 10, 0.35), model.smooth(0, 1, 0.25, 0.35))
end)

test('wobble angles are continuous and limited to configured degrees', function()
  local cfg = model.defaults(); cfg.wobble = 1
  local maxAngle = math.pi / 180
  for phase = 0, 100, 0.01 do
    local pitch, yaw, roll = model.wobble(phase, 1, cfg)
    truthy(math.abs(pitch) <= maxAngle + 1e-12)
    truthy(math.abs(yaw) <= maxAngle + 1e-12)
    truthy(math.abs(roll) <= maxAngle * 0.65 + 1e-12)
    local p2, y2, r2 = model.wobble(phase + 1e-6, 1, cfg)
    truthy(math.abs(p2-pitch) < 1e-6 and math.abs(y2-yaw) < 1e-6 and math.abs(r2-roll) < 1e-6)
  end
  local pitch, yaw, roll = model.wobble(2, 0, cfg)
  equal(pitch, 0); equal(yaw, 0); equal(roll, 0)
end)

test('RPM envelope is bounded and engine vibration remains continuous within configured degrees', function()
  local cfg = model.defaults()
  equal(model.rpmEnvelope(-1, cfg), 0)
  equal(model.rpmEnvelope(cfg.rpmStart, cfg), 0)
  equal(model.rpmEnvelope(cfg.rpmFull, cfg), 1)
  equal(model.rpmEnvelope(30000, cfg), 1)
  equal(model.rpmEnvelope(0/0, cfg), 0)
  equal(model.rpmEnvelope(math.huge, cfg), 0)
  near(model.rpmEnvelope((cfg.rpmStart + cfg.rpmFull) / 2, cfg), 0.5)
  local limit = cfg.rpmWobble * math.pi / 180
  for phase = 0, 2 * math.pi, 0.01 do
    local pitch, yaw, roll = model.rpmWobble(phase, 1, cfg)
    truthy(math.abs(pitch) <= limit and math.abs(yaw) <= limit and math.abs(roll) <= limit)
    local p2, y2, r2 = model.rpmWobble(phase + 1e-6, 1, cfg)
    truthy(math.abs(p2 - pitch) < 1e-7 and math.abs(y2 - yaw) < 1e-7 and math.abs(r2 - roll) < 1e-7)
  end
  local p0, y0, r0 = model.rpmWobble(0, 1, cfg)
  local p1, y1, r1 = model.rpmWobble(2 * math.pi, 1, cfg)
  near(p1, p0); near(y1, y0); near(r1, r0)
end)

local activeCamera, state, effects, writes, logs, shuts, unloadModes, queuedCommands
local main
local function resetController(stored, activeLayer)
  activeCamera, state, effects, writes, logs, shuts, unloadModes = 'orbit', nil, {}, {}, {}, 0, {}
  queuedCommands = {}
  if not activeLayer then
    -- Existing controller contracts exercise the original passive layer exactly.
    stored = model.validate(stored)
    stored.activeEnabled, stored.rpmWobble = false, 0
  end
  _G.editor = nil
  _G.guihooks = {trigger = function(event, payload)
    equal(event, 'Feel4SpeedState'); state = payload
  end}
  _G.core_camera = {getActiveCamName = function(player) equal(player, 0); return activeCamera end}
  _G.jsonReadFile = function(path) equal(path, '/settings/feel4speed.json'); return stored end
  _G.jsonWriteFile = function(path, cfg, pretty)
    equal(path, '/settings/feel4speed.json'); equal(pretty, true)
    writes[#writes+1] = model.copy(cfg); return true
  end
  _G.setExtensionUnloadMode = function(name, mode) unloadModes[name] = mode end
  _G.log = function(level, tag, message) logs[#logs+1] = {level, tag, message} end
  _G.quatFromEuler = function(pitch, yaw, roll)
    return setmetatable({pitch = pitch, yaw = yaw, roll = roll}, {
      __mul = function(offset, base) return {offset = offset, base = base} end
    })
  end
  package.loaded['ge/extensions/feel4speed/postfx'] = {
    set = function(v, b) effects[#effects+1] = {v = v, b = b}; return true, 'ready' end,
    shutdown = function() shuts = shuts + 1 end
  }
  package.loaded['ge/extensions/feel4speed/main'] = nil
  package.loaded['ge/extensions/feel4speed/rpm'] = nil
  main = require('ge/extensions/feel4speed/main')
  main.onExtensionLoaded()
  equal(unloadModes.feel4speed_main, 'manual')
  return main
end
local function snapshot() main.requestState(); return state end
local function frame(opts)
  opts = opts or {}
  local id = opts.id or 7
  local veh = opts.veh or {getId = function() return id end}
  if opts.rpmBridge or opts.rpm ~= nil then
    veh.queueLuaCommand = function(_, command)
      queuedCommands[#queuedCommands + 1] = command
      local env = {electrics = {values = {rpm = opts.rpm}},
        obj = {queueGameEngineLua = function(_, reply)
          local ge = {extensions = {feel4speed_main = main}}
          assert(load(reply, 'RPM integration GE reply', 't', ge))()
        end}, string = string, math = math, type = type}
      assert(load(command, 'RPM integration vehicle request', 't', env))()
    end
  end
  local data = {veh = veh, vid = id,
    vel = {length = function() return (opts.kph or 200) / 3.6 end},
    dtSim = opts.dtSim == nil and 1/60 or opts.dtSim,
    dtReal = opts.dtReal == nil and 1/60 or opts.dtReal,
    res = {fov = opts.fov or 56, rot = {native = true}},
    teleported = opts.teleported, openxrSessionRunning = opts.vr,
    gearIndex = opts.gear, wheelSpeed = opts.wheelSpeed}
  if opts.slipAngle ~= nil then
    local speed = (opts.kph or 200) / 3.6
    local heading = (opts.carAngle or 0) * math.pi / 180
    local travel = heading + opts.slipAngle * math.pi / 180
    data.vel.x, data.vel.y, data.vel.z = speed * math.sin(travel), speed * math.cos(travel), 0
    if opts.forwardState ~= 'missing' then
      veh.getDirectionVector = function()
        if opts.forwardState == 'throws' then error('direction unavailable') end
        if opts.forwardState == 'invalid' then return {x = 0/0, y = 1, z = 0} end
        if opts.forwardState == 'vertical' then return {x = 0, y = 0, z = 1} end
        return {x = math.sin(heading), y = math.cos(heading), z = 0}
      end
    end
  end
  return data
end
local function warm()
  for _ = 1, 120 do main.processCamera(frame({kph = 300})) end
  return snapshot()
end
local function finalEffect() return effects[#effects] end

test('controller adds FOV after native camera and publishes effects', function()
  resetController()
  local data = frame(); local originalRot = data.res.rot
  main.processCamera(data)
  local s = snapshot()
  truthy(data.res.fov > 56 and data.res.fov <= 96)
  near(data.res.fov - 56, s.telemetry.extraFov)
  near(s.telemetry.speedKph, 200)
  equal(s.telemetry.active, true)
  equal(data.res.rot.base, originalRot)
  truthy(finalEffect().v > 0 and finalEffect().b > 0)
  local first = data.res.fov
  main.processCamera(frame({fov = 56}))
  truthy(snapshot().telemetry.fov > first)
  local wide = frame({fov = 130}); main.processCamera(wide)
  equal(wide.res.fov, 130); equal(snapshot().telemetry.extraFov, 0)
end)

test('controller freezes speed, strength and rotation phase while paused', function()
  resetController(); warm()
  local before = frame(); main.processCamera(before); local s = snapshot()
  local paused = frame({dtSim = 0, dtReal = 1, kph = 0})
  main.processCamera(paused)
  local after = snapshot()
  near(after.telemetry.strength, s.telemetry.strength)
  near(after.telemetry.speedKph, s.telemetry.speedKph)
  near(paused.res.fov, before.res.fov)
  near(paused.res.rot.offset.pitch, before.res.rot.offset.pitch)
  near(paused.res.rot.offset.yaw, before.res.rot.offset.yaw)
  near(paused.res.rot.offset.roll, before.res.rot.offset.roll)
end)

test('vehicle changes and teleports reset strength before next frame', function()
  resetController(); local s = warm(); truthy(s.telemetry.strength > 0.99)
  main.processCamera(frame({id = 8, kph = 300}))
  near(snapshot().telemetry.strength, 1 - math.exp(-(1/60)/0.25))
  warm(); main.processCamera(frame({teleported = true, kph = 300}))
  near(snapshot().telemetry.strength, 1 - math.exp(-(1/60)/0.25))
  main.onVehicleSwitched()
  equal(snapshot().telemetry.active, false)
  equal(finalEffect().v, 0); equal(finalEffect().b, 0)
end)

test('non-orbit, VR and editor views clean up without modifying native camera', function()
  resetController(); warm()
  for _, camera in ipairs({'driver', 'chase', 'free', 'external', 'path'}) do
    activeCamera = camera
    local data = frame(); local rot = data.res.rot
    main.processCamera(data)
    equal(data.res.fov, 56); equal(data.res.rot, rot)
    equal(snapshot().telemetry.active, false)
    equal(finalEffect().v, 0); equal(finalEffect().b, 0)
  end
  activeCamera = 'orbit'; warm()
  main.processCamera(frame({vr = true}))
  equal(snapshot().status.message, 'Inactive in VR')
  equal(finalEffect().v, 0)
  warm(); _G.editor = {active = true}
  main.processCamera(frame())
  equal(snapshot().status.message, 'Inactive in World Editor')
  equal(finalEffect().b, 0)
  _G.editor = nil
  main.setSetting('orbitOnly', false)
  activeCamera = 'driver'; main.processCamera(frame())
  equal(snapshot().telemetry.active, true)
  activeCamera = 'chase'; main.processCamera(frame())
  equal(snapshot().telemetry.active, true)
  activeCamera = 'free'; main.processCamera(frame())
  equal(snapshot().telemetry.active, false)
end)

test('visual effects toggle preserves additive FOV and master toggle stops effects', function()
  resetController(); warm()
  main.setSetting('postfxEnabled', false)
  local data = frame(); main.processCamera(data)
  truthy(data.res.fov > 56)
  equal(finalEffect().v, 0); equal(finalEffect().b, 0)
  main.setEnabled(false)
  equal(snapshot().telemetry.active, false)
  local untouched = frame(); main.processCamera(untouched)
  equal(untouched.res.fov, 56)
  main.toggle(); main.processCamera(frame())
  equal(snapshot().telemetry.active, true)
end)

test('invalid camera data and numeric telemetry are safely deactivated', function()
  resetController(); warm()
  main.processCamera(nil)
  equal(snapshot().telemetry.active, false)
  main.processCamera({res = {}})
  equal(snapshot().telemetry.active, false)
  local data = frame(); data.res.fov = 0/0
  main.processCamera(data)
  equal(snapshot().status.message, 'Camera FOV unavailable')
  equal(finalEffect().v, 0)
  data = frame(); data.vel.length = function() return math.huge end
  main.processCamera(data)
  equal(snapshot().telemetry.speedKph, 0)
  data = frame({dtSim = 0/0, dtReal = 0/0})
  main.processCamera(data)
  truthy(model.finite(snapshot().telemetry.strength))
  truthy(model.finite(data.res.fov))
end)

test('heartbeat watchdog removes stale post-effects', function()
  resetController(); warm()
  main.onUpdate(0.49)
  equal(snapshot().telemetry.active, true)
  main.onUpdate(0.02)
  equal(snapshot().telemetry.active, false)
  equal(finalEffect().v, 0); equal(finalEffect().b, 0)
  truthy(snapshot().status.message:find('Camera filter inactive', 1, true))
end)

test('state snapshots do not expose mutable settings and detect missing camera filter', function()
  resetController()
  local public = main.getState()
  equal(public.cameraFilterSeen, false)
  public.settings.extraFov = 999
  public.telemetry.active = true
  public.status.message = 'changed externally'
  equal(main.getState().settings.extraFov, 40)
  equal(main.getState().telemetry.active, false)
  truthy(main.getState().status.message ~= 'changed externally')
  main.onUpdate(2.1)
  truthy(main.getState().status.message:find('Camera filter not detected', 1, true))
  main.processCamera(frame())
  equal(main.getState().cameraFilterSeen, true)
  equal(main.getState().status.message, 'Active')
end)

test('settings debounce, validation, serialization and unload persistence', function()
  resetController({extraFov = 31, blur = 99, enabled = true})
  equal(snapshot().settings.extraFov, 31)
  equal(snapshot().settings.blur, 0.1)
  main.setSetting('extraFov', 42)
  main.onUpdate(0.49); equal(#writes, 0)
  main.onUpdate(0.02); equal(#writes, 1); equal(writes[1].extraFov, 42)
  main.setSetting('extraFov', 38)
  local serialized = main.onSerialize()
  equal(#writes, 2); equal(serialized.settings.extraFov, 38)
  equal(shuts, 1, 'Serialization releases renderer handles before a Lua reload')
  serialized.settings.extraFov = 1000
  equal(snapshot().settings.extraFov, 38)
  main.onDeserialized({settings = {extraFov = 1000, enabled = false}})
  equal(snapshot().settings.extraFov, 60)
  equal(snapshot().settings.enabled, false)
  main.resetDefaults(); equal(snapshot().settings.extraFov, 40)
  main.setSetting('extraFov', 29); main.onExtensionUnloaded()
  equal(writes[#writes].extraFov, 29); equal(shuts, 2)
end)

test('controller reset and Standard preset restore the complete user-tested profile', function()
  resetController({enabled = false, orbitOnly = false, postfxEnabled = false,
    extraFov = 1, startSpeed = 100, fullSpeed = 350, curve = 0.5,
    response = 2, fovLimit = 80, wobble = 1, vignette = 0, blur = 0}, true)
  equal(main.applyPreset('standard'), true)
  assertStandard(snapshot().settings, false)
  main.onUpdate(0.51)
  assertStandard(writes[#writes], false)
  main.setSetting('fovLimit', 140)
  main.setSetting('extraFov', 3)
  main.setSetting('orbitOnly', false)
  main.setSetting('postfxEnabled', false)
  main.setSetting('corneringInvert', false)
  main.resetDefaults()
  assertStandard(snapshot().settings)
  main.onUpdate(0.51)
  assertStandard(writes[#writes])
end)

test('upgrade preserves previously saved user settings and supplies defaults only for missing keys', function()
  local previous = {enabled = false, orbitOnly = false, postfxEnabled = false,
    extraFov = 24, startSpeed = 25, fullSpeed = 200, curve = 1.15,
    response = 0.35, fovLimit = 130, wobble = 0.38, vignette = 0.28, blur = 0.025,
    activeEnabled = true, accelerationFov = 6, brakingFov = 8,
    accelerationDistance = 0.30, brakingDistance = 0.35,
    accelReference = 6, accelDeadzone = 0.5, springTime = 0.25,
    springDamping = 0.85, rpmWobble = 0.06, rpmStart = 1000, rpmFull = 6500}
  resetController(previous, true)
  for key, expected in pairs(previous) do
    equal(snapshot().settings[key], expected, 'Previously saved setting ' .. key)
  end
  equal(snapshot().settings.activeWhileDrifting, false,
    'An older profile gains the drift default without replacing its active tune')
  for _, key in ipairs({'corneringEnabled', 'corneringStrength', 'corneringLimit',
    'corneringDeadzone', 'corneringResponse', 'corneringWhileDrifting', 'corneringInvert'}) do
    equal(snapshot().settings[key], standardSettings[key], 'Cornering default for older profile ' .. key)
  end
  main.onUpdate(1)
  equal(#writes, 0, 'Loading an older profile must not overwrite the saved file')
  resetController({extraFov = 31, enabled = false}, true)
  local settings = snapshot().settings
  equal(settings.extraFov, 31)
  equal(settings.enabled, false)
  for key, expected in pairs(standardSettings) do
    if key ~= 'extraFov' and key ~= 'enabled' then
      equal(settings[key], expected, 'Default for missing saved setting ' .. key)
    end
  end
end)

test('mission end clears state and flushes pending edits', function()
  resetController(); warm(); main.setSetting('extraFov', 41)
  main.onClientEndMission()
  local s = snapshot()
  equal(s.telemetry.camera, 'none'); equal(s.telemetry.fov, nil)
  equal(s.telemetry.speedKph, 0); equal(s.telemetry.active, false)
  equal(writes[#writes].extraFov, 41)
  equal(finalEffect().v, 0); equal(finalEffect().b, 0)
end)

test('persistence failure is reported once without per-frame retry spam', function()
  resetController()
  _G.jsonWriteFile = function() return false end
  main.setSetting('extraFov', 27)
  main.onUpdate(0.51); equal(#logs, 1)
  truthy(snapshot().status.message:find('could not be saved', 1, true))
  truthy(snapshot().status.saveError)
  main.processCamera(frame())
  equal(snapshot().status.message, 'Active')
  truthy(snapshot().status.saveError, 'Save error must survive normal camera telemetry')
  for _ = 1, 100 do main.onUpdate(0.1) end
  equal(#logs, 1)
  _G.jsonWriteFile = function() return true end
  main.setSetting('extraFov', 29)
  main.onUpdate(0.51)
  equal(snapshot().status.saveError, nil)
end)

test('suspension stops effects across edits until Lua state recovery', function()
  resetController(); warm(); main.suspend('mock failure')
  equal(snapshot().telemetry.active, false)
  local data = frame(); main.processCamera(data); equal(data.res.fov, 56)
  main.setSetting('extraFov', 26); main.processCamera(frame())
  equal(snapshot().telemetry.active, false)
  equal(snapshot().suspended, true)
  main.onDeserialized({settings = model.defaults()})
  main.processCamera(frame()); equal(snapshot().telemetry.active, true)
  equal(snapshot().suspended, false)
end)

local cameraFactory = dofile(F4S_TEST_ROOT .. '/lua/ge/extensions/core/cameraModes/feel4speed.lua')
test('camera integration is a hidden ordered global filter', function()
  local filter = cameraFactory()
  equal(filter.isGlobal, true); equal(filter.isFilter, true); equal(filter.hidden, true)
  truthy(filter.runningOrder > 0 and filter.runningOrder < 1)
  equal(filter.processorFailed, false)
end)

test('filter lazy-loads once and does not resurrect explicitly unloaded extension', function()
  local calls, loads = 0, 0
  _G.feel4speed_main = nil
  _G.extensions = {load = function(name)
    loads = loads + 1; equal(name, 'feel4speed_main')
    _G.feel4speed_main = {processCamera = function() calls = calls + 1 end}
  end}
  local filter = cameraFactory()
  equal(filter:update({}), nil); filter:update({})
  equal(loads, 1); equal(calls, 2)
  _G.feel4speed_main = nil
  filter:update({}); filter:update({})
  equal(loads, 1); equal(calls, 2)
  local unavailable = cameraFactory()
  _G.extensions.load = function() loads = loads + 1 end
  unavailable:update({}); unavailable:update({})
  equal(loads, 2)
end)

test('filter isolates processor errors and reports only once', function()
  local calls, suspends, logCount = 0, 0, 0
  _G.log = function() logCount = logCount + 1 end
  _G.feel4speed_main = {
    processCamera = function() calls = calls + 1; error('injected processor failure') end,
    suspend = function(reason) suspends = suspends + 1; truthy(reason:find('injected processor failure', 1, true)) end
  }
  local filter = cameraFactory()
  filter:update({}); filter:update({})
  equal(calls, 1); equal(suspends, 1); equal(logCount, 1)
  equal(filter.processorFailed, true); equal(filter.processing, false)
end)

test('filter extension-loader error and reentrancy are contained', function()
  local logsSeen = 0
  _G.feel4speed_main = nil
  _G.log = function() logsSeen = logsSeen + 1 end
  _G.extensions = {load = function() error('injected load failure') end}
  local filter = cameraFactory(); filter:update({}); filter:update({})
  equal(logsSeen, 1); equal(filter.processorFailed, true)
  filter = cameraFactory(); local calls = 0
  _G.feel4speed_main = {processCamera = function(data)
    calls = calls + 1; filter:update(data)
  end}
  filter:update({})
  equal(calls, 1); equal(filter.processing, false)
end)

test('integrated filter suspends safely and requires reconstruction after failure', function()
  resetController()
  _G.feel4speed_main = main
  local goodQuat = _G.quatFromEuler
  _G.quatFromEuler = function() error('injected rotation failure') end
  local filter = cameraFactory()
  local data = frame(); local nativeRot = data.res.rot
  filter:update(data)
  equal(filter.processorFailed, true)
  equal(filter.processing, false)
  equal(data.res.fov, 56)
  equal(data.res.rot, nativeRot)
  equal(snapshot().telemetry.active, false)
  equal(snapshot().suspended, true)
  equal(finalEffect().v, 0); equal(finalEffect().b, 0)
  local logCount = #logs
  _G.quatFromEuler = goodQuat
  main.setSetting('extraFov', 26)
  data = frame(); filter:update(data)
  equal(data.res.fov, 56)
  equal(snapshot().suspended, true)
  equal(#logs, logCount)
  -- Deserialization belongs to Lua reload; the camera filter must also be new.
  main.onDeserialized({settings = model.defaults()})
  data = frame(); filter:update(data)
  equal(data.res.fov, 56)
  filter = cameraFactory()
  data = frame(); filter:update(data)
  truthy(data.res.fov > 56)
  equal(snapshot().telemetry.active, true)
  equal(snapshot().suspended, false)
end)

local registry, created, deleted, enableCalls, disableCalls, realPostfx
local function resetPostfx(options)
  options = options or {}
  registry, created, deleted, enableCalls, disableCalls = {}, {}, {}, 0, 0
  _G.Feel4Speed_PostFXCallbacks = nil
  _G.scenetree = {findObject = function(name) return registry[name] end}
  _G.FS = {fileExists = function(_, path)
    equal(path, '/art/feel4speed/shaders/feel4speedP.hlsl')
    return not options.missingShader
  end}
  _G.createObject = function(className)
    if options.failClass == className then return nil end
    local object = {className = className, fields = {}, constants = {}}
    created[#created+1] = object
    function object:setField(name, index, value) self.fields[name .. ':' .. index] = value end
    function object:getField(name, index) return self.fields[name .. ':' .. index] end
    function object:registerObject(name)
      if options.failRegister == className then error('injected register error') end
      self.name = name; registry[name] = self
    end
    function object:enable() enableCalls = enableCalls + 1; return not options.declineEnable end
    function object:disable() disableCalls = disableCalls + 1 end
    function object:delete()
      deleted[#deleted+1] = self
      if self.name and registry[self.name] == self then registry[self.name] = nil end
    end
    function object:setShaderConst(name, value)
      if options.failConstants then error('injected uniform error') end
      self.constants[name] = value
    end
    return object
  end
  package.loaded['ge/extensions/feel4speed/postfx'] = nil
  realPostfx = require('ge/extensions/feel4speed/postfx')
  return realPostfx
end
local function paramsOf(effect)
  local values = {}
  for number in effect.constants['$f4sParams']:gmatch('[^ ]+') do values[#values+1] = tonumber(number) end
  equal(#values, 4)
  return values
end

test('PostFX initializes lazily, uses private objects and updates uniforms', function()
  resetPostfx()
  local ok, status = realPostfx.set(0, 0)
  equal(ok, true); equal(status, 'disabled'); equal(#created, 0)
  ok, status = realPostfx.set(0.28, 0.025)
  equal(ok, true); truthy(status:find('enabled', 1, true))
  equal(#created, 3); equal(enableCalls, 1)
  local shader = registry.Feel4Speed_Shader
  local stateBlock = registry.Feel4Speed_State
  local effect = registry.Feel4Speed_PostFX
  equal(shader.DXPixelShaderFile, 'art/feel4speed/shaders/feel4speedP.hlsl')
  equal(shader.DXVertexShaderFile, shader.DXPixelShaderFile)
  equal(stateBlock:getField('samplerStates', 0), 'SamplerClampLinear')
  equal(effect:getField('texture', 0), '$backBuffer')
  equal(effect:getField('target', 0), '$backBuffer')
  equal(effect:getField('renderTime', 0), 'PFXAfterDiffuse')
  for _, object in ipairs(created) do equal(object.canSave, false); equal(object:getField('f4sOwner', 0), 'Feel4Speed/1') end
  local values = paramsOf(effect)
  near(values[1], 0.28); near(values[2], 0.025)
  near(values[3], 0.5); near(values[4], 0.5)
  realPostfx.set(0.4, 0.05, {x = 0.4, y = 0.6})
  equal(#created, 3); equal(enableCalls, 1)
  values = paramsOf(effect); near(values[1], 0.4); near(values[3], 0.4); near(values[4], 0.6)
  effect.constants = {}
  _G.Feel4Speed_PostFXCallbacks.setShaderConsts()
  near(paramsOf(effect)[2], 0.05)
  realPostfx.set(0, 0); equal(disableCalls, 1)
  realPostfx.set(0, 0); equal(disableCalls, 1)
  realPostfx.set(0.1, 0); equal(enableCalls, 2)
end)

test('PostFX clamps values and sanitizes invalid parameters', function()
  resetPostfx(); realPostfx.set(2, -3, {x = 3, y = -3})
  local values = paramsOf(registry.Feel4Speed_PostFX)
  equal(values[1], 1); equal(values[2], 0)
  equal(values[3], 0.95); equal(values[4], 0.05)
  realPostfx.set(0/0, 0.1, {x = math.huge, y = 0/0})
  values = paramsOf(registry.Feel4Speed_PostFX)
  equal(values[1], 0); equal(values[2], 0.1)
  equal(values[3], 0.5); equal(values[4], 0.5)
  realPostfx.set(0.2, math.huge)
  values = paramsOf(registry.Feel4Speed_PostFX)
  equal(values[1], 0.2); equal(values[2], 0)
end)

test('PostFX shutdown deletes only owned objects in reverse dependency order', function()
  resetPostfx(); realPostfx.set(0.3, 0.04)
  local callbacks = _G.Feel4Speed_PostFXCallbacks
  realPostfx.shutdown()
  equal(#deleted, 3)
  equal(deleted[1].className, 'PostEffect')
  equal(deleted[2].className, 'GFXStateBlockData')
  equal(deleted[3].className, 'ShaderData')
  equal(next(registry), nil); equal(_G.Feel4Speed_PostFXCallbacks, nil)
  realPostfx.shutdown(); equal(#deleted, 3)
  realPostfx.set(0.2, 0.01); equal(#created, 6)
  registry.Feel4Speed_Shader:setField('f4sOwner', 0, 'AnotherOwner')
  _G.Feel4Speed_PostFXCallbacks = {other = true}
  realPostfx.shutdown()
  equal(#deleted, 5)
  truthy(registry.Feel4Speed_Shader)
  equal(_G.Feel4Speed_PostFXCallbacks.other, true)
  truthy(callbacks ~= _G.Feel4Speed_PostFXCallbacks)
end)

test('PostFX missing API/shader and partial initialization fail with cleanup', function()
  for _, options in ipairs({{missingShader = true}, {failClass = 'PostEffect'},
    {failRegister = 'PostEffect'}}) do
    resetPostfx(options)
    local ok, status = realPostfx.set(0.2, 0.03)
    equal(ok, false); truthy(status:find('unavailable', 1, true))
    equal(next(registry), nil); equal(#deleted, #created)
    equal(_G.Feel4Speed_PostFXCallbacks, nil)
    local count = #created
    equal(realPostfx.set(0.2, 0.03), false); equal(#created, count)
    realPostfx.shutdown()
  end
  resetPostfx(); _G.createObject = nil
  equal(realPostfx.set(0.2, 0.03), false); equal(#created, 0)
end)

test('PostFX name collisions are rejected without touching existing objects', function()
  resetPostfx()
  local existing = {marker = 'belongs to someone else'}
  registry.Feel4Speed_Shader = existing
  local ok, status = realPostfx.set(0.2, 0.03)
  equal(ok, false); truthy(status:find('already in use', 1, true))
  equal(#created, 0); equal(#deleted, 0)
  realPostfx.shutdown()
  equal(registry.Feel4Speed_Shader, existing)
end)

test('PostFX renderer rejection and callback failures are sticky and contained', function()
  resetPostfx({declineEnable = true})
  local ok, status = realPostfx.set(0.2, 0.03)
  equal(ok, false); truthy(status:find('renderer declined', 1, true))
  equal(enableCalls, 1); equal(disableCalls, 1)
  realPostfx.set(0.2, 0.03); equal(enableCalls, 1)
  realPostfx.shutdown()
  resetPostfx({failConstants = true})
  ok, status = realPostfx.set(0.2, 0.03)
  equal(ok, false); truthy(status:find('injected uniform error', 1, true))
  equal(_G.Feel4Speed_PostFXCallbacks.onEnabled(), false)
  -- A rendering callback must not propagate an exception into the game.
  _G.Feel4Speed_PostFXCallbacks.setShaderConsts()
  realPostfx.shutdown()
end)

test('PostFX external scene removal is contained and reset allows recreation', function()
  resetPostfx(); realPostfx.set(0.3, 0.04)
  registry.Feel4Speed_PostFX = nil
  local ok, status = realPostfx.set(0.3, 0.04)
  equal(ok, false); truthy(status:find('was removed', 1, true))
  equal(#created, 3)
  realPostfx.set(0.3, 0.04); equal(#created, 3)
  realPostfx.shutdown()
  equal(realPostfx.set(0.3, 0.04), true)
  equal(#created, 6)
end)

test('controller can recreate its PostFX after a mission changes the scene', function()
  resetController()
  resetPostfx()
  package.loaded['ge/extensions/feel4speed/main'] = nil
  main = require('ge/extensions/feel4speed/main')
  main.onExtensionLoaded()
  warm()
  equal(#created, 3)
  main.onClientEndMission()
  -- BeamNG destroys old level objects before the next level is loaded.
  registry = {}
  main.processCamera(frame())
  equal(main.getState().telemetry.active, true)
  equal(main.getState().status.message, 'Active')
  equal(#created, 6)
  truthy(registry.Feel4Speed_PostFX)
  main.onExtensionUnloaded()
end)

test('serialization releases scene objects before a fresh Lua module recreates them', function()
  resetController()
  resetPostfx()
  package.loaded['ge/extensions/feel4speed/main'] = nil
  main = require('ge/extensions/feel4speed/main')
  main.onExtensionLoaded()
  warm()
  equal(#created, 3)
  local state = main.onSerialize()
  equal(registry.Feel4Speed_PostFX, nil)
  equal(_G.Feel4Speed_PostFXCallbacks, nil)
  package.loaded['ge/extensions/feel4speed/main'] = nil
  main = require('ge/extensions/feel4speed/main')
  main.onDeserialized(state)
  warm()
  equal(#created, 6)
  truthy(registry.Feel4Speed_PostFX)
  main.onExtensionUnloaded()
end)

-- Camera placement geometry and collision checks have their own contracts below.
-- Controller contracts mock placement to verify which signed offset is requested,
-- the camera scope, and that telemetry reports the offset actually accepted.
local function activeTest(name, fn)
  test(name, function()
    local path = 'ge/extensions/feel4speed/distance'
    local previous = package.loaded[path]
    local calls = {}
    package.loaded[path] = {apply = function(data, camera, offset)
      calls[#calls + 1] = {data = data, camera = camera, offset = offset}
      if camera == 'driver' then return 0, 'driver view' end
      local applied = offset * (data.acceptedDistanceFraction or 1)
      data.appliedDistance = applied
      return applied, 'applied'
    end}
    local ok, err = xpcall(function() fn(calls) end, debug.traceback)
    package.loaded[path] = previous
    if not ok then error(err) end
  end)
end
local function resetActiveController(stored)
  -- Preserve the original active regression scenarios with their explicit tune;
  -- separate defaults/profile tests verify the new user-selected settings.
  local tune = {activeEnabled = true, accelerationFov = 6, brakingFov = 8,
    accelerationDistance = 0.30, brakingDistance = 0.35,
    accelReference = 6, accelDeadzone = 0.5, springTime = 0.25,
    springDamping = 0.85, rpmWobble = 0.06, rpmStart = 1000, rpmFull = 6500,
    corneringEnabled = false}
  for key, value in pairs(stored or {}) do tune[key] = value end
  return resetController(tune, true)
end
local function activeTick(speedMs, opts)
  opts = model.copy(opts or {})
  opts.kph = speedMs * 3.6
  local data = frame(opts)
  main.processCamera(data)
  return main.getState(), data
end
local function activeRamp(speedMs, acceleration, seconds, fps, opts)
  local state, data
  opts = model.copy(opts or {})
  opts.dtSim, opts.dtReal = 1 / fps, 1 / fps
  for _ = 1, math.floor(seconds * fps + 0.5) do
    speedMs = speedMs + acceleration / fps
    state, data = activeTick(speedMs, opts)
  end
  return speedMs, state, data
end
local function nearNoActive(state, tolerance)
  near(state.telemetry.acceleration, 0, tolerance or 1e-7)
  near(state.telemetry.kickFov, 0, tolerance or 1e-7)
  near(state.telemetry.distanceOffset, 0, tolerance or 1e-7)
end

activeTest('rapid acceleration in second gear produces a kick before passive speed effects start', function(calls)
  resetActiveController()
  local initial = activeTick(3, {gear = 2})
  equal(initial.telemetry.kickFov, 0)
  local speed, state, data = activeRamp(3, 8, 0.25, 120, {gear = 2})
  truthy(speed * 3.6 < state.settings.startSpeed)
  equal(state.telemetry.strength, 0)
  equal(state.telemetry.extraFov, 0)
  equal(state.telemetry.driftAvailable, false, 'Length-only velocity mocks lack drift direction APIs')
  near(state.telemetry.activeBlend, 1)
  truthy(state.telemetry.acceleration > 7)
  truthy(state.telemetry.kickFov > 4)
  truthy(state.telemetry.distanceOffset > 0.2)
  near(data.res.fov, 56 + state.telemetry.kickFov)
  near(calls[#calls].offset, data.appliedDistance)
  near(data.appliedDistance, state.telemetry.distanceOffset)
  equal(finalEffect().v, 0); equal(finalEffect().b, 0)
end)

activeTest('accelerating and braking cues are signed independently of passive speed strength', function()
  resetActiveController()
  activeTick(80)
  local speed, accelerating = activeRamp(80, 8, 0.5, 120)
  truthy(accelerating.telemetry.strength > 0.8)
  truthy(accelerating.telemetry.kickFov > 5)
  truthy(accelerating.telemetry.distanceOffset > 0.25)
  local _, braking, data = activeRamp(speed, -12, 0.1, 120)
  truthy(braking.telemetry.acceleration < -7)
  truthy(braking.telemetry.kickFov < -1, 'Braking must reverse the FOV cue within 100 ms')
  local passive = model.fov(56, braking.telemetry.strength, braking.settings)
  truthy(data.res.fov < passive)
  near(data.res.fov - passive, braking.telemetry.kickFov)
  truthy(finalEffect().v > 0 and finalEffect().b > 0,
    'The passive speed effects continue independently while braking')
end)

activeTest('downshifting without physical speed change produces no acceleration cue', function()
  resetActiveController()
  for _ = 1, 120 do activeTick(40, {gear = 5, rpm = 1800}) end
  local state = activeTick(40, {gear = 2, rpm = 6500, wheelSpeed = 90})
  nearNoActive(state)
  equal(state.telemetry.speedKph, 144)
  activeTick(40, {gear = 2})
  local _, braking = activeRamp(40, -8, 0.15, 120, {gear = 2})
  truthy(braking.telemetry.kickFov < -6,
    'A downshift that really slows the vehicle must produce the same braking cue')
end)

activeTest('transient acceleration cues settle back to the unchanged passive FOV at constant speed', function()
  resetActiveController()
  activeTick(30)
  local speed, active = activeRamp(30, 8, 0.5, 60)
  truthy(active.telemetry.kickFov > 5)
  local _, settled, data = activeRamp(speed, 0, 5, 60)
  nearNoActive(settled)
  local passive, extra = model.fov(56, settled.telemetry.strength, settled.settings)
  near(data.res.fov, passive, 1e-7)
  near(settled.telemetry.extraFov, extra)
end)

activeTest('total FOV ceiling includes acceleration kick and braking respects the 20-degree floor', function()
  resetActiveController({extraFov = 0, fovLimit = 120})
  activeTick(10, {fov = 118})
  local _, limited, data = activeRamp(10, 8, 0.5, 120, {fov = 118})
  equal(data.res.fov, 120)
  near(limited.telemetry.kickFov, 2)
  equal(limited.telemetry.extraFov, 0)
  resetActiveController({extraFov = 0, fovLimit = 120})
  activeTick(10, {fov = 135})
  _, limited, data = activeRamp(10, 8, 0.5, 120, {fov = 135})
  equal(data.res.fov, 135)
  equal(limited.telemetry.kickFov, 0)
  resetActiveController({extraFov = 0, brakingFov = 20})
  activeTick(40, {fov = 22})
  _, limited, data = activeRamp(40, -12, 0.5, 120, {fov = 22})
  equal(data.res.fov, 20)
  near(limited.telemetry.kickFov, -2)
  resetActiveController({extraFov = 0, brakingFov = 20})
  activeTick(40, {fov = 12})
  _, limited, data = activeRamp(40, -12, 0.5, 120, {fov = 12})
  equal(data.res.fov, 12, 'An unusually low native FOV must not be widened by the floor')
  equal(limited.telemetry.kickFov, 0)
end)

activeTest('switch teleport reset profile reload and camera changes clear and re-prime active motion', function()
  for _, change in ipairs({'switch', 'teleport', 'camera', 'vehicle event', 'reset', 'profile', 'reload'}) do
    resetActiveController()
    activeTick(10)
    local speed, before = activeRamp(10, 8, 0.5, 60)
    truthy(before.telemetry.kickFov > 5)
    local opts = {}
    if change == 'switch' then opts.id = 8
    elseif change == 'teleport' then opts.teleported = true
    elseif change == 'camera' then main.setSetting('orbitOnly', false); activeCamera = 'chase'
    elseif change == 'vehicle event' then main.onVehicleSwitched()
    elseif change == 'profile' then main.applyPreset('balanced')
    elseif change == 'reload' then main.onDeserialized({settings = main.getState().settings})
    else main.resetDefaults() end
    local state = activeTick(speed + 8 / 60, opts)
    truthy(math.abs(state.telemetry.acceleration) < 1e-7, change .. ' must re-prime motion')
    nearNoActive(state)
    equal(state.telemetry.rpm, 0)
  end
end)

activeTest('pause holds active camera cues and resume rebases motion before releasing continuously', function()
  resetActiveController()
  activeTick(10)
  local speed, before, beforeData = activeRamp(10, 8, 0.5, 60)
  truthy(before.telemetry.kickFov > 5)
  local held, paused = activeTick(0, {dtSim = 0, dtReal = 2})
  near(held.telemetry.kickFov, before.telemetry.kickFov)
  near(held.telemetry.distanceOffset, before.telemetry.distanceOffset)
  near(held.telemetry.acceleration, before.telemetry.acceleration)
  near(paused.res.fov, beforeData.res.fov)
  local resumed = activeTick(speed + 20)
  equal(resumed.telemetry.acceleration, 0)
  truthy(resumed.telemetry.kickFov > before.telemetry.kickFov * 0.9)
  truthy(resumed.telemetry.distanceOffset > before.telemetry.distanceOffset * 0.9)
  local _, settled = activeRamp(speed + 20, 0, 5, 60)
  nearNoActive(settled)
end)

activeTest('missing invalid discontinuous and throwing velocity samples clear active cues softly', function()
  for _, kind in ipairs({'missing', 'nan', 'infinite', 'throws', 'jump', 'long frame'}) do
    resetActiveController()
    activeTick(10)
    local speed, before = activeRamp(10, 8, 0.5, 60)
    truthy(before.telemetry.kickFov > 5)
    local data = frame({kph = speed * 3.6})
    if kind == 'missing' then data.vel = nil
    elseif kind == 'nan' then data.vel.length = function() return 0/0 end
    elseif kind == 'infinite' then data.vel.length = function() return math.huge end
    elseif kind == 'throws' then data.vel.length = function() error('removed velocity object') end
    elseif kind == 'jump' then data.vel.length = function() return speed + 100 end
    else data.dtSim, data.dtReal = 1, 1 end
    main.processCamera(data)
    local state = main.getState()
    nearNoActive(state)
    truthy(model.finite(data.res.fov))
    equal(state.suspended, false)
    state = activeTick(50)
    nearNoActive(state)
  end
end)

activeTest('RPM sampler works without a UI app and stationary engine vibration ignores wheel speed', function()
  resetActiveController()
  _G.guihooks = nil
  local missing, untouched = activeTick(0, {rpmBridge = true, wheelSpeed = 100})
  equal(missing.telemetry.rpm, 0)
  equal(missing.telemetry.rpmAvailable, false)
  equal(untouched.res.rot.native, true)
  truthy(#queuedCommands > 0, 'RPM requests must be issued with the UI app absent')
  -- A request without RPM eventually retries and obtains a real engine sample.
  local state, data
  for _ = 1, 30 do state, data = activeTick(0, {rpm = 6500, wheelSpeed = 100}) end
  equal(state.telemetry.rpm, 6500)
  equal(state.telemetry.rpmAvailable, true)
  equal(state.telemetry.speedKph, 0)
  equal(state.telemetry.strength, 0)
  equal(state.telemetry.extraFov, 0)
  equal(state.telemetry.kickFov, 0)
  equal(data.res.fov, 56)
  truthy(data.res.rot.offset ~= nil)
  truthy(math.abs(data.res.rot.offset.pitch) + math.abs(data.res.rot.offset.yaw) +
    math.abs(data.res.rot.offset.roll) > 0,
    'Stationary high engine RPM must produce vibration without wheel-speed FOV')
  equal(finalEffect().v, 0); equal(finalEffect().b, 0)
  for _ = 1, 40 do state, data = activeTick(0, {rpmBridge = true, wheelSpeed = 100}) end
  equal(state.telemetry.rpm, 0)
  equal(state.telemetry.rpmAvailable, false)
  truthy(state.telemetry.rpmStrength < 0.3, 'Stale RPM must release vibration smoothly')
  for _ = 1, 120 do state, data = activeTick(0, {rpmBridge = true, wheelSpeed = 100}) end
  near(state.telemetry.rpmStrength, 0, 1e-7)
  if data.res.rot.offset then
    near(data.res.rot.offset.pitch, 0, 1e-7)
    near(data.res.rot.offset.yaw, 0, 1e-7)
    near(data.res.rot.offset.roll, 0, 1e-7)
  end
end)

activeTest('RPM vibration remains independently adjustable when acceleration feedback is off and holds while paused', function()
  resetActiveController({activeEnabled = false})
  for _ = 1, 120 do activeTick(0, {rpm = 6500}) end
  local before, beforeData = activeTick(0, {rpm = 6500})
  truthy(before.telemetry.rpmStrength > 0.99)
  equal(before.telemetry.kickFov, 0)
  local commands = #queuedCommands
  local paused, pausedData = activeTick(100, {rpm = 0, dtSim = 0, dtReal = 5})
  equal(#queuedCommands, commands, 'Pause must not poll or advance the RPM sampler')
  equal(paused.telemetry.rpm, before.telemetry.rpm)
  near(paused.telemetry.rpmStrength, before.telemetry.rpmStrength)
  near(pausedData.res.rot.offset.pitch, beforeData.res.rot.offset.pitch)
  near(pausedData.res.rot.offset.yaw, beforeData.res.rot.offset.yaw)
  near(pausedData.res.rot.offset.roll, beforeData.res.rot.offset.roll)
  local _, state, data = activeRamp(0, 8, 0.5, 60, {rpm = 6500})
  equal(state.telemetry.kickFov, 0)
  equal(state.telemetry.distanceOffset, 0)
  truthy(state.telemetry.rpmStrength > 0.99)
  truthy(data.res.rot.offset ~= nil)
end)

activeTest('turning off active feedback preserves passive effects exactly and FOV-only disables all added cues', function()
  resetActiveController()
  activeTick(10)
  local speed, before = activeRamp(10, 8, 0.5, 60)
  truthy(before.telemetry.kickFov > 5)
  main.setSetting('activeEnabled', false)
  main.setSetting('rpmWobble', 0)
  local state, data = activeTick(speed + 8 / 60)
  near(state.telemetry.kickFov, 0)
  near(state.telemetry.distanceOffset, 0)
  local passive, extra = model.fov(56, state.telemetry.strength, state.settings)
  near(data.res.fov, passive)
  near(state.telemetry.extraFov, extra)
  near(finalEffect().v, state.settings.vignette * state.telemetry.strength)
  near(finalEffect().b, state.settings.blur * state.telemetry.strength)
  main.applyPreset('clean')
  equal(main.getState().settings.activeEnabled, false)
  equal(main.getState().settings.rpmWobble, 0)
  equal(main.getState().settings.corneringEnabled, false)
  for _ = 1, 20 do state, data = activeTick(speed + 5, {rpm = 6500}) end
  equal(state.telemetry.kickFov, 0)
  equal(state.telemetry.distanceOffset, 0)
  equal(data.res.rot.native, true)
  truthy(data.res.fov > 56)
  equal(finalEffect().v, 0); equal(finalEffect().b, 0)
end)

activeTest('controller reports accepted camera spring distance and leaves driver position unchanged', function(calls)
  resetActiveController()
  activeTick(10)
  local speed = activeRamp(10, 8, 0.5, 60)
  local data = frame({kph = (speed + 8 / 60) * 3.6})
  data.acceptedDistanceFraction = 0.5
  main.processCamera(data)
  local state = main.getState()
  truthy(calls[#calls].offset > 0.25)
  near(state.telemetry.distanceOffset, calls[#calls].offset * 0.5)
  main.setSetting('orbitOnly', false)
  activeCamera = 'driver'
  activeTick(speed)
  local _, driver, driverData = activeRamp(speed, 8, 0.5, 60)
  truthy(driver.telemetry.kickFov > 5)
  equal(driver.telemetry.distanceOffset, 0)
  equal(driverData.appliedDistance or 0, 0)
end)

local function driftTrace(allow, acceleration, settings, opts)
  settings = model.copy(settings or {})
  settings.activeWhileDrifting = allow
  opts = model.copy(opts or {})
  opts.slipAngle, opts.rpm = 0, 6700
  resetController(settings, true)
  activeTick(35, opts)
  local speed = activeRamp(35, acceleration, 0.5, 120, opts)
  local state, data
  -- A 20-degree slip at these speeds keeps the velocity vector continuous enough
  -- to exercise drift dwell, rather than the discontinuity recovery path.
  opts.slipAngle = 20
  speed, state, data = activeRamp(speed, acceleration, 1.2, 120, opts)
  return speed, state, data, model.copy(finalEffect())
end

activeTest('drifting suppresses sustained acceleration and braking cues while preserving passive effects and RPM', function()
  for _, acceleration in ipairs({8, -8}) do
    local _, allowed, allowedData, allowedEffect = driftTrace(true, acceleration)
    local _, suppressed, data, effect = driftTrace(false, acceleration)
    equal(allowed.settings.activeWhileDrifting, true)
    equal(suppressed.settings.activeWhileDrifting, false)
    equal(allowed.telemetry.drifting, true)
    equal(suppressed.telemetry.drifting, true)
    equal(suppressed.telemetry.driftAvailable, true)
    near(suppressed.telemetry.slipAngle, 20, 1e-8)
    near(allowed.telemetry.activeBlend, 1)
    truthy(suppressed.telemetry.activeBlend < 0.01)
    truthy(allowed.telemetry.kickFov * acceleration > 0)
    truthy(allowed.telemetry.distanceOffset * acceleration > 0)
    near(suppressed.telemetry.kickFov,
      allowed.telemetry.kickFov * suppressed.telemetry.activeBlend, 1e-8)
    near(suppressed.telemetry.distanceOffset,
      allowed.telemetry.distanceOffset * suppressed.telemetry.activeBlend, 1e-8)
    near(suppressed.telemetry.acceleration, allowed.telemetry.acceleration)
    near(suppressed.telemetry.strength, allowed.telemetry.strength)
    near(suppressed.telemetry.extraFov, allowed.telemetry.extraFov)
    near(effect.v, allowedEffect.v); near(effect.b, allowedEffect.b)
    equal(suppressed.telemetry.rpm, 6700)
    near(suppressed.telemetry.rpmStrength, allowed.telemetry.rpmStrength)
    near(data.res.rot.offset.pitch, allowedData.res.rot.offset.pitch)
    near(data.res.rot.offset.yaw, allowedData.res.rot.offset.yaw)
    near(data.res.rot.offset.roll, allowedData.res.rot.offset.roll)
    local passive = model.fov(56, suppressed.telemetry.strength, suppressed.settings)
    near(data.res.fov - passive, suppressed.telemetry.kickFov)
  end
end)

activeTest('drift blending fades the already bounded visible kick at ceiling and braking floor', function()
  for _, case in ipairs({{acceleration = 8, fov = 119.5, kick = 0.5},
    {acceleration = -8, fov = 20.5, kick = -0.5}}) do
    local _, allowed = driftTrace(true, case.acceleration, {extraFov = 0}, {fov = case.fov})
    local _, gated, data = driftTrace(false, case.acceleration, {extraFov = 0}, {fov = case.fov})
    near(allowed.telemetry.kickFov, case.kick)
    truthy(gated.telemetry.activeBlend < 0.01)
    near(gated.telemetry.kickFov, case.kick * gated.telemetry.activeBlend, 1e-9)
    near(data.res.fov, case.fov + case.kick * gated.telemetry.activeBlend, 1e-9)
  end
end)

activeTest('drift exit uses its dwell and restores active cues gradually during continued acceleration', function()
  local speed, before = driftTrace(false, 8)
  local speed2, held = activeRamp(speed, 8, 0.25, 120, {slipAngle = 0, rpm = 6700})
  equal(held.telemetry.drifting, true, 'Brief grip recovery must not immediately end a drift')
  truthy(held.telemetry.activeBlend <= before.telemetry.activeBlend)
  local speed3, exit = activeRamp(speed2, 8, 0.1, 120, {slipAngle = 0, rpm = 6700})
  equal(exit.telemetry.drifting, false)
  truthy(exit.telemetry.activeBlend > held.telemetry.activeBlend)
  truthy(exit.telemetry.activeBlend < 0.3, 'Recovery must blend in without an immediate camera snap')
  local _, recovered = activeRamp(speed3, 8, 2, 120, {slipAngle = 0, rpm = 6700})
  truthy(recovered.telemetry.activeBlend > 0.99)
  truthy(recovered.telemetry.kickFov > 1)
  truthy(recovered.telemetry.distanceOffset > 0.2)
end)

activeTest('the active-while-drifting setting restores cues smoothly without disabling drift detection', function()
  local speed, before = driftTrace(false, -8)
  truthy(before.telemetry.activeBlend < 0.01)
  equal(before.telemetry.drifting, true)
  equal(main.setSetting('activeWhileDrifting', true), true)
  local state = activeTick(speed - 8 / 120, {slipAngle = 35, rpm = 6700, dtSim = 1/120, dtReal = 1/120})
  equal(state.telemetry.drifting, true)
  truthy(state.telemetry.activeBlend > before.telemetry.activeBlend)
  truthy(state.telemetry.activeBlend < 0.1, 'Opting in must retain the smooth release')
  local _, restored = activeRamp(speed - 8 / 120, -8, 2, 120, {slipAngle = 35, rpm = 6700})
  equal(restored.telemetry.drifting, true)
  truthy(restored.telemetry.activeBlend > 0.99)
  truthy(restored.telemetry.kickFov < -1)
  truthy(restored.telemetry.distanceOffset < -0.15)
end)

activeTest('ordinary turns reverse driving low speed and short lateral blips keep active cues available', function()
  for _, scenario in ipairs({'turn', 'reverse', 'low speed', 'brief slip'}) do
    resetController(nil, true)
    local speed = scenario == 'low speed' and 1 or 20
    activeTick(speed, {slipAngle = 0})
    local state
    for index = 1, 120 do
      local opts = {slipAngle = 0}
      if scenario == 'turn' then opts.carAngle, opts.slipAngle = index * 1.5, 6
      elseif scenario == 'reverse' then opts.slipAngle = 180
      elseif scenario == 'low speed' then opts.slipAngle = 60
      elseif index >= 50 and index < 54 then opts.slipAngle = 35 end
      state = activeTick(speed, opts)
      equal(state.telemetry.drifting, false, scenario .. ' must not suppress active effects')
      near(state.telemetry.activeBlend, 1)
    end
    if scenario == 'reverse' then near(state.telemetry.slipAngle, 0, 1e-7) end
    if scenario == 'turn' then near(state.telemetry.slipAngle, 6, 1e-7) end
  end
end)

activeTest('pause holds drift detection and blend and resumes the active release continuously', function()
  local speed, before, beforeData = driftTrace(false, 8)
  local held, data = activeTick(0, {slipAngle = 0, dtSim = 0, dtReal = 5, rpm = 0})
  equal(held.telemetry.drifting, before.telemetry.drifting)
  equal(held.telemetry.driftAvailable, before.telemetry.driftAvailable)
  near(held.telemetry.slipAngle, before.telemetry.slipAngle)
  near(held.telemetry.activeBlend, before.telemetry.activeBlend)
  near(data.res.fov, beforeData.res.fov)
  near(held.telemetry.kickFov, before.telemetry.kickFov)
  near(held.telemetry.distanceOffset, before.telemetry.distanceOffset)
  local resumed = activeTick(speed, {slipAngle = 35, rpm = 6700})
  equal(resumed.telemetry.drifting, true)
  truthy(resumed.telemetry.activeBlend <= held.telemetry.activeBlend)
  truthy(resumed.telemetry.activeBlend > held.telemetry.activeBlend * 0.8)
  equal(resumed.telemetry.acceleration, 0)
end)

activeTest('vehicle teleport camera profile and settings reset clear drift suppression to neutral', function()
  for _, change in ipairs({'switch', 'teleport', 'camera', 'vehicle event', 'profile', 'reset', 'reload'}) do
    local speed, before = driftTrace(false, 8)
    equal(before.telemetry.drifting, true)
    truthy(before.telemetry.activeBlend < 0.01)
    local opts = {slipAngle = 0}
    if change == 'switch' then opts.id = 8
    elseif change == 'teleport' then opts.teleported = true
    elseif change == 'camera' then main.setSetting('orbitOnly', false); activeCamera = 'chase'
    elseif change == 'vehicle event' then main.onVehicleSwitched()
    elseif change == 'profile' then main.applyPreset('balanced')
    elseif change == 'reload' then main.onDeserialized({settings = main.getState().settings})
    else main.resetDefaults() end
    local state = activeTick(speed, opts)
    equal(state.telemetry.drifting, false, change .. ' must clear the previous drift state')
    near(state.telemetry.activeBlend, 1)
    nearNoActive(state)
  end
end)

activeTest('unavailable direction or velocity components fail softly and restore the active layer smoothly', function()
  for _, invalid in ipairs({'length only', 'missing', 'throws', 'invalid', 'vertical', 'velocity'}) do
    local speed, before = driftTrace(false, 8)
    local opts = {slipAngle = 35, forwardState = invalid}
    if invalid == 'length only' then opts.slipAngle = nil end
    local function unavailableFrame(atSpeed)
      local data = frame({kph = atSpeed * 3.6, slipAngle = opts.slipAngle,
        forwardState = opts.forwardState})
      if invalid == 'velocity' then data.vel.x = math.huge end
      return data
    end
    speed = speed + 8 / 60
    local data = unavailableFrame(speed)
    main.processCamera(data)
    local state = main.getState()
    equal(state.telemetry.driftAvailable, false, invalid .. ' must report unavailable drift data')
    equal(state.telemetry.drifting, false)
    truthy(state.telemetry.activeBlend > before.telemetry.activeBlend)
    truthy(state.telemetry.activeBlend < 0.1, 'Losing direction telemetry must not snap the camera')
    for _ = 1, 120 do
      speed = speed + 8 / 60
      data = unavailableFrame(speed)
      main.processCamera(data)
    end
    state = main.getState()
    equal(state.telemetry.driftAvailable, false)
    equal(state.telemetry.drifting, false)
    truthy(state.telemetry.activeBlend > 0.99)
    truthy(state.telemetry.kickFov > 1, 'Missing drift APIs must preserve active acceleration feedback')
    truthy(model.finite(data.res.fov))
    equal(state.suspended, false)
  end
end)

local function turnFrames(speed, heading, rate, seconds, fps, opts, acceleration)
  opts = model.copy(opts or {})
  opts.slipAngle = opts.slipAngle or 0
  opts.dtSim, opts.dtReal = 1 / fps, 1 / fps
  local state, data
  for _ = 1, math.floor(seconds * fps + 0.5) do
    speed = speed + (acceleration or 0) / fps
    heading = heading + rate * 180 / math.pi / fps
    opts.carAngle = heading
    state, data = activeTick(speed, opts)
  end
  return speed, heading, state, data
end
local function cornerTrace(settings, rate, opts, acceleration)
  -- Existing direction-sensitive fixtures retain the established outward tune.
  -- New inward/default behavior is covered separately with inversion enabled.
  local tune = {activeEnabled = false, wobble = 0, rpmWobble = 0, corneringInvert = false}
  for key, value in pairs(settings or {}) do tune[key] = value end
  resetController(tune, true)
  activeTick(20, opts or {slipAngle = 0})
  local speed, heading, state, data = turnFrames(20, 0, rate or 0.25, 2, 120, opts, acceleration)
  return speed, heading, state, data, model.copy(finalEffect())
end

activeTest('constant-speed left and right turns create opposite outward lean on the pure camera-local Y axis', function()
  local turns = {}
  for _, rate in ipairs({-0.25, 0.25}) do
    local _, _, state, data = cornerTrace(nil, rate)
    equal(state.settings.activeEnabled, false)
    equal(state.telemetry.corneringAvailable, true)
    equal(state.telemetry.drifting, false)
    near(state.telemetry.corneringBlend, 1)
    near(state.telemetry.lateralG, -20 * rate / 9.80665, 0.002)
    truthy(state.telemetry.corneringRoll * state.telemetry.lateralG > 0)
    truthy(math.abs(state.telemetry.corneringRoll) > 0.5)
    near(data.res.rot.offset.pitch, 0)
    near(data.res.rot.offset.roll, 0)
    near(data.res.rot.offset.yaw, -state.telemetry.corneringRoll * math.pi / 180)
    equal(data.res.rot.base.native, true)
    equal(state.telemetry.kickFov, 0)
    equal(state.telemetry.distanceOffset, 0)
    turns[#turns + 1] = state.telemetry.corneringRoll
  end
  near(turns[1], -turns[2], 1e-8)
end)

activeTest('the release default leans into both turns and opting out restores equal opposite outward lean', function()
  for _, rate in ipairs({-0.25, 0.25}) do
    local _, _, outward = cornerTrace({corneringInvert = false}, rate)
    local _, _, inward, data = cornerTrace({corneringInvert = model.defaults().corneringInvert}, rate)
    equal(inward.settings.corneringInvert, true)
    near(inward.telemetry.lateralG, -20 * rate / 9.80665, 0.002)
    truthy(inward.telemetry.corneringRoll * inward.telemetry.lateralG < 0,
      'Inward lean opposes the measured lateral-force sign')
    truthy(math.abs(inward.telemetry.corneringRoll) > 0.5)
    near(inward.telemetry.corneringRoll, -outward.telemetry.corneringRoll)
    near(inward.telemetry.lateralG, outward.telemetry.lateralG)
    near(inward.telemetry.fov, outward.telemetry.fov)
    near(inward.telemetry.distanceOffset, outward.telemetry.distanceOffset)
    near(data.res.rot.offset.pitch, 0)
    near(data.res.rot.offset.roll, 0)
    near(data.res.rot.offset.yaw, -inward.telemetry.corneringRoll * math.pi / 180)
  end
end)

activeTest('changing lean direction under load passes smoothly through neutral without changing force or other layers', function()
  local function trajectory(invert)
    local speed, heading, before = cornerTrace({corneringInvert = false, activeEnabled = true,
      wobble = 0.12, rpmWobble = 0.03, corneringLimit = 2}, -0.25,
      {slipAngle = 0, rpm = 6700}, 8)
    truthy(before.telemetry.corneringRoll > 1)
    truthy(before.telemetry.kickFov > 1)
    truthy(before.telemetry.distanceOffset > 0.2)
    local frames = {}
    if invert then
      equal(main.setSetting('corneringInvert', true), true)
      near(main.getState().telemetry.corneringRoll, before.telemetry.corneringRoll,
        1e-10, 'Changing direction must retain the current visible lean until the next sample')
    end
    for index = 1, 120 do
      speed = speed + 8 / 120
      heading = heading - 0.25 * 180 / math.pi / 120
      local state, data = activeTick(speed, {slipAngle = 0, carAngle = heading,
        rpm = 6700, dtSim = 1/120, dtReal = 1/120})
      frames[index] = {state = state, data = data, effect = model.copy(finalEffect())}
    end
    return before, frames
  end
  local _, unchanged = trajectory(false)
  local before, changed = trajectory(true)
  truthy(changed[1].state.telemetry.corneringRoll > 0,
    'The first inverted sample must retain the previous lean direction')
  truthy(changed[1].state.telemetry.corneringRoll < before.telemetry.corneringRoll)
  truthy(changed[#changed].state.telemetry.corneringRoll < -1)
  local crossed = false
  local previous = before.telemetry.corneringRoll
  for index, sample in ipairs(changed) do
    local state, baseline = sample.state, unchanged[index].state
    local roll = state.telemetry.corneringRoll
    truthy(math.abs(roll) <= state.settings.corneringLimit)
    truthy(math.abs(roll - previous) < 0.2, 'Direction changes must not snap the camera')
    if previous > 0 and roll <= 0 then
      crossed = true
      truthy(previous < 0.2 and roll > -0.2, 'Direction reversal must pass through neutral')
    end
    for _, key in ipairs({'lateralG', 'acceleration', 'fov', 'extraFov', 'kickFov',
      'distanceOffset', 'strength', 'rpm', 'rpmStrength', 'activeBlend', 'corneringBlend'}) do
      near(state.telemetry[key], baseline.telemetry[key], 1e-10,
        'Independent feedback while changing lean direction ' .. key)
    end
    equal(state.settings.activeWhileDrifting, baseline.settings.activeWhileDrifting)
    equal(state.settings.corneringWhileDrifting, baseline.settings.corneringWhileDrifting)
    near(sample.effect.v, unchanged[index].effect.v)
    near(sample.effect.b, unchanged[index].effect.b)
    previous = roll
  end
  truthy(crossed)
end)

activeTest('inward lean retains its independent suppression and opt-in behavior during drifting', function()
  for _, rate in ipairs({-0.15, 0.15}) do
    local _, _, allowed = cornerTrace({corneringInvert = true, activeEnabled = true,
      corneringWhileDrifting = true}, rate, {slipAngle = 20}, 8)
    local _, _, gated = cornerTrace({corneringInvert = true, activeEnabled = true,
      corneringWhileDrifting = false}, rate, {slipAngle = 20}, 8)
    equal(allowed.telemetry.drifting, true)
    equal(gated.telemetry.drifting, true)
    truthy(allowed.telemetry.corneringRoll * allowed.telemetry.lateralG < 0)
    near(allowed.telemetry.corneringBlend, 1)
    truthy(gated.telemetry.corneringBlend < 0.01)
    near(gated.telemetry.corneringRoll,
      allowed.telemetry.corneringRoll * gated.telemetry.corneringBlend, 1e-8)
    near(gated.telemetry.lateralG, allowed.telemetry.lateralG)
    near(gated.telemetry.fov, allowed.telemetry.fov)
    near(gated.telemetry.distanceOffset, allowed.telemetry.distanceOffset)
    near(gated.telemetry.activeBlend, allowed.telemetry.activeBlend)
  end
end)

activeTest('cornering lean changes neither FOV nor camera distance post effects or the existing wobble composition', function()
  local _, _, off, offData, offEffect = cornerTrace({corneringEnabled = false,
    wobble = 0.12, rpmWobble = 0.03}, -0.25, {slipAngle = 0, rpm = 6700})
  local _, _, on, onData, onEffect = cornerTrace({corneringEnabled = true,
    wobble = 0.12, rpmWobble = 0.03}, -0.25, {slipAngle = 0, rpm = 6700})
  truthy(on.telemetry.corneringRoll > 0.5)
  equal(off.telemetry.corneringRoll, 0)
  near(on.telemetry.fov, off.telemetry.fov)
  near(on.telemetry.extraFov, off.telemetry.extraFov)
  near(on.telemetry.kickFov, off.telemetry.kickFov)
  near(on.telemetry.distanceOffset, off.telemetry.distanceOffset)
  near(onEffect.v, offEffect.v); near(onEffect.b, offEffect.b)
  equal(on.telemetry.rpm, off.telemetry.rpm)
  near(on.telemetry.rpmStrength, off.telemetry.rpmStrength)
  near(onData.res.rot.offset.pitch, 0)
  near(onData.res.rot.offset.roll, 0)
  near(onData.res.rot.offset.yaw, -on.telemetry.corneringRoll * math.pi / 180)
  near(onData.res.rot.base.offset.pitch, offData.res.rot.offset.pitch)
  near(onData.res.rot.base.offset.yaw, offData.res.rot.offset.yaw)
  near(onData.res.rot.base.offset.roll, offData.res.rot.offset.roll)
end)

activeTest('cornering strength deadzone limit and independent toggle produce bounded tunable lean', function()
  local speed, heading, limited = cornerTrace({corneringStrength = 6,
    corneringLimit = 1, corneringDeadzone = 0}, 1)
  truthy(math.abs(limited.telemetry.lateralG) > 2)
  truthy(math.abs(limited.telemetry.corneringRoll) > 0.99)
  truthy(math.abs(limited.telemetry.corneringRoll) <= 1)
  equal(main.setSetting('corneringEnabled', false), true)
  equal(main.getState().telemetry.corneringRoll, 0, 'The cornering switch clears applied lean immediately')
  local state, data = activeTick(speed, {slipAngle = 0, carAngle = heading})
  equal(state.telemetry.corneringRoll, 0)
  equal(data.res.rot.native, true)
  equal(main.setSetting('corneringEnabled', true), true)
  state = activeTick(speed, {slipAngle = 0, carAngle = heading})
  equal(state.telemetry.corneringRoll, 0, 'Re-enabling must prime at current velocity')
  local _, _, returned = turnFrames(speed, heading, 1, 1, 120)
  truthy(math.abs(returned.telemetry.corneringRoll) > 0.9)
  local _, _, deadzone = cornerTrace({corneringDeadzone = 1}, 0.25)
  truthy(math.abs(deadzone.telemetry.lateralG) > 0.4)
  equal(deadzone.telemetry.corneringRoll, 0)
  local _, _, zero = cornerTrace({corneringStrength = 0}, 0.25)
  equal(zero.telemetry.corneringRoll, 0)
end)

activeTest('cornering and acceleration drift permissions control their own blends independently', function()
  local results = {}
  for _, activeAllowed in ipairs({false, true}) do
    for _, rollAllowed in ipairs({false, true}) do
      local _, _, state, data, effect = cornerTrace({activeEnabled = true,
        activeWhileDrifting = activeAllowed, corneringWhileDrifting = rollAllowed},
        0.15, {slipAngle = 20}, 8)
      equal(state.telemetry.drifting, true)
      equal(state.telemetry.corneringAvailable, true)
      if activeAllowed then near(state.telemetry.activeBlend, 1)
      else truthy(state.telemetry.activeBlend < 0.01) end
      if rollAllowed then near(state.telemetry.corneringBlend, 1)
      else truthy(state.telemetry.corneringBlend < 0.01) end
      results[tostring(activeAllowed) .. '/' .. tostring(rollAllowed)] = {state = state, data = data, effect = effect}
    end
  end
  for _, activeAllowed in ipairs({false, true}) do
    local gated = results[tostring(activeAllowed) .. '/false']
    local allowed = results[tostring(activeAllowed) .. '/true']
    near(gated.state.telemetry.corneringRoll,
      allowed.state.telemetry.corneringRoll * gated.state.telemetry.corneringBlend, 1e-8)
    near(gated.state.telemetry.lateralG, allowed.state.telemetry.lateralG)
    near(gated.state.telemetry.fov, allowed.state.telemetry.fov)
    near(gated.state.telemetry.distanceOffset, allowed.state.telemetry.distanceOffset)
    near(gated.effect.v, allowed.effect.v); near(gated.effect.b, allowed.effect.b)
  end
  near(results['false/true'].state.telemetry.corneringRoll,
    results['true/true'].state.telemetry.corneringRoll)
end)

activeTest('cornering drift opt-in blends lean back while the drift and acceleration policy stay unchanged', function()
  local speed, heading, before = cornerTrace({activeEnabled = true},
    0.15, {slipAngle = 20}, 8)
  equal(before.telemetry.drifting, true)
  truthy(before.telemetry.corneringBlend < 0.01)
  equal(main.setSetting('corneringWhileDrifting', true), true)
  local _, _, first = turnFrames(speed, heading, 0.15, 1 / 120, 120, {slipAngle = 20}, 8)
  equal(first.telemetry.drifting, true)
  truthy(first.telemetry.corneringBlend > before.telemetry.corneringBlend)
  truthy(first.telemetry.corneringBlend < 0.1)
  truthy(first.telemetry.activeBlend < 0.01)
  local _, _, restored = turnFrames(speed + 8 / 120, heading + 0.15 * 180 / math.pi / 120,
    0.15, 2, 120, {slipAngle = 20}, 8)
  truthy(restored.telemetry.corneringBlend > 0.99)
  truthy(math.abs(restored.telemetry.corneringRoll) > 0.5)
  truthy(restored.telemetry.activeBlend < 0.01)
end)

activeTest('pause holds cornering lean and resume rebases velocity before a smooth neutral release', function()
  local speed, heading, before, beforeData = cornerTrace(nil, -0.25)
  local held, heldData = activeTick(0, {slipAngle = 0, carAngle = 0, dtSim = 0, dtReal = 5})
  near(held.telemetry.lateralG, before.telemetry.lateralG)
  near(held.telemetry.corneringRoll, before.telemetry.corneringRoll)
  near(held.telemetry.corneringBlend, before.telemetry.corneringBlend)
  equal(held.telemetry.corneringAvailable, before.telemetry.corneringAvailable)
  near(heldData.res.rot.offset.yaw, beforeData.res.rot.offset.yaw)
  local resumed = activeTick(speed + 40, {slipAngle = 0, carAngle = heading + 100})
  near(resumed.telemetry.lateralG, 0)
  truthy(resumed.telemetry.corneringRoll > before.telemetry.corneringRoll * 0.8)
  truthy(resumed.telemetry.corneringRoll <= before.telemetry.corneringRoll)
  local state
  for _ = 1, 240 do state = activeTick(speed + 40, {slipAngle = 0, carAngle = heading + 100}) end
  near(state.telemetry.corneringRoll, 0, 1e-7)
end)

activeTest('lowering the cornering ceiling while paused clamps visible lean and preserves held feedback', function()
  local speed, heading, before = cornerTrace({corneringStrength = 6, corneringLimit = 2.8,
    activeEnabled = true, wobble = 0.12, rpmWobble = 0.03}, -0.4,
    {slipAngle = 0, rpm = 6700}, 8)
  truthy(before.telemetry.corneringRoll > 2.7)
  truthy(before.telemetry.kickFov > 1)
  truthy(before.telemetry.distanceOffset > 0.2)
  truthy(before.telemetry.rpmStrength > 0.99)
  local held = activeTick(speed, {slipAngle = 0, carAngle = heading,
    rpm = 6700, dtSim = 0, dtReal = 1})
  equal(main.setSetting('corneringLimit', 1), true)
  local limited, data = activeTick(speed, {slipAngle = 0, carAngle = heading,
    rpm = 6700, dtSim = 0, dtReal = 1})
  near(limited.telemetry.corneringRoll, 1)
  truthy(math.abs(limited.telemetry.corneringRoll) <= limited.settings.corneringLimit)
  near(data.res.rot.offset.yaw, -math.pi / 180)
  for _, key in ipairs({'lateralG', 'acceleration', 'strength', 'extraFov', 'kickFov',
    'distanceOffset', 'rpm', 'rpmStrength', 'activeBlend', 'corneringBlend'}) do
    near(limited.telemetry[key], held.telemetry[key], 1e-10, 'Held feedback ' .. key)
  end
  equal(limited.telemetry.corneringAvailable, held.telemetry.corneringAvailable)
  equal(limited.telemetry.rpmAvailable, held.telemetry.rpmAvailable)
  near(limited.telemetry.fov, held.telemetry.fov)
end)

activeTest('vehicle camera profile settings and reload transitions re-prime cornering lean', function()
  for _, change in ipairs({'switch', 'teleport', 'camera', 'vehicle event', 'profile', 'reset', 'reload'}) do
    local speed, heading, before = cornerTrace(nil, -0.25)
    truthy(before.telemetry.corneringRoll > 0.5)
    local opts = {slipAngle = 0, carAngle = heading}
    if change == 'switch' then opts.id = 8
    elseif change == 'teleport' then opts.teleported = true
    elseif change == 'camera' then main.setSetting('orbitOnly', false); activeCamera = 'chase'
    elseif change == 'vehicle event' then main.onVehicleSwitched()
    elseif change == 'profile' then main.applyPreset('balanced')
    elseif change == 'reload' then main.onDeserialized({settings = main.getState().settings})
    else main.resetDefaults() end
    local state = activeTick(speed, opts)
    near(state.telemetry.lateralG, 0)
    near(state.telemetry.corneringRoll, 0)
    near(state.telemetry.corneringBlend, 1)
  end
end)

activeTest('master camera VR and editor exclusions remove cornering lean from native output', function()
  for _, exclusion in ipairs({'master', 'driver', 'free', 'VR', 'editor'}) do
    local speed, heading, before = cornerTrace(nil, -0.25)
    truthy(before.telemetry.corneringRoll > 0.5)
    local opts = {slipAngle = 0, carAngle = heading}
    if exclusion == 'master' then main.setEnabled(false)
    elseif exclusion == 'driver' then activeCamera = 'driver'
    elseif exclusion == 'free' then activeCamera = 'free'
    elseif exclusion == 'VR' then opts.vr = true
    else _G.editor = {active = true} end
    local state, data = activeTick(speed, opts)
    equal(state.telemetry.active, false)
    equal(state.telemetry.corneringRoll, 0)
    equal(data.res.rot.native, true)
    equal(data.res.fov, 56)
  end
end)

activeTest('missing invalid and throwing cornering data release lean softly without disabling camera effects', function()
  for _, invalid in ipairs({'length only', 'missing', 'throws', 'invalid', 'vertical', 'velocity', 'long frame'}) do
    local speed, heading, before = cornerTrace(nil, -0.25)
    local opts = {slipAngle = 0, carAngle = heading, forwardState = invalid}
    if invalid == 'length only' then opts.slipAngle = nil end
    if invalid == 'long frame' then opts.dtSim, opts.dtReal = 1, 1 end
    local data = frame({kph = speed * 3.6, slipAngle = opts.slipAngle,
      carAngle = opts.carAngle, forwardState = opts.forwardState,
      dtSim = opts.dtSim, dtReal = opts.dtReal})
    if invalid == 'velocity' then data.vel.x = math.huge end
    main.processCamera(data)
    local state = main.getState()
    equal(state.telemetry.corneringAvailable, false)
    truthy(state.telemetry.corneringRoll > 0)
    truthy(state.telemetry.corneringRoll < before.telemetry.corneringRoll)
    equal(state.telemetry.active, true)
    equal(state.suspended, false)
    truthy(model.finite(data.res.fov))
  end
end)

activeTest('unavailable or failing quaternion roll reports zero applied lean and preserves the native camera safely', function()
  for _, failure in ipairs({'missing', 'constructor', 'multiplication'}) do
    local speed, heading, before = cornerTrace(nil, -0.25)
    truthy(before.telemetry.corneringRoll > 0.5)
    local saved = _G.quatFromEuler
    if failure == 'missing' then _G.quatFromEuler = nil
    elseif failure == 'constructor' then
      _G.quatFromEuler = function() error('roll constructor unavailable') end
    else
      _G.quatFromEuler = function() return setmetatable({}, {
        __mul = function() error('roll multiplication unavailable') end}) end
    end
    local ok, state, data = pcall(activeTick, speed, {slipAngle = 0, carAngle = heading})
    _G.quatFromEuler = saved
    truthy(ok, tostring(state))
    equal(state.telemetry.corneringAvailable, true)
    truthy(state.telemetry.lateralG > 0.3)
    equal(state.telemetry.corneringRoll, 0)
    equal(state.status.cornering, 'rotation unavailable')
    equal(data.res.rot.native, true)
    equal(state.telemetry.active, true)
    equal(state.suspended, false)
    local _, _, recovered = turnFrames(speed, heading, -0.25, 0.1, 120)
    truthy(recovered.telemetry.corneringRoll > 0.4)
    equal(recovered.status.cornering, 'active')
  end
end)

activeTest('FOV-only preset disables established cornering lean and its saved profile persists independently', function()
  local speed, heading, before = cornerTrace(nil, -0.25)
  truthy(before.telemetry.corneringRoll > 0.5)
  equal(main.applyPreset('clean'), true)
  equal(main.getState().settings.corneringEnabled, false)
  local state, data = activeTick(speed, {slipAngle = 0, carAngle = heading})
  equal(state.telemetry.corneringRoll, 0)
  equal(data.res.rot.native, true)
  truthy(data.res.fov > 56)
  local saved = {corneringEnabled = false, corneringStrength = 4,
    corneringLimit = 12, corneringDeadzone = 0.3, corneringResponse = 0.6,
    corneringWhileDrifting = true, corneringInvert = false}
  resetController(saved, true)
  for key, expected in pairs(saved) do equal(main.getState().settings[key], expected) end
  main.onUpdate(1)
  equal(#writes, 0, 'Loading a saved cornering profile must not rewrite it')
  main.setSetting('corneringStrength', 3)
  main.onUpdate(0.51)
  equal(writes[#writes].corneringStrength, 3)
  equal(writes[#writes].corneringWhileDrifting, true)
  equal(writes[#writes].corneringInvert, false)
end)

dofile(F4S_TEST_ROOT .. '/art/feel4speed/dev/test_dynamics.lua')(test, equal, near, truthy)
dofile(F4S_TEST_ROOT .. '/art/feel4speed/dev/test_rpm.lua')(test, equal, truthy)
dofile(F4S_TEST_ROOT .. '/art/feel4speed/dev/test_distance.lua')(test, equal, truthy, near)
dofile(F4S_TEST_ROOT .. '/art/feel4speed/dev/test_drift.lua')(test, equal, near, truthy)
dofile(F4S_TEST_ROOT .. '/art/feel4speed/dev/test_cornering.lua')(test, equal, near, truthy)
dofile(F4S_TEST_ROOT .. '/art/feel4speed/dev/test_roll_geometry.lua')(test, equal, near, truthy)

print(string.format('Feel4Speed contract tests: %d passed, %d failed', passed, failed))
if failed > 0 then error('Feel4Speed contract test failure') end
