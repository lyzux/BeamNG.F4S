-- Called by the main contract suite with its assertion/reporting helpers.
return function(test, equal, near, truthy)
  local dynamics = require('feel4speed/dynamics')
  local cfg = {activeEnabled = true, accelReference = 6, accelDeadzone = 0.5,
    accelerationFov = 6, brakingFov = 8, accelerationDistance = 0.30,
    brakingDistance = 0.35, springTime = 0.25, springDamping = 0.85}
  local function tick(state, speed, dt, settings)
    dynamics.sample(state, speed, dt)
    return dynamics.step(state, dt, settings or cfg)
  end
  local function ramp(state, speed, acceleration, seconds, fps, settings)
    local out
    for _ = 1, math.floor(seconds * fps + 0.5) do
      speed = speed + acceleration / fps
      out = tick(state, speed, 1 / fps, settings)
    end
    return speed, out
  end
  local function assertZero(out)
    equal(out.acceleration, 0); equal(out.demand, 0)
    equal(out.kick, 0); equal(out.distance, 0)
  end

  test('active feedback primes at current speed without an initial kick', function()
    local state = dynamics.new()
    assertZero(tick(state, 85, 1 / 60))
    for _ = 1, 90 do assertZero(tick(state, 85, 1 / 60)) end
  end)

  test('rapid low-speed acceleration and high-speed braking have opposite immediate cues', function()
    local state = dynamics.new()
    tick(state, 2, 1 / 120)
    local speed, out = ramp(state, 2, 8, 0.25, 120)
    truthy(out.kick > 5, 'Acceleration must be visible below passive speed onset')
    truthy(out.distance > 0.25, 'Acceleration pulls the spring farther back')
    dynamics.reset(state, 90)
    speed, out = ramp(state, 90, -8, 0.15, 120)
    truthy(out.kick < -6, 'Braking needs a fast negative FOV kick')
    truthy(out.distance < -0.2, 'Braking moves the camera toward the vehicle')
  end)

  test('braking reverses an existing acceleration kick without a slow-release wait', function()
    local state = dynamics.new()
    tick(state, 35, 1 / 120)
    local speed = ramp(state, 35, 8, 0.5, 120)
    local _, out = ramp(state, speed, -8, 0.15, 120)
    truthy(out.kick < -5, 'A braking reversal must cross zero promptly')
    truthy(out.distance < 0, 'Camera spring must follow the reversal')
  end)

  test('active effects return to the unchanged passive baseline at steady speed', function()
    local state = dynamics.new()
    tick(state, 10, 1 / 60)
    local speed = ramp(state, 10, 8, 0.5, 60)
    local _, out = ramp(state, speed, 0, 5, 60)
    equal(out.demand, 0)
    near(out.kick, 0, 1e-7); near(out.distance, 0, 1e-7)
    near(out.acceleration, 0, 1e-7)
  end)

  test('small speed drift and constant-speed cornering create no active cue', function()
    local state = dynamics.new()
    tick(state, 20, 1 / 120)
    local _, out = ramp(state, 20, 0.4, 2, 120)
    equal(out.demand, 0); equal(out.kick, 0); equal(out.distance, 0)
    dynamics.reset(state)
    -- Changing velocity direction alone preserves its magnitude.
    for frame = 0, 120 do
      local angle = frame * 0.03
      local x, y = 30 * math.cos(angle), 30 * math.sin(angle)
      out = tick(state, math.sqrt(x * x + y * y), 1 / 60)
      equal(out.demand, 0); equal(out.kick, 0); equal(out.distance, 0)
    end
  end)

  test('constant acceleration produces consistent dynamics at 30 60 and 144 FPS', function()
    local outputs = {}
    for _, fps in ipairs({30, 60, 144}) do
      local state = dynamics.new()
      tick(state, 10, 1 / fps)
      local _, out = ramp(state, 10, 6, 1, fps)
      outputs[#outputs + 1] = out
    end
    for index = 2, #outputs do
      near(outputs[index].acceleration, outputs[1].acceleration, 1e-9)
      near(outputs[index].kick, outputs[1].kick, 0.001)
      near(outputs[index].distance, outputs[1].distance, 0.0001)
    end
  end)

  test('all damping regimes stay finite during alternating acceleration and braking', function()
    for _, damping in ipairs({0.35, 0.85, 0.99995, 1, 1.00005, 1.5}) do
      local settings = {}
      for key, value in pairs(cfg) do settings[key] = value end
      settings.springDamping = damping
      settings.springTime = 0.08
      local state, speed = dynamics.new(), 30
      tick(state, speed, 1 / 30, settings)
      for interval = 1, 20 do
        local out
        speed, out = ramp(state, speed, interval % 2 == 1 and 12 or -12, 0.3, 30, settings)
        truthy(out.distance == out.distance and math.abs(out.distance) <= 2.5)
        truthy(out.kick == out.kick and math.abs(out.kick) <= 8)
      end
    end
  end)

  test('missing samples pause gaps and discontinuities clear and re-prime active feedback', function()
    local function primed()
      local state = dynamics.new()
      tick(state, 10, 1 / 60)
      local speed, out = ramp(state, 10, 8, 0.5, 60)
      truthy(out.kick > 5)
      return state, speed
    end
    for _, invalid in ipairs({{speed = 0/0, dt = 1/60}, {speed = -1, dt = 1/60},
      {speed = 401, dt = 1/60}, {speed = 14, dt = 0}, {speed = 15, dt = 0.25},
      {speed = 80, dt = 1/60}}) do
      local state = primed()
      assertZero(tick(state, invalid.speed, invalid.dt))
      assertZero(tick(state, 100, 1/60))
      assertZero(tick(state, 100, 1/60))
    end
    local state = primed()
    assertZero(tick(state, nil, 1/60))
    assertZero(tick(state, 100, 1/60))
    state = primed()
    assertZero(dynamics.step(state, 1/60, cfg))
    assertZero(tick(state, 100, 1/60))
  end)

  test('disabling active feedback clears both cues immediately', function()
    local state = dynamics.new()
    tick(state, 10, 1 / 60)
    local speed = ramp(state, 10, 8, 0.5, 60)
    local disabled = {activeEnabled = false}
    assertZero(tick(state, speed + 8 / 60, 1 / 60, disabled))
    assertZero(tick(state, speed + 8 / 60, 1 / 60))
  end)

  test('pause resume rebases speed while held camera offsets release continuously', function()
    local state = dynamics.new()
    tick(state, 10, 1 / 60)
    local speed, held = ramp(state, 10, 8, 0.5, 60)
    local heldVelocity = state.distanceVelocity
    -- The engine skips sample/step during pause, then re-primes at resume.
    dynamics.rebase(state, speed + 20)
    equal(state.kick, held.kick); equal(state.distance, held.distance)
    equal(state.distanceVelocity, heldVelocity)
    equal(state.acceleration, 0); equal(state.demand, 0)
    local out = tick(state, speed + 20, 1 / 60)
    equal(out.acceleration, 0); equal(out.demand, 0)
    truthy(out.kick > held.kick * 0.9, 'Resume must retain the held FOV kick')
    truthy(out.distance > held.distance * 0.9, 'Resume must retain the held spring offset')
    _, out = ramp(state, speed + 20, 0, 5, 60)
    near(out.kick, 0, 1e-7); near(out.distance, 0, 1e-7)
    dynamics.rebase(state, 0/0)
    equal(state.kick, 0); equal(state.distance, 0); equal(state.speed, nil)
  end)
end
