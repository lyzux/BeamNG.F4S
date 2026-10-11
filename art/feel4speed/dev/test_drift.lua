return function(test, equal, near, truthy)
  local drift = require('feel4speed/drift')
  local forward = {x = 1, y = 0, z = 0}
  local function velocity(speedKph, degrees)
    local radians = degrees * math.pi / 180
    return {x = speedKph / 3.6 * math.cos(radians),
      y = speedKph / 3.6 * math.sin(radians), z = 0}
  end
  local function tick(state, speedKph, degrees, dt, allow, allowCornering)
    return drift.step(state, velocity(speedKph, degrees), forward, dt, allow, allowCornering)
  end
  local function hold(state, speedKph, degrees, duration, fps, allow, allowCornering)
    local out
    for _ = 1, math.floor(duration * fps + 0.5) do
      out = tick(state, speedKph, degrees, 1 / fps, allow, allowCornering)
    end
    return out
  end

  test('drift detector keeps straight forward and reverse driving neutral', function()
    for _, degrees in ipairs({0, 180, -180}) do
      local state = drift.new()
      local out = hold(state, 100, degrees, 1, 60)
      equal(out.available, true); equal(out.drifting, false)
      near(out.slipAngle, 0, 1e-10); equal(out.blend, 1)
    end
  end)

  test('sustained horizontal side slip suppresses active feedback after entry dwell', function()
    local state = drift.new()
    local out = hold(state, 60, 30, 0.05, 60)
    equal(out.drifting, false); equal(out.blend, 1)
    out = hold(state, 60, 30, 0.05, 60)
    equal(out.drifting, true); near(out.slipAngle, 30, 1e-10)
    near(out.blend, 1, 1e-10)
    out = hold(state, 60, 30, 0.18, 100)
    near(out.blend, math.exp(-1), 1e-10)
  end)

  test('speed thresholds and short slips do not trigger a drift', function()
    local state = drift.new()
    local out = hold(state, 19, 90, 1, 60)
    equal(out.drifting, false); equal(out.blend, 1)
    out = hold(state, 30, 40, 0.08, 100)
    equal(out.drifting, false)
    out = tick(state, 30, 0, 0.01)
    equal(out.drifting, false)
    out = hold(state, 30, 40, 0.08, 100)
    equal(out.drifting, false); equal(out.blend, 1)
  end)

  test('drift hysteresis rejects angle chatter and holds briefly through straightening', function()
    local state = drift.new()
    local out = hold(state, 60, 30, 0.5, 100)
    equal(out.drifting, true)
    for index = 1, 50 do
      out = tick(state, 60, index % 2 == 0 and 9 or 11, 0.01)
      equal(out.drifting, true)
    end
    out = hold(state, 60, 0, 0.29, 100)
    equal(out.drifting, true)
    out = tick(state, 60, 0, 0.01)
    equal(out.drifting, false)
    local initial = out.blend
    out = hold(state, 60, 0, 0.4, 100)
    near(out.blend, 1 + (initial - 1) * math.exp(-1), 1e-10)
  end)

  test('drift low-speed exit uses its own hysteresis and exit dwell', function()
    local state = drift.new()
    hold(state, 25, 45, 0.5, 100)
    local out = hold(state, 17, 45, 0.5, 100)
    equal(out.drifting, true)
    out = hold(state, 14, 45, 0.29, 100)
    equal(out.drifting, true)
    out = tick(state, 14, 45, 0.01)
    equal(out.drifting, false)
  end)

  test('drift exact entry and exit thresholds tolerate projection rounding', function()
    local state = drift.new()
    local out = hold(state, 20, 12, 0.10, 100)
    equal(out.drifting, true)
    out = hold(state, 20, 8, 0.30, 100)
    equal(out.drifting, false)
    out = hold(state, 20, 12, 0.10, 100)
    equal(out.drifting, true)
    out = hold(state, 15, 12, 0.30, 100)
    equal(out.drifting, false)
  end)

  test('drift dwell and blend agree at 30 60 and 144 FPS', function()
    local outputs = {}
    for _, fps in ipairs({30, 60, 144}) do
      local state = drift.new()
      local entered = hold(state, 60, 35, 1, fps)
      local exited = hold(state, 60, 0, 1, fps)
      outputs[#outputs + 1] = {entered = entered, exited = exited}
    end
    for index = 2, #outputs do
      equal(outputs[index].entered.drifting, true)
      equal(outputs[index].exited.drifting, false)
      near(outputs[index].entered.blend, outputs[1].entered.blend, 1e-10)
      near(outputs[index].exited.blend, outputs[1].exited.blend, 1e-10)
      near(outputs[index].entered.rollBlend, outputs[1].entered.rollBlend, 1e-10)
      near(outputs[index].exited.rollBlend, outputs[1].exited.rollBlend, 1e-10)
    end
  end)

  test('paused drift feedback holds detector blend and dwell timers', function()
    local state = drift.new()
    local held = hold(state, 60, 35, 0.5, 100)
    local enter, exit = state.enterTime, state.exitTime
    for _ = 1, 100 do
      local out = drift.step(state, nil, nil, 0, true)
      equal(out.drifting, held.drifting); equal(out.available, held.available)
      equal(out.slipAngle, held.slipAngle); equal(out.blend, held.blend)
      equal(out.rollBlend, held.rollBlend)
      equal(state.enterTime, enter); equal(state.exitTime, exit)
    end
  end)

  test('invalid vertical and discontinuous samples clear drift gently', function()
    local cases = {
      {v = nil, f = forward, dt = 0.02},
      {v = {x = 10, y = 0, z = 0/0}, f = forward, dt = 0.02},
      {v = {x = 0, y = 0, z = 10}, f = forward, dt = 0.02},
      {v = velocity(60, 30), f = {x = 0, y = 0, z = 1}, dt = 0.02},
      {v = velocity(60, 30), f = forward, dt = 0/0},
      {v = velocity(60, 30), f = forward, dt = -0.01},
      {v = velocity(60, 30), f = forward, dt = 1},
      {v = velocity(250, 30), f = forward, dt = 0.02},
      {v = setmetatable({}, {__index = function() error('Invalid vector') end}), f = forward, dt = 0.02}
    }
    for _, case in ipairs(cases) do
      local state = drift.new()
      local held = hold(state, 60, 30, 0.5, 100)
      local out = drift.step(state, case.v, case.f, case.dt)
      equal(out.drifting, false); equal(out.available, false)
      truthy(out.blend > held.blend and out.blend < 1,
        'An unavailable detector must ease back, rather than snap')
      truthy(out.rollBlend > held.rollBlend and out.rollBlend < 1)
    end
  end)

  test('active-while-drifting toggle preserves detection and blends its effect', function()
    local state = drift.new()
    local held = hold(state, 60, 40, 0.5, 100)
    local out = tick(state, 60, 40, 0.01, true)
    equal(out.drifting, true)
    truthy(out.blend > held.blend and out.blend < 1)
    out = hold(state, 60, 40, 1, 100, true)
    local allowed = out.blend
    out = tick(state, 60, 40, 0.01, false)
    equal(out.drifting, true)
    truthy(out.blend < allowed and out.blend > 0)
    local neutral = drift.new()
    out = hold(neutral, 60, 40, 0.5, 100, true)
    equal(out.drifting, true); equal(out.blend, 1)
    drift.reset(state)
    equal(state.drifting, false); equal(state.available, false); equal(state.blend, 1)
    equal(state.rollBlend, 1)
  end)

  test('acceleration and cornering drift policies blend independently', function()
    for _, activeAllowed in ipairs({false, true}) do
      for _, cornerAllowed in ipairs({false, true}) do
        local state = drift.new()
        local out = hold(state, 60, 35, 0.5, 100, activeAllowed, cornerAllowed)
        equal(out.drifting, true)
        if activeAllowed then equal(out.blend, 1)
        else truthy(out.blend > 0 and out.blend < 0.2) end
        if cornerAllowed then equal(out.rollBlend, 1)
        else truthy(out.rollBlend > 0 and out.rollBlend < 0.2) end
        local previous = out
        out = tick(state, 60, 35, 0.01, activeAllowed, not cornerAllowed)
        if cornerAllowed then truthy(out.rollBlend < previous.rollBlend)
        else truthy(out.rollBlend > previous.rollBlend) end
        if activeAllowed then equal(out.blend, 1)
        else truthy(out.blend < previous.blend) end
      end
    end
  end)
end
