-- Feel4Speed: true lateral acceleration and renderer-independent camera lean.
-- World velocity is m/s. Positive G acts to vehicle-left; positive roll degrees
-- mean the camera leans right. The renderer performs its quaternion conversion.
local M = {}
local exp, abs, sqrt = math.exp, math.abs, math.sqrt
local gravity = 9.80665
local function finite(v)
  return type(v) == 'number' and v == v and v > -math.huge and v < math.huge
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function vector(value)
  local ok, x, y, z = pcall(function() return value.x, value.y, value.z end)
  if not ok or not finite(x) or not finite(y) or not finite(z) then return nil end
  return x, y, z
end
local function magnitude(x, y, z)
  local scale = math.max(abs(x), abs(y), abs(z))
  if scale == 0 then return 0 end
  return scale * sqrt((x / scale)^2 + (y / scale)^2 + (z / scale)^2)
end
local function setting(cfg, key, fallback, lo, hi)
  local value = type(cfg) == 'table' and cfg[key] or nil
  return finite(value) and clamp(value, lo, hi) or fallback
end
local function result(state)
  return {lateralG = state.lateralG, roll = state.roll,
    available = state.available, status = state.status}
end
local function baseline(state, x, y, z)
  state.lastX, state.lastY, state.lastZ = x, y, z
end
function M.reset(state)
  baseline(state)
  state.lateralG, state.roll = 0, 0
  state.available, state.status = false, 'priming'
  return state
end
function M.new() return M.reset({}) end

function M.rebase(state, velocityXYZ)
  local x, y, z = vector(velocityXYZ)
  baseline(state, x, y, z)
  state.lateralG = 0
  state.available = false
  state.status = x == nil and 'unavailable' or 'priming'
  -- The visible lean remains held; the next sample releases it smoothly.
  return state
end

local function release(state, dt, cfg, status)
  local recovery = finite(dt) and dt > 0 and math.min(dt, 0.05) or 1 / 60
  state.lateralG = state.lateralG * exp(-recovery / 0.06)
  local limit = setting(cfg, 'corneringLimit', 6, 0, 15)
  state.roll = clamp(state.roll * exp(-recovery /
    setting(cfg, 'corneringResponse', 0.18, 0.05, 1)), -limit, limit)
  state.available, state.status = false, status
  return result(state)
end
local function unavailable(state, dt, cfg)
  baseline(state)
  return release(state, dt, cfg, 'unavailable')
end

function M.step(state, velocityXYZ, forwardXYZ, dtSim, cfg)
  if dtSim == 0 then return result(state) end
  if type(cfg) ~= 'table' or cfg.corneringEnabled ~= true then
    M.reset(state)
    state.status = 'disabled'
    return result(state)
  end
  if not finite(dtSim) or dtSim < 0 or dtSim >= 0.25 then
    return unavailable(state, dtSim, cfg)
  end
  local x, y, z = vector(velocityXYZ)
  local fx, fy = vector(forwardXYZ)
  if x == nil or fx == nil then return unavailable(state, dtSim, cfg) end
  local forwardScale = math.max(abs(fx), abs(fy))
  if forwardScale < 1e-6 then return unavailable(state, dtSim, cfg) end
  local sx, sy = fx / forwardScale, fy / forwardScale
  local forwardLength = sqrt(sx * sx + sy * sy)
  -- Left=(-forward.y, forward.x); z never participates in the lean projection.
  local leftX, leftY = -sy / forwardLength, sx / forwardLength
  if state.lastX == nil then
    baseline(state, x, y, z)
    return release(state, dtSim, cfg, 'priming')
  end
  local dx, dy, dz = x - state.lastX, y - state.lastY, z - state.lastZ
  if not finite(dx) or not finite(dy) or not finite(dz) then
    return unavailable(state, dtSim, cfg)
  end
  local delta = magnitude(dx, dy, dz)
  if not finite(delta) or delta > 12 or delta / dtSim > 100 then
    return unavailable(state, dtSim, cfg)
  end
  baseline(state, x, y, z)
  local lateral = (dx * leftX + dy * leftY) / dtSim / gravity
  if not finite(lateral) then return unavailable(state, dtSim, cfg) end
  state.lateralG = lateral + (state.lateralG - lateral) * exp(-dtSim / 0.06)
  local effective = math.max(0, abs(state.lateralG) -
    setting(cfg, 'corneringDeadzone', 0.08, 0, 1))
  local limit = setting(cfg, 'corneringLimit', 6, 0, 15)
  local target = math.min(limit, effective *
    setting(cfg, 'corneringStrength', 1.5, 0, 6))
  if state.lateralG < 0 then target = -target end
  -- Inward lean is the default. Invert the target before smoothing so changing
  -- direction under load crosses neutral continuously; G keeps its physical sign.
  if cfg.corneringInvert ~= false then target = -target end
  local response = setting(cfg, 'corneringResponse', 0.18, 0.05, 1)
  state.roll = clamp(target + (state.roll - target) * exp(-dtSim / response), -limit, limit)
  state.available, state.status = true, 'active'
  return result(state)
end

return M
