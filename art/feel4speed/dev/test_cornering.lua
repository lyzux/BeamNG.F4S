return function(test, equal, near, truthy)
  local cornering = require('feel4speed/cornering')
  local gravity = 9.80665
  local forward = {x = 1, y = 0, z = 0}
  local cfg = {corneringEnabled = true, corneringInvert = false, corneringStrength = 1.5,
    corneringLimit = 6, corneringDeadzone = 0.08, corneringResponse = 0.18}
  local function copy(settings)
    local out = {}
    for key, value in pairs(settings) do out[key] = value end
    return out
  end
  local function vector(x, y, z) return {x = x, y = y, z = z or 0} end
  local function ramp(state, g, seconds, fps, settings, axis)
    local velocity = vector(20, 0)
    cornering.step(state, velocity, forward, 1 / fps, settings or cfg)
    local out
    for index = 1, math.floor(seconds * fps + 0.5) do
      local change = g * gravity * index / fps
      velocity = axis == 'x' and vector(20 + change, 0) or
        axis == 'z' and vector(20, 0, change) or vector(20, change)
      out = cornering.step(state, velocity, forward, 1 / fps, settings or cfg)
    end
    return out, velocity
  end

  test('left and right lateral two-G forces produce equal opposite camera lean', function()
    for _, g in ipairs({2, -2}) do
      local out = ramp(cornering.new(), g, 2, 60)
      equal(out.available, true); equal(out.status, 'active')
      near(out.lateralG, g, 1e-9)
      near(out.roll, (g > 0 and 1 or -1) * 2.88, 0.0001)
    end
  end)

  test('default inward cornering leans with the turn while preserving signed G', function()
    local inward = copy(cfg)
    inward.corneringInvert = nil
    for _, g in ipairs({2, -2}) do
      local out = ramp(cornering.new(), g, 2, 60, inward)
      near(out.lateralG, g, 1e-9)
      near(out.roll, (g > 0 and -1 or 1) * 2.88, 0.0001)
      truthy(math.abs(out.roll) <= inward.corneringLimit)
      inward.corneringInvert = true
      local explicit = ramp(cornering.new(), g, 2, 60, inward)
      near(explicit.lateralG, out.lateralG, 1e-9)
      near(explicit.roll, out.roll, 1e-9)
      inward.corneringInvert = nil
    end
  end)

  test('invalid inversion values default inward and explicit false retains outward lean', function()
    for _, value in ipairs({'false', 0, {}}) do
      local inward = copy(cfg)
      inward.corneringInvert = value
      local out = ramp(cornering.new(), 2, 2, 60, inward)
      near(out.lateralG, 2, 1e-9)
      truthy(out.roll < -2.8)
    end
    local outward = copy(cfg)
    outward.corneringInvert, outward.corneringStrength, outward.corneringLimit = false, 6, 1
    for _, g in ipairs({2, -2}) do
      local out = ramp(cornering.new(), g, 2, 60, outward)
      near(out.lateralG, g, 1e-9)
      near(out.roll, g > 0 and 1 or -1, 0.0001)
      outward.corneringInvert = true
      local inverted = ramp(cornering.new(), g, 2, 60, outward)
      near(inverted.roll, -out.roll, 1e-9)
      near(inverted.lateralG, out.lateralG, 1e-9)
      outward.corneringInvert = false
    end
  end)

  test('changing cornering direction under load crosses neutral smoothly', function()
    local state = cornering.new()
    local held, velocity = ramp(state, 2, 1, 60)
    truthy(held.roll > 2)
    local inward = copy(cfg)
    inward.corneringInvert = true
    velocity.y = velocity.y + 2 * gravity / 60
    local out = cornering.step(state, velocity, forward, 1 / 60, inward)
    truthy(out.roll > 0 and out.roll < held.roll, 'The first toggle frame must not flip the held roll')
    near(out.lateralG, held.lateralG, 1e-6)
    local crossed = false
    for _ = 1, 60 do
      velocity.y = velocity.y + 2 * gravity / 60
      out = cornering.step(state, velocity, forward, 1 / 60, inward)
      if out.roll < 0 then crossed = true end
      truthy(math.abs(out.roll) <= inward.corneringLimit)
    end
    truthy(crossed); truthy(out.roll < -2.8)
    local beforeOutward = out.roll
    velocity.y = velocity.y + 2 * gravity / 60
    out = cornering.step(state, velocity, forward, 1 / 60, cfg)
    truthy(out.roll < 0 and out.roll > beforeOutward, 'The reverse toggle must also release smoothly')
    for _ = 1, 60 do
      velocity.y = velocity.y + 2 * gravity / 60
      out = cornering.step(state, velocity, forward, 1 / 60, cfg)
    end
    truthy(out.roll > 2.8); near(out.lateralG, 2, 1e-9)
  end)

  test('a constant-speed circle produces centripetal cornering feedback', function()
    local speed, omega = 20, gravity / 20
    local state = cornering.new()
    local out
    for frame = 0, 240 do
      local angle = omega * frame / 120
      local heading = vector(math.cos(angle), math.sin(angle))
      local velocity = vector(speed * heading.x, speed * heading.y)
      near(math.sqrt(velocity.x^2 + velocity.y^2), speed, 1e-10)
      out = cornering.step(state, velocity, heading, 1 / 120, cfg)
    end
    truthy(out.lateralG > 0.99 and out.roll > 1.37)
    near(out.lateralG, 1, 0.0001)
  end)

  test('longitudinal acceleration braking and vertical motion do not lean the camera', function()
    for _, g in ipairs({2, -2}) do
      for _, axis in ipairs({'x', 'z'}) do
        local out = ramp(cornering.new(), g, 1, 60, nil, axis)
        equal(out.lateralG, 0); equal(out.roll, 0); equal(out.available, true)
      end
    end
  end)

  test('changing heading without physical acceleration does not invent cornering G', function()
    local state = cornering.new()
    local velocity = vector(20, 0)
    for frame = 0, 120 do
      local heading = vector(math.cos(frame * 0.05), math.sin(frame * 0.05), 0.7)
      local out = cornering.step(state, velocity, heading, 1 / 60, cfg)
      equal(out.lateralG, 0); equal(out.roll, 0)
    end
  end)

  test('cornering filter and response remain consistent at 30 60 and 144 FPS', function()
    local outputs = {}
    for _, fps in ipairs({30, 60, 144}) do
      outputs[#outputs + 1] = ramp(cornering.new(), 2, 1, fps)
    end
    for index = 2, #outputs do
      near(outputs[index].lateralG, outputs[1].lateralG, 1e-9)
      near(outputs[index].roll, outputs[1].roll, 0.002)
    end
  end)

  test('cornering deadzone maximum lean and zero strength constrain the effect', function()
    local out = ramp(cornering.new(), 0.06, 1, 60)
    equal(out.roll, 0)
    local strong = copy(cfg)
    strong.corneringStrength, strong.corneringLimit = 6, 3
    out = ramp(cornering.new(), 2, 2, 60, strong)
    truthy(out.roll <= 3); near(out.roll, 3, 0.0001)
    strong.corneringStrength = 0
    out = ramp(cornering.new(), 2, 1, 60, strong)
    equal(out.roll, 0)
    strong.corneringStrength, strong.corneringLimit = 6, 0
    out = ramp(cornering.new(), 2, 1, 60, strong)
    equal(out.roll, 0)
  end)

  test('cornering smoothing changes onset without changing the steady target', function()
    local fast, slow = copy(cfg), copy(cfg)
    fast.corneringResponse, slow.corneringResponse = 0.05, 1
    local fastOut = ramp(cornering.new(), 2, 0.3, 100, fast)
    local slowOut = ramp(cornering.new(), 2, 0.3, 100, slow)
    truthy(fastOut.roll > slowOut.roll + 1)
    fastOut = ramp(cornering.new(), 2, 8, 100, fast)
    slowOut = ramp(cornering.new(), 2, 8, 100, slow)
    near(fastOut.roll, slowOut.roll, 0.002)
  end)

  test('paused cornering holds and rebased resume releases without a false force', function()
    local state = cornering.new()
    local held, velocity = ramp(state, 2, 1, 60)
    for _ = 1, 100 do
      local out = cornering.step(state, nil, nil, 0, cfg)
      equal(out.roll, held.roll); equal(out.lateralG, held.lateralG)
      equal(out.available, held.available); equal(out.status, held.status)
    end
    velocity.y = velocity.y + 20
    cornering.rebase(state, velocity)
    equal(state.roll, held.roll); equal(state.lateralG, 0)
    local out = cornering.step(state, velocity, forward, 1 / 60, cfg)
    equal(out.lateralG, 0)
    truthy(out.roll < held.roll and out.roll > held.roll * 0.9)
    for _ = 1, 240 do out = cornering.step(state, velocity, forward, 1 / 60, cfg) end
    near(out.roll, 0, 1e-8)
  end)

  test('invalid samples frame gaps and crash outliers softly clear cornering history', function()
    local cases = {
      {v = nil, f = forward, dt = 0.02},
      {v = vector(0/0, 10), f = forward, dt = 0.02},
      {v = vector(20, 30), f = nil, dt = 0.02},
      {v = vector(20, 30), f = vector(0, 0, 1), dt = 0.02},
      {v = vector(20, 30), f = forward, dt = 0/0},
      {v = vector(20, 30), f = forward, dt = -1},
      {v = vector(20, 30), f = forward, dt = 0.25},
      {v = vector(20, 70), f = forward, dt = 0.02},
      {v = vector(20, 25), f = forward, dt = 0.02},
      {v = setmetatable({}, {__index = function() error('Invalid vector') end}), f = forward, dt = 0.02}
    }
    for _, case in ipairs(cases) do
      local state = cornering.new()
      local held = ramp(state, 2, 1, 60)
      local out = cornering.step(state, case.v, case.f, case.dt, cfg)
      equal(out.available, false); equal(out.status, 'unavailable')
      truthy(out.roll > 0 and out.roll < held.roll, 'Bad data must release rather than snap')
      truthy(out.lateralG > 0 and out.lateralG < held.lateralG)
      out = cornering.step(state, vector(100, 100), forward, 1 / 60, cfg)
      equal(out.available, false); equal(out.status, 'priming')
      out = cornering.step(state, vector(100, 100), forward, 1 / 60, cfg)
      equal(out.available, true); truthy(out.lateralG < held.lateralG)
    end
  end)

  test('disabling cornering clears visible lean and force immediately', function()
    local state = cornering.new()
    local _, velocity = ramp(state, 2, 1, 60)
    local disabled = copy(cfg)
    disabled.corneringEnabled = false
    local out = cornering.step(state, velocity, forward, 1 / 60, disabled)
    equal(out.roll, 0); equal(out.lateralG, 0)
    equal(out.available, false); equal(out.status, 'disabled')
    cornering.reset(state)
    equal(state.roll, 0); equal(state.lateralG, 0)
  end)

  test('reducing the lean ceiling also constrains release during unavailable telemetry', function()
    local state = cornering.new()
    local held = ramp(state, 2, 1, 60)
    truthy(held.roll > 2)
    local limited = copy(cfg)
    limited.corneringLimit = 1
    local out = cornering.step(state, nil, forward, 1 / 60, limited)
    equal(out.available, false); equal(out.status, 'unavailable')
    truthy(out.roll > 0 and out.roll <= 1, 'A newly reduced ceiling must constrain held lean')
    out = cornering.step(state, vector(20, 0), forward, 1 / 60, limited)
    equal(out.status, 'priming'); truthy(out.roll > 0 and out.roll <= 1)
  end)

  test('cornering validates numeric settings and primes zero-speed samples safely', function()
    local invalid = copy(cfg)
    invalid.corneringStrength, invalid.corneringLimit = 0/0, math.huge
    invalid.corneringDeadzone, invalid.corneringResponse = 'bad', -1
    local out = ramp(cornering.new(), 2, 1, 60, invalid)
    truthy(out.roll == out.roll and out.roll > 0 and out.roll <= 6)
    local state = cornering.new()
    out = cornering.step(state, vector(0, 0), forward, 1 / 60, cfg)
    equal(out.status, 'priming'); equal(out.available, false)
    out = cornering.step(state, vector(0, 0), forward, 1 / 60, cfg)
    equal(out.available, true); equal(out.roll, 0); equal(out.lateralG, 0)
  end)
end
