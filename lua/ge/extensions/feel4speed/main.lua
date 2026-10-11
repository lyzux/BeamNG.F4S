-- Feel4Speed 1.0.0. Own settings and objects only; no stock-file overrides.
local M = {}
local model = require('feel4speed/model')
local dynamics = require('feel4speed/dynamics')
local drift = require('feel4speed/drift')
local cornering = require('feel4speed/cornering')
local rpmSampler = require('ge/extensions/feel4speed/rpm')
local distance = require('ge/extensions/feel4speed/distance')
local postfx = require('ge/extensions/feel4speed/postfx')
local VERSION = '1.0.0'
local SETTINGS_PATH = '/settings/feel4speed.json'
local cfg = model.defaults()
local strength, phase, speedKph = 0, 0, 0
local activeState = dynamics.new()
local activeResult = {acceleration = 0, demand = 0, kick = 0, distance = 0}
local driftState = drift.new()
local driftResult = {drifting = false, slipAngle = 0, blend = 1, rollBlend = 1, available = false}
local corneringState = cornering.new()
local corneringResult = {lateralG = 0, roll = 0, available = false, status = 'idle'}
local rpmStrength, rpmPhase, paused = 0, 0, false
local vehicleId, lastCamera
local heartbeatAge, uiElapsed, saveElapsed = 0, 0, 0
local dirty, suspended, filterSeen = false, false, false
local telemetry = {speedKph = 0, extraFov = 0, strength = 0, active = false, camera = 'none',
  acceleration = 0, kickFov = 0, distanceOffset = 0, rpm = 0, rpmAvailable = false, rpmStrength = 0,
  drifting = false, driftAvailable = false, slipAngle = 0, activeBlend = 1,
  lateralG = 0, corneringRoll = 0, corneringBlend = 1, corneringAvailable = false}
local status = {message = 'Waiting for orbit camera', postfx = 'idle'}

function M.getState()
  return {version = VERSION, settings = model.copy(cfg),
    telemetry = model.copy(telemetry), status = model.copy(status),
    cameraFilterSeen = filterSeen, suspended = suspended}
end
local function tellUI()
  if guihooks and guihooks.trigger then
    guihooks.trigger('Feel4SpeedState', M.getState())
  end
end
local function save()
  if not dirty then return end
  local ok, result = pcall(jsonWriteFile, SETTINGS_PATH, cfg, true)
  if ok and result ~= false then
    dirty = false
    status.saveError = nil
  else
    status.message = 'Settings could not be saved; see console'
    status.saveError = 'Settings are not saved. Check beamng.log and edit again to retry.'
    log('W', 'Feel4Speed', 'Could not save ' .. SETTINGS_PATH)
    -- Retry on the next edit instead of writing/logging every frame.
    dirty = false
  end
end
local function resetFeedback()
  dynamics.reset(activeState)
  activeResult = {acceleration = 0, demand = 0, kick = 0, distance = 0}
  drift.reset(driftState)
  driftResult = {drifting = false, slipAngle = 0, blend = 1, rollBlend = 1, available = false}
  cornering.reset(corneringState)
  corneringResult = {lateralG = 0, roll = 0, available = false, status = 'idle'}
  rpmSampler.reset()
  rpmStrength, rpmPhase, paused = 0, 0, false
  telemetry.acceleration, telemetry.kickFov, telemetry.distanceOffset = 0, 0, 0
  telemetry.rpm, telemetry.rpmAvailable, telemetry.rpmStrength = 0, false, 0
  telemetry.drifting, telemetry.driftAvailable, telemetry.slipAngle, telemetry.activeBlend = false, false, 0, 1
  telemetry.lateralG, telemetry.corneringRoll, telemetry.corneringBlend, telemetry.corneringAvailable = 0, 0, 1, false
  status.rpm, status.distance, status.drift, status.cornering = 'idle', 'idle', 'idle', 'idle'
end
local function stopEffects(message)
  strength, phase, speedKph = 0, 0, 0
  resetFeedback()
  telemetry.active, telemetry.strength, telemetry.extraFov = false, 0, 0
  telemetry.speedKph = 0
  telemetry.fov = nil
  local ok, msg = postfx.set(0, 0)
  status.postfx = msg or (ok and 'idle' or 'unavailable')
  status.message = message or 'Waiting for orbit camera'
end
local function edited()
  dirty, saveElapsed = true, 0
  if not cfg.activeEnabled then
    dynamics.reset(activeState)
    activeResult = {acceleration = 0, demand = 0, kick = 0, distance = 0}
    telemetry.acceleration, telemetry.kickFov, telemetry.distanceOffset = 0, 0, 0
  end
  if cfg.rpmWobble == 0 then
    rpmSampler.reset()
    rpmStrength, rpmPhase = 0, 0
    telemetry.rpm, telemetry.rpmAvailable, telemetry.rpmStrength = 0, false, 0
    status.rpm = 'off'
  end
  if not cfg.corneringEnabled or cfg.corneringStrength == 0 or cfg.corneringLimit == 0 then
    cornering.reset(corneringState)
    corneringResult = {lateralG = 0, roll = 0, available = false, status = 'disabled'}
    telemetry.lateralG, telemetry.corneringRoll, telemetry.corneringAvailable = 0, 0, false
    status.cornering = 'disabled'
  end
  if not cfg.enabled then stopEffects('Disabled') end
  tellUI()
end
function M.requestState() tellUI() end
function M.receiveRpm(id, token, value) return rpmSampler.receive(id, token, value) end
function M.setSetting(key, value)
  local nextCfg, err = model.withSetting(cfg, key, value)
  if not nextCfg then return false, err end
  cfg = nextCfg
  edited()
  return true
end
function M.setEnabled(value) return M.setSetting('enabled', value) end
function M.toggle() return M.setEnabled(not cfg.enabled) end
function M.applyPreset(name)
  local nextCfg = model.preset(cfg, name)
  if not nextCfg then return false end
  cfg = nextCfg
  resetFeedback()
  edited()
  return true
end
function M.resetDefaults()
  cfg = model.defaults()
  resetFeedback()
  edited()
end
function M.suspend(reason)
  suspended = true
  stopEffects('Camera integration error; see console')
  log('E', 'Feel4Speed', tostring(reason))
  tellUI()
end

function M.processCamera(data)
  heartbeatAge = 0
  filterSeen = true
  if type(data) ~= 'table' or type(data.res) ~= 'table' then
    stopEffects('Camera data unavailable')
    return
  end
  local camera = core_camera and core_camera.getActiveCamName and core_camera.getActiveCamName(0)
  telemetry.camera = camera or 'none'
  local veh = data.veh
  local id = data.vid or (veh and veh:getId())
  local allowed = camera == 'orbit'
  if not cfg.orbitOnly then
    allowed = camera == 'orbit' or camera == 'chase' or camera == 'driver'
  end
  if suspended or not cfg.enabled or not veh or not allowed or
    data.openxrSessionRunning or (editor and editor.active) then
    local message = not cfg.enabled and 'Disabled' or 'Inactive in this camera'
    if data.openxrSessionRunning then message = 'Inactive in VR' end
    if editor and editor.active then message = 'Inactive in World Editor' end
    if suspended then message = 'Camera integration error; see console' end
    stopEffects(message)
    vehicleId, lastCamera = id, camera
    return
  end
  if vehicleId ~= id or lastCamera ~= camera or data.teleported then
    strength, phase, speedKph = 0, 0, 0
    resetFeedback()
  end
  vehicleId, lastCamera = id, camera
  local dtSim = model.finite(data.dtSim) and math.max(0, data.dtSim) or 0
  local dtReal = model.finite(data.dtReal) and math.max(0, data.dtReal) or dtSim
  -- Hold the image while paused. Position-derived camera velocity is zero
  -- during pause and must not collapse the speed envelope.
  if dtSim > 0 then
    local okVelocity, measured = pcall(function() return data.vel and data.vel:length() end)
    local validSpeed = okVelocity and model.finite(measured) and measured >= 0
    speedKph = validSpeed and measured * 3.6 or 0
    strength = model.smooth(strength, model.envelope(speedKph, cfg), dtReal, cfg.response)
    phase = (phase + dtSim) % 1000
    if paused then dynamics.rebase(activeState, validSpeed and measured or nil) end
    dynamics.sample(activeState, validSpeed and measured or nil, dtSim)
    activeResult = dynamics.step(activeState, dtSim, cfg)
    -- Vehicle heading is independent of orbit-camera rotation. Missing heading
    -- softly restores the active blend instead of suspending the camera filter.
    local okHeading, heading = pcall(function() return veh:getDirectionVector() end)
    driftResult = drift.step(driftState, validSpeed and data.vel or nil,
      okHeading and heading or nil, dtSim, cfg.activeWhileDrifting, cfg.corneringWhileDrifting)
    if paused then cornering.rebase(corneringState, validSpeed and data.vel or nil) end
    corneringResult = cornering.step(corneringState, validSpeed and data.vel or nil,
      okHeading and heading or nil, dtSim, cfg)
    status.cornering = corneringResult.status
    status.drift = not driftResult.available and 'unavailable' or
      (driftResult.drifting and (cfg.activeWhileDrifting and 'active during drift' or 'fading to passive') or 'ready')
    if cfg.rpmWobble > 0 then
      local rpm, available, rpmStatus = rpmSampler.step(veh, id, dtReal)
      local target = available and model.rpmEnvelope(rpm, cfg) or 0
      rpmStrength = model.smooth(rpmStrength, target, dtSim, 0.10)
      rpmPhase = (rpmPhase + dtSim * 2 * math.pi * (5 + 8 * rpmStrength)) % (2 * math.pi)
      telemetry.rpm, telemetry.rpmAvailable, status.rpm = rpm, available, rpmStatus
    else
      rpmStrength = 0
      telemetry.rpm, telemetry.rpmAvailable, status.rpm = 0, false, 'off'
    end
    paused = false
  else
    paused = true
  end
  local passiveFov, extra = model.fov(data.res.fov, strength, cfg)
  if not passiveFov then stopEffects('Camera FOV unavailable'); return end
  local kick = activeResult.kick
  if kick >= 0 then
    kick = math.min(kick, math.max(0, cfg.fovLimit - passiveFov))
  else
    -- Braking deliberately narrows the passive result transiently; it releases
    -- back to that result at constant speed. Preserve unusually low native FOV.
    kick = math.max(kick, math.min(20, data.res.fov) - passiveFov)
  end
  -- Blend the cue that can actually be displayed. Applying the cap first keeps
  -- a drift fade continuous from its first frame even near the FOV limits.
  kick = kick * driftResult.blend
  local fov = passiveFov + kick
  local rotation = data.res.rot
  local appliedRoll = 0
  if data.res.rot and quatFromEuler and
    ((cfg.wobble > 0 and strength > 0) or (cfg.rpmWobble > 0 and rpmStrength > 0)) then
    local pitch, yaw, roll = model.wobble(phase, strength, cfg)
    local ep, ey, er = model.rpmWobble(rpmPhase, rpmStrength, cfg)
    -- BeamNG cameras face local Y: X = pitch, Y = roll, Z = yaw.
    rotation = quatFromEuler(pitch + ep, roll + er, yaw + ey) * data.res.rot
  end
  local requestedRoll = model.clamp(corneringResult.roll, -cfg.corneringLimit,
    cfg.corneringLimit) * driftResult.rollBlend
  if math.abs(requestedRoll) > 1e-8 then
    if rotation and quatFromEuler then
      -- BeamNG's quaternion vector action uses inverse rotations. Premultiplying
      -- negative local-Y roll makes positive reported lean tilt camera-up right,
      -- while retaining the viewing axis at every orbit yaw/pitch.
      local okRoll, rolled = pcall(function()
        return quatFromEuler(0, -math.rad(requestedRoll), 0) * rotation
      end)
      if okRoll and rolled then rotation, appliedRoll = rolled, requestedRoll
      else status.cornering = 'rotation unavailable' end
    else status.cornering = 'rotation unavailable' end
  end
  data.res.fov = fov
  if rotation then data.res.rot = rotation end
  local appliedDistance, distanceStatus = distance.apply(data, camera, activeResult.distance * driftResult.blend)
  status.distance = distanceStatus
  local v = cfg.postfxEnabled and cfg.vignette * strength or 0
  local b = cfg.postfxEnabled and cfg.blur * strength or 0
  local ok, message = postfx.set(v, b)
  status.postfx = message or (ok and 'ready' or 'unavailable')
  status.message = 'Active'
  if not ok then status.message = 'Camera active; visual effects unavailable' end
  telemetry.speedKph, telemetry.extraFov, telemetry.fov = speedKph, extra, fov
  telemetry.strength, telemetry.active = strength, true
  telemetry.acceleration, telemetry.kickFov = activeResult.acceleration, kick
  telemetry.distanceOffset, telemetry.rpmStrength = appliedDistance, rpmStrength
  telemetry.drifting, telemetry.driftAvailable = driftResult.drifting, driftResult.available
  telemetry.slipAngle, telemetry.activeBlend = driftResult.slipAngle, driftResult.blend
  telemetry.lateralG, telemetry.corneringAvailable = corneringResult.lateralG, corneringResult.available
  telemetry.corneringRoll, telemetry.corneringBlend = appliedRoll, driftResult.rollBlend
end

function M.onUpdate(dtReal)
  local dt = model.finite(dtReal) and math.max(0, dtReal) or 0
  heartbeatAge, uiElapsed = heartbeatAge + dt, uiElapsed + dt
  if heartbeatAge > 0.5 and telemetry.active then
    stopEffects('Camera filter inactive; restart game if newly installed')
  end
  if not filterSeen and heartbeatAge > 2 and cfg.enabled then
    status.message = 'Camera filter not detected; restart BeamNG if newly installed'
  end
  if dirty then
    saveElapsed = saveElapsed + dt
    if saveElapsed >= 0.5 then save() end
  end
  if uiElapsed >= 0.1 then uiElapsed = 0; tellUI() end
end
function M.onExtensionLoaded()
  local ok, stored = pcall(jsonReadFile, SETTINGS_PATH)
  if ok then cfg = model.validate(stored) end
  -- Script mods remain active independently of adding/removing the UI app.
  if setExtensionUnloadMode then setExtensionUnloadMode('feel4speed_main', 'manual') end
  heartbeatAge = 0
  tellUI()
end
function M.onClientEndMission()
  stopEffects('Waiting for orbit camera')
  postfx.shutdown()
  telemetry.camera = 'none'
  telemetry.fov = nil
  vehicleId, lastCamera = nil, nil
  save()
end
function M.onVehicleSwitched() stopEffects('Waiting for orbit camera'); vehicleId = nil end
function M.onExtensionUnloaded() save(); rpmSampler.reset(); postfx.shutdown() end
function M.onSerialize()
  save()
  -- Registered renderer objects can outlive a Lua VM reload. Release them
  -- before losing their handles so the new module can register clean names.
  postfx.shutdown()
  resetFeedback()
  return {settings = model.copy(cfg)}
end
function M.onDeserialized(state)
  if type(state) == 'table' then cfg = model.validate(state.settings) end
  stopEffects('Waiting for orbit camera')
  vehicleId, lastCamera = nil, nil
  suspended = false
  tellUI()
end
return M
