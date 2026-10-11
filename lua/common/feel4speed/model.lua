-- Feel4Speed: renderer-independent speed envelope and validated settings.
local M = {}
local defaults = {
  enabled = true, orbitOnly = true, postfxEnabled = true,
  extraFov = 40, startSpeed = 20, fullSpeed = 280,
  curve = 1.45, response = 0.25, vignette = 0.15,
  blur = 0.074, wobble = 0.12, fovLimit = 120,
  activeEnabled = true, activeWhileDrifting = false,
  accelerationFov = 3.5, brakingFov = 3.5,
  accelerationDistance = 0.80, brakingDistance = 0.59,
  accelReference = 13.5, accelDeadzone = 1.4, springTime = 0.34,
  springDamping = 2.00, rpmWobble = 0.03, rpmStart = 1000, rpmFull = 6700,
  corneringEnabled = true, corneringStrength = 1.5, corneringLimit = 6,
  corneringDeadzone = 0.08, corneringResponse = 0.18, corneringWhileDrifting = false,
  corneringInvert = true
}
local ranges = {
  extraFov = {0, 60}, startSpeed = {0, 150}, fullSpeed = {40, 400},
  curve = {0.5, 3}, response = {0.05, 2}, vignette = {0, 0.8},
  blur = {0, 0.1}, wobble = {0, 1}, fovLimit = {80, 140},
  accelerationFov = {0, 20}, brakingFov = {0, 20},
  accelerationDistance = {0, 1}, brakingDistance = {0, 1},
  accelReference = {1, 20}, accelDeadzone = {0, 3},
  springTime = {0.08, 1.5}, springDamping = {0.3, 2},
  rpmWobble = {0, 1}, rpmStart = {0, 10000}, rpmFull = {1000, 20000},
  corneringStrength = {0, 6}, corneringLimit = {0, 15},
  corneringDeadzone = {0, 1}, corneringResponse = {0.05, 1}
}
local presets = {
  balanced = {extraFov = 24, vignette = 0.28, blur = 0.025, wobble = 0.18,
    startSpeed = 25, fullSpeed = 200, curve = 1.15, response = 0.35},
  intense = {extraFov = 42, vignette = 0.45, blur = 0.055, wobble = 0.38,
    startSpeed = 20, fullSpeed = 180, curve = 0.95, response = 0.25},
  clean = {extraFov = 30, vignette = 0, blur = 0, wobble = 0,
    activeEnabled = false, rpmWobble = 0, corneringEnabled = false,
    startSpeed = 25, fullSpeed = 200, curve = 1.15, response = 0.35}
}
function M.finite(v)
  return type(v) == 'number' and v == v and v > -math.huge and v < math.huge
end
function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function M.copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end
function M.defaults() return M.copy(defaults) end
function M.validate(input)
  local out = M.defaults()
  if type(input) ~= 'table' then return out end
  for k, d in pairs(defaults) do
    local v = input[k]
    if type(d) == 'boolean' then
      if type(v) == 'boolean' then out[k] = v end
    elseif M.finite(v) then
      out[k] = M.clamp(v, ranges[k][1], ranges[k][2])
    end
  end
  out.fullSpeed = math.max(out.fullSpeed, out.startSpeed + 5)
  out.rpmFull = math.max(out.rpmFull, out.rpmStart + 100)
  out.accelDeadzone = math.min(out.accelDeadzone, out.accelReference - 0.1)
  return out
end
function M.withSetting(cfg, key, value)
  if defaults[key] == nil then return nil, 'Unknown setting' end
  if type(value) ~= type(defaults[key]) or
    (type(value) == 'number' and not M.finite(value)) then
    return nil, 'Invalid setting value'
  end
  local out = M.copy(cfg)
  out[key] = value
  return M.validate(out)
end
function M.preset(cfg, name)
  if name == 'standard' then
    local out = M.defaults()
    -- Apply the complete tested tune without silently changing the master switch.
    out.enabled = cfg.enabled
    return out
  end
  if not presets[name] then return nil end
  local out = M.copy(cfg)
  for k, v in pairs(presets[name]) do out[k] = v end
  return M.validate(out)
end
function M.envelope(speedKph, cfg)
  if not M.finite(speedKph) then return 0 end
  local t = M.clamp((speedKph - cfg.startSpeed) /
    math.max(5, cfg.fullSpeed - cfg.startSpeed), 0, 1)
  -- Smooth endpoints prevent a step when crossing either speed threshold.
  local smooth = t * t * (3 - 2 * t)
  return smooth ^ cfg.curve
end
function M.smooth(current, target, dt, response)
  if not M.finite(dt) or dt <= 0 then return current end
  return target + (current - target) * math.exp(-math.min(dt, 0.25) / response)
end
function M.fov(base, strength, cfg)
  if not M.finite(base) then return nil, 0 end
  local extra = cfg.extraFov * M.clamp(strength, 0, 1)
  -- A limit never narrows an already wider native camera.
  extra = math.min(extra, math.max(0, cfg.fovLimit - base))
  return base + extra, extra
end
function M.wobble(phase, strength, cfg)
  local amplitude = cfg.wobble * M.clamp(strength, 0, 1) * math.pi / 180
  -- Continuous mixed frequencies; no frame-dependent random jitter.
  local pitch = amplitude * (0.70 * math.sin(phase * 17.3) + 0.30 * math.sin(phase * 29.1))
  local yaw = amplitude * (0.65 * math.sin(phase * 13.7 + 1.4) + 0.35 * math.sin(phase * 23.9))
  local roll = amplitude * 0.65 * math.sin(phase * 11.3 + 0.4)
  return pitch, yaw, roll
end
function M.rpmEnvelope(rpm, cfg)
  if not M.finite(rpm) then return 0 end
  local t = M.clamp((rpm - cfg.rpmStart) / math.max(100, cfg.rpmFull - cfg.rpmStart), 0, 1)
  return t * t * (3 - 2 * t)
end
function M.rpmWobble(phase, strength, cfg)
  local a = cfg.rpmWobble * M.clamp(strength, 0, 1) * math.pi / 180
  -- Stylized engine vibration. Integer harmonics keep a wrapped phase continuous.
  return a * (0.5 * math.sin(phase) + 0.2 * math.sin(2 * phase)),
    a * (0.35 * math.sin(phase + 0.6) + 0.25 * math.sin(2 * phase)),
    a * 0.55 * math.sin(phase + 0.3)
end
return M
