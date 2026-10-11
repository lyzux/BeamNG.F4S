-- Feel4Speed: renderer-independent horizontal drift detection and active blend.
-- World vectors use x/y as the ground plane and z as vertical; speed is m/s.
local M = {}
local abs, sqrt, atan, exp = math.abs, math.sqrt, math.atan, math.exp
local function finite(v)
  return type(v) == 'number' and v == v and v > -math.huge and v < math.huge
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function result(state)
  return {drifting = state.drifting, slipAngle = state.slipAngle,
    blend = state.blend, rollBlend = state.rollBlend, available = state.available}
end

function M.reset(state)
  state.drifting, state.available = false, false
  state.slipAngle, state.enterTime, state.exitTime = 0, 0, 0
  state.blend, state.rollBlend = 1, 1
  state.lastX, state.lastY = nil, nil
  return state
end
function M.new() return M.reset({}) end

local function vector(value)
  -- BeamNG vectors can be userdata/cdata; a failed field read must not escape.
  local ok, x, y, z = pcall(function() return value.x, value.y, value.z end)
  if not ok or not finite(x) or not finite(y) or not finite(z) then return nil end
  return x, y, z
end
local function horizontal(x, y)
  local scale = math.max(abs(x), abs(y))
  if scale < 1e-6 then return nil end
  local sx, sy = x / scale, y / scale
  local normal = sqrt(sx * sx + sy * sy)
  local length = scale * normal
  if not finite(length) then return nil end
  return sx / normal, sy / normal, length
end
local function blend(state, field, target, dt)
  if dt <= 0 then return end
  local response = target == 0 and 0.18 or 0.40
  state[field] = clamp(target + (state[field] - target) * exp(-dt / response), 0, 1)
end
local function target(drifting, activeWhileDrifting)
  return drifting and activeWhileDrifting ~= true and 0 or 1
end
local function unavailable(state, dt, x, y)
  state.drifting, state.available = false, false
  state.slipAngle, state.enterTime, state.exitTime = 0, 0, 0
  state.lastX, state.lastY = x, y
  -- Restore the active cues gently even when the timing sample itself is bad.
  local recovery = finite(dt) and dt > 0 and math.min(dt, 0.05) or 1 / 60
  blend(state, 'blend', 1, recovery)
  blend(state, 'rollBlend', 1, recovery)
  return result(state)
end

function M.step(state, velocityXYZ, forwardXYZ, dtSim, activeWhileDrifting, corneringWhileDrifting)
  -- Pausing holds both the detector and its currently applied blend.
  if dtSim == 0 then return result(state) end
  if not finite(dtSim) or dtSim < 0 or dtSim >= 0.25 then
    return unavailable(state, dtSim)
  end
  local vx, vy = vector(velocityXYZ)
  local fx, fy = vector(forwardXYZ)
  if vx == nil or fx == nil then return unavailable(state, dtSim) end
  local nx, ny, speed = horizontal(vx, vy)
  local ax, ay = horizontal(fx, fy)
  if nx == nil or ax == nil or speed > 400 then return unavailable(state, dtSim) end
  if state.lastX ~= nil then
    local dx, dy = vx - state.lastX, vy - state.lastY
    if dx * dx + dy * dy > 20 * 20 then
      return unavailable(state, dtSim, vx, vy)
    end
  end
  state.lastX, state.lastY = vx, vy
  state.available = true
  local dot, cross = abs(nx * ax + ny * ay), abs(nx * ay - ny * ax)
  -- Absolute dot selects the nearer forward/reverse axis. atan of the ratio
  -- avoids a LuaJIT-specific atan2 dependency and protects the 90-degree case.
  state.slipAngle = dot < 1e-12 and 90 or atan(cross / dot) * 180 / math.pi
  local speedKph = speed * 3.6
  local wasDrifting = state.drifting
  local transitionTime = nil
  if not wasDrifting then
    state.exitTime = 0
    if speedKph >= 20 - 1e-9 and state.slipAngle >= 12 - 1e-9 then
      local previous = state.enterTime
      state.enterTime = previous + dtSim
      if state.enterTime + 1e-12 >= 0.10 then
        state.drifting = true
        state.enterTime = 0
        transitionTime = clamp(0.10 - previous, 0, dtSim)
      end
    else state.enterTime = 0 end
  else
    state.enterTime = 0
    if speedKph <= 15 + 1e-9 or state.slipAngle <= 8 + 1e-9 then
      local previous = state.exitTime
      state.exitTime = previous + dtSim
      if state.exitTime + 1e-12 >= 0.30 then
        state.drifting = false
        state.exitTime = 0
        transitionTime = clamp(0.30 - previous, 0, dtSim)
      end
    else state.exitTime = 0 end
  end
  if transitionTime ~= nil then
    blend(state, 'blend', target(wasDrifting, activeWhileDrifting), transitionTime)
    blend(state, 'blend', target(state.drifting, activeWhileDrifting), dtSim - transitionTime)
    blend(state, 'rollBlend', target(wasDrifting, corneringWhileDrifting), transitionTime)
    blend(state, 'rollBlend', target(state.drifting, corneringWhileDrifting), dtSim - transitionTime)
  else
    blend(state, 'blend', target(state.drifting, activeWhileDrifting), dtSim)
    blend(state, 'rollBlend', target(state.drifting, corneringWhileDrifting), dtSim)
  end
  return result(state)
end

return M
