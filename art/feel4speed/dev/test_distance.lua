return function(test, equal, truthy, near)
  local function fixture(run)
    local oldVec3, oldRay = vec3, castRayStatic
    vec3 = function(x, y, z) return {x = x, y = y, z = z} end
    castRayStatic = function(_, _, distance) return distance end
    local ok, err = xpcall(run, debug.traceback)
    vec3, castRayStatic = oldVec3, oldRay
    if not ok then error(err) end
  end
  local function frame(distance)
    return {res = {pos = {x = 0, y = -(distance or 5), z = 0},
      targetPos = {x = 0, y = 0, z = 0}, fov = 70, nearClip = 0.1}}
  end
  local distance = require('ge/extensions/feel4speed/distance')
  test('camera spring uses fresh native positions and moves outward/inward with nine probes', function()
    fixture(function()
      local probes = 0
      castRayStatic = function(origin, dir, length)
        probes = probes + 1
        truthy(type(origin.x) == 'number')
        near(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z, 1)
        return length
      end
      local outward = frame()
      local native = outward.res.pos
      near(distance.apply(outward, 'orbit', 0.5), 0.5)
      near(outward.res.pos.y, -5.5); near(native.y, -5)
      equal(probes, 9)
      local nextFrame = frame()
      near(distance.apply(nextFrame, 'orbit', 0.5), 0.5)
      near(nextFrame.res.pos.y, -5.5)
      local inward = frame()
      near(distance.apply(inward, 'chase', -0.5), -0.5)
      near(inward.res.pos.y, -4.5)
    end)
  end)
  test('camera spring caps inward fraction/minimum and outward travel including pole positions', function()
    fixture(function()
      local data = frame()
      near(distance.apply(data, 'orbit', -10), -0.6)
      near(data.res.pos.y, -4.4)
      data = frame(1.1)
      near(distance.apply(data, 'orbit', -10), -0.1)
      near(data.res.pos.y, -1)
      data = frame(0.8)
      equal(distance.apply(data, 'orbit', -10), 0)
      near(data.res.pos.y, -0.8)
      data = frame()
      near(distance.apply(data, 'orbit', 10), 1.25)
      data = frame(); data.res.pos = {x = 0, y = 0, z = 5}
      near(distance.apply(data, 'orbit', 0.3), 0.3)
      near(data.res.pos.z, 5.3)
    end)
  end)
  test('camera spring clearance uses nearest edge/corner obstacle before mutating output', function()
    fixture(function()
      local count = 0
      castRayStatic = function(_, _, length)
        count = count + 1
        return count == 9 and 0.3 or length
      end
      local data = frame()
      near(distance.apply(data, 'orbit', 1), 0.18)
      near(data.res.pos.y, -5.18); equal(count, 9)
      castRayStatic = function() return 0.1 end
      data = frame(); equal(distance.apply(data, 'orbit', 1), 0)
      near(data.res.pos.y, -5)
    end)
  end)
  test('camera spring fails softly for unsupported cameras, invalid data and query failures', function()
    fixture(function()
      local data = frame()
      equal(distance.apply(data, 'driver', 1), 0)
      equal(distance.apply(data, 'orbit', math.huge), 0)
      equal(distance.apply(nil, 'orbit', 1), 0)
      local invalid = frame(); invalid.res.pos.x = 0/0
      equal(distance.apply(invalid, 'orbit', 1), 0)
      invalid = frame(); invalid.res.targetPos = 'bad'
      equal(distance.apply(invalid, 'orbit', 1), 0)
      castRayStatic = nil
      equal(distance.apply(data, 'orbit', 1), 0)
      castRayStatic = function() return nil end
      equal(distance.apply(data, 'orbit', 1), 0)
      local count = 0
      castRayStatic = function(_, _, length)
        count = count + 1
        if count == 8 then error('query failed') end
        return length
      end
      local native = data.res.pos
      equal(distance.apply(data, 'orbit', 1), 0)
      equal(data.res.pos, native); near(data.res.pos.y, -5)
      vec3 = nil
      equal(distance.apply(data, 'orbit', 1), 0)
    end)
  end)
  test('camera spring accepts callable vector constructors and rejects noncallable ones softly', function()
    fixture(function()
      local constructor = vec3
      vec3 = setmetatable({}, {__call = function(_, x, y, z)
        return constructor(x, y, z)
      end})
      local data = frame()
      near(distance.apply(data, 'orbit', 0.5), 0.5)
      near(data.res.pos.y, -5.5)
      vec3 = {}
      data = frame()
      local native = data.res.pos
      equal(distance.apply(data, 'orbit', 0.5), 0)
      equal(data.res.pos, native)
      near(data.res.pos.y, -5)
    end)
  end)
end
