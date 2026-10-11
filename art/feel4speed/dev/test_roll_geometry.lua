-- Original mathematical fixture for BeamNG camera quaternion conventions.
-- Quaternion products are Hamilton products, while quaternion/vector action
-- uses the inverse rotation (Torque's opposite scalar-component convention).
-- Camera local axes: X right, Y forward, Z up. This matters for nonidentity
-- orbit orientations; an identity-only quaternion stub cannot catch it.
return function(test, equal, near, truthy)
  local function vector(x, y, z) return {x = x, y = y, z = z} end
  local function add(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
  local function sub(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
  local function scale(a, s) return vector(a.x * s, a.y * s, a.z * s) end
  local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
  local function cross(a, b)
    return vector(a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
  end
  local function distance(a, b)
    local delta = sub(a, b)
    return math.sqrt(dot(delta, delta))
  end
  local function quaternion(v, s) return {v = v, s = s} end
  local function multiply(a, b)
    return quaternion(add(add(scale(b.v, a.s), scale(a.v, b.s)), cross(a.v, b.v)),
      a.s * b.s - dot(a.v, b.v))
  end
  local function axisAngle(axis, radians)
    return quaternion(scale(axis, math.sin(radians / 2)), math.cos(radians / 2))
  end
  local rightAxis, forwardAxis, upAxis = vector(1, 0, 0), vector(0, 1, 0), vector(0, 0, 1)
  local function fromEuler(x, y, z)
    -- BeamNG's Euler constructor is the Hamilton product Qy * Qz * Qx.
    return multiply(axisAngle(forwardAxis, y),
      multiply(axisAngle(upAxis, z), axisAngle(rightAxis, x)))
  end
  local function rotate(q, v)
    -- Unit quaternion inverse action, written as the expanded rotation map.
    return add(add(scale(v, q.s * q.s - dot(q.v, q.v)),
      scale(q.v, 2 * dot(q.v, v))), scale(cross(q.v, v), -2 * q.s))
  end
  local function nativeEulerDegrees(pitch, roll, yaw)
    return fromEuler(math.rad(pitch), math.rad(roll), math.rad(yaw))
  end
  local baselines = {
    nativeEulerDegrees(14, -21, 73),
    nativeEulerDegrees(-37, 12, -111),
    nativeEulerDegrees(42, 19, 164),
    -- Include the preexisting wobble before adding the camera-local roll.
    multiply(nativeEulerDegrees(-0.6, 1.3, 0.4), nativeEulerDegrees(17, -9, 128))
  }
  local function applyRightRoll(base, degrees)
    return multiply(fromEuler(0, -math.rad(degrees), 0), base)
  end
  local function basis(q)
    return rotate(q, rightAxis), rotate(q, forwardAxis), rotate(q, upAxis)
  end

  test('camera-local roll preserves the view axis for manually rotated orbit baselines', function()
    for _, base in ipairs(baselines) do
      local _, forward = basis(base)
      for _, degrees in ipairs({-12, -3, 0, 3, 12}) do
        local _, rolledForward = basis(applyRightRoll(base, degrees))
        near(distance(rolledForward, forward), 0, 1e-12)
      end
    end
  end)

  test('positive right-roll angles tilt camera up toward its own right axis', function()
    for _, base in ipairs(baselines) do
      local right, _, up = basis(base)
      for _, degrees in ipairs({-12, -3, 0, 3, 12}) do
        local radians = math.rad(degrees)
        local rolledRight, _, rolledUp = basis(applyRightRoll(base, degrees))
        local expectedUp = add(scale(up, math.cos(radians)), scale(right, math.sin(radians)))
        local expectedRight = sub(scale(right, math.cos(radians)), scale(up, math.sin(radians)))
        near(distance(rolledUp, expectedUp), 0, 1e-12)
        near(distance(rolledRight, expectedRight), 0, 1e-12)
        near(dot(rolledUp, right), math.sin(radians), 1e-12)
        if degrees > 0 then truthy(dot(rolledUp, right) > 0, 'Camera up must lean right') end
        if degrees < 0 then truthy(dot(rolledUp, right) < 0, 'Camera up must lean left') end
      end
    end
  end)

  test('nonidentity geometry rejects postmultiplication and the opposite roll sign', function()
    for _, base in ipairs(baselines) do
      local right, forward, up = basis(base)
      local radians = math.rad(10)
      local expectedUp = add(scale(up, math.cos(radians)), scale(right, math.sin(radians)))
      -- Same correct sign, opposite multiplication order: rotates a world
      -- axis and changes the view direction when the orbit is turned.
      local wrongOrder = multiply(base, fromEuler(0, -radians, 0))
      truthy(distance(rotate(wrongOrder, forwardAxis), forward) > 0.001,
        'Postmultiplication must fail the unchanged-view-axis contract')
      -- Same correct order, opposite sign: still a pure roll, but leftward.
      local wrongSign = multiply(fromEuler(0, radians, 0), base)
      truthy(distance(rotate(wrongSign, upAxis), expectedUp) > 0.1,
        'A positive native Y angle must fail the rightward-tilt contract')
      truthy(dot(rotate(wrongSign, upAxis), right) < 0)
    end
  end)

  test('the BeamNG Euler Y axis is roll while X and Z alter the view direction', function()
    local radians = math.rad(10)
    near(distance(rotate(fromEuler(0, radians, 0), forwardAxis), forwardAxis), 0, 1e-12)
    truthy(distance(rotate(fromEuler(radians, 0, 0), forwardAxis), forwardAxis) > 0.1)
    truthy(distance(rotate(fromEuler(0, 0, radians), forwardAxis), forwardAxis) > 0.1)
  end)
end
