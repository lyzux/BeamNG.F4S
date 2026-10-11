-- Feel4Speed: renderer-independent longitudinal acceleration feedback.
-- Speeds are scalar world/air velocity magnitudes in m/s, never wheel speed.
-- Sample and step once per simulation frame; reset at vehicle/camera transitions.
local M = {}
local abs, exp, sqrt, sin, cos = math.abs, math.exp, math.sqrt, math.sin, math.cos

local function finite(v)
  return type(v) == 'number' and v == v and v > -math.huge and v < math.huge
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function setting(cfg, key, fallback, lo, hi)
  local value = type(cfg) == 'table' and cfg[key] or nil
  return finite(value) and clamp(value, lo, hi) or fallback
end
local function result(state)
  return {acceleration = state.acceleration, demand = state.demand,
    kick = state.kick, distance = state.distance}
end

function M.reset(state, speedMs)
  state.speed = finite(speedMs) and speedMs >= 0 and speedMs <= 400 and speedMs or nil
  state.acceleration, state.demand, state.kick = 0, 0, 0
  state.distance, state.distanceVelocity = 0, 0
  state.sampleReady = false
  return state
end

function M.new() return M.reset({}) end

function M.rebase(state, speedMs)
  -- Resume from a frozen visual state without differentiating paused time or
  -- snapping the camera back to its passive position. The held offsets release
  -- normally when the next valid sample reports little or no acceleration.
  if not finite(speedMs) or speedMs < 0 or speedMs > 400 then
    return M.reset(state)
  end
  state.speed = speedMs
  state.acceleration, state.demand = 0, 0
  state.sampleReady = false
  return state
end

function M.sample(state, speedMs, dt)
  -- Pause, missing telemetry and long frame gaps re-prime the derivative. A
  -- resumed sample therefore cannot turn the entire missing interval into a kick.
  if not finite(speedMs) or speedMs < 0 or speedMs > 400 or
    not finite(dt) or dt <= 0 or dt >= 0.25 then
    M.reset(state)
    return 0
  end
  if state.speed == nil then
    M.reset(state, speedMs)
    state.sampleReady = true
    return 0
  end
  local delta = speedMs - state.speed
  local acceleration = delta / dt
  state.speed = speedMs
  -- Ordinary hard braking and downshifts remain valid. Discontinuous teleport,
  -- respawn and crash samples must not send the camera spring flying.
  if abs(delta) > 12 or abs(acceleration) > 50 then
    M.reset(state, speedMs)
    state.sampleReady = true
    return 0
  end
  -- Filtering the signed scalar derivative suppresses sample noise without
  -- creating a false deceleration while cornering at constant speed.
  state.acceleration = acceleration + (state.acceleration - acceleration) * exp(-dt / 0.06)
  state.sampleReady = true
  return state.acceleration
end

local function spring(position, velocity, target, dt, response, damping)
  -- Exact constant-target second-order solution, stable at every frame rate.
  -- response tunes approximate settling time; damping controls spring rebound.
  local omega = 4 / response
  local offset = position - target
  if abs(damping - 1) < 0.0001 then
    local decay = exp(-omega * dt)
    local combined = velocity + omega * offset
    return target + decay * (offset + combined * dt),
      decay * (velocity - omega * combined * dt)
  elseif damping < 1 then
    local damped = omega * sqrt(1 - damping * damping)
    local decay = exp(-damping * omega * dt)
    local c, s = cos(damped * dt), sin(damped * dt)
    return target + decay * (offset * c + (velocity + damping * omega * offset) / damped * s),
      decay * (velocity * c - (damping * omega * velocity + omega * omega * offset) / damped * s)
  else
    local separation = sqrt(damping * damping - 1)
    local slow, fast = -omega * (damping - separation), -omega * (damping + separation)
    local a = (velocity - fast * offset) / (slow - fast)
    local b = offset - a
    local slowDecay, fastDecay = exp(slow * dt), exp(fast * dt)
    return target + a * slowDecay + b * fastDecay,
      slow * a * slowDecay + fast * b * fastDecay
  end
end

function M.step(state, dt, cfg)
  if not finite(dt) or dt <= 0 or dt >= 0.25 or not state.sampleReady then
    -- No valid fresh sample means no active cue, including stale spring output.
    M.reset(state)
    return result(state)
  end
  state.sampleReady = false
  if type(cfg) ~= 'table' or cfg.activeEnabled ~= true then
    local speed = state.speed
    M.reset(state, speed)
    return result(state)
  end

  local reference = setting(cfg, 'accelReference', 13.5, 1, 20)
  local deadzone = math.min(setting(cfg, 'accelDeadzone', 1.4, 0, 3), reference - 0.1)
  local magnitude = clamp((abs(state.acceleration) - deadzone) / (reference - deadzone), 0, 1)
  local demand = state.acceleration < 0 and -magnitude or magnitude
  state.demand = demand

  local accelerating = demand >= 0
  local kickTarget = demand * setting(cfg,
    accelerating and 'accelerationFov' or 'brakingFov', 3.5, 0, 20)
  local distanceTarget = demand * setting(cfg,
    accelerating and 'accelerationDistance' or 'brakingDistance', accelerating and 0.80 or 0.59, 0, 1)

  -- Immediate braking reversals use the short attack, rather than waiting for
  -- the old acceleration cue to release. Low acceleration returns to baseline.
  local isAttack = abs(kickTarget) > abs(state.kick) or kickTarget * state.kick < 0
  local kickTime = isAttack and 0.04 or 0.25
  state.kick = kickTarget + (state.kick - kickTarget) * exp(-dt / kickTime)
  state.distance, state.distanceVelocity = spring(state.distance, state.distanceVelocity,
    distanceTarget, dt, setting(cfg, 'springTime', 0.34, 0.08, 1.5),
    setting(cfg, 'springDamping', 2.00, 0.3, 2))
  -- A low-damping user tune can overshoot naturally, but remains bounded.
  state.distance = clamp(state.distance, -2.5, 2.5)
  return result(state)
end

return M
