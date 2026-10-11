-- Additive camera spring travel, with independent static-geometry clearance.
-- Stock orbit/chase output remains our baseline; native camera state is untouched.
local M = {}
local CLEARANCE, PROBE_RADIUS = 0.12, 0.2
local function finite(value)
  return type(value) == 'number' and value == value and
    value ~= math.huge and value ~= -math.huge
end
local function xyz(value)
  return value ~= nil and finite(value.x) and finite(value.y) and finite(value.z)
end

function M.apply(data, camera, offset)
  if camera ~= 'orbit' and camera ~= 'chase' then return 0, 'unsupported camera' end
  if not finite(offset) then return 0, 'invalid offset' end
  if math.abs(offset) < 1e-8 then return 0, 'idle' end
  -- BeamNG can expose constructors as callable tables/FFI ctypes as well as
  -- functions. Construction below stays protected and validates the result.
  if vec3 == nil or type(castRayStatic) ~= 'function' then
    return 0, 'collision query unavailable'
  end
  local ok, applied, status, candidate = pcall(function()
    local res = type(data) == 'table' and data.res
    if type(res) ~= 'table' or not xyz(res.pos) or not xyz(res.targetPos) then
      return 0, 'camera position unavailable'
    end
    local pos, target = res.pos, res.targetPos
    local dx, dy, dz = pos.x - target.x, pos.y - target.y, pos.z - target.z
    local nativeDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if not finite(nativeDistance) or nativeDistance < 1e-6 then
      return 0, 'camera distance unavailable'
    end
    local sign = offset > 0 and 1 or -1
    local travel
    if sign > 0 then travel = math.min(offset, 1.25)
    else travel = math.max(0, math.min(-offset, nativeDistance * 0.12, nativeDistance - 1)) end
    if travel < 1e-8 then return 0, 'distance limited' end
    dx, dy, dz = dx / nativeDistance, dy / nativeDistance, dz / nativeDistance
    -- A horizontal right vector perpendicular to the radial direction. Use a
    -- different reference axis at the poles, where world-Z would be parallel.
    local rx, ry, rz = dy, -dx, 0
    local rightLength = math.sqrt(rx * rx + ry * ry)
    if rightLength < 1e-6 then
      rx, ry, rz = 0, dz, -dy
      rightLength = math.sqrt(ry * ry + rz * rz)
    end
    rx, ry, rz = rx / rightLength, ry / rightLength, rz / rightLength
    local ux, uy, uz = dy * rz - dz * ry, dz * rx - dx * rz, dx * ry - dy * rx
    local radius = PROBE_RADIUS
    if finite(res.nearClip) and res.nearClip > 0 and
      finite(res.fov) and res.fov > 0 and res.fov < 160 then
      radius = math.min(0.6, radius + res.nearClip * math.tan(math.rad(res.fov) * 0.5))
    end
    local direction = vec3(dx * sign, dy * sign, dz * sign)
    if not xyz(direction) then return 0, 'camera vector unavailable' end
    local rayLength = travel + CLEARANCE
    local permitted = travel
    -- Center, cardinal edges and corners protect a small cross section rather
    -- than relying on a single center ray. This is an original conservative
    -- guard, not a substitute for the game's complete camera collision model.
    for right = -1, 1 do
      for up = -1, 1 do
        local origin = vec3(pos.x + radius * (rx * right + ux * up),
          pos.y + radius * (ry * right + uy * up),
          pos.z + radius * (rz * right + uz * up))
        if not xyz(origin) then return 0, 'camera vector unavailable' end
        local hit = castRayStatic(origin, direction, rayLength)
        if not finite(hit) or hit < 0 then return 0, 'collision query unavailable' end
        permitted = math.min(permitted, math.max(0, hit - CLEARANCE))
      end
    end
    if permitted < 1e-8 then return 0, 'obstacle limited' end
    local result = vec3(pos.x + dx * sign * permitted,
      pos.y + dy * sign * permitted, pos.z + dz * sign * permitted)
    if not xyz(result) then return 0, 'camera vector unavailable' end
    return sign * permitted, permitted < travel and 'obstacle limited' or 'active', result
  end)
  if not ok then return 0, 'collision query unavailable' end
  if candidate then data.res.pos = candidate end
  return applied, status
end

return M
