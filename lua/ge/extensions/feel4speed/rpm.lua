-- Feel4Speed RPM sampler. No UI stream or persistent Vehicle Lua publisher.
local M = {}
local INTERVAL, RETRY_AFTER, EXPIRES_AFTER = 0.05, 0.25, 0.5
local MAX_INTEGER = 9007199254740991 -- Exact integers in LuaJIT's number type.
local SEQUENCE_KEY = '__feel4speedRpmSequence'
local function finite(value)
  return type(value) == 'number' and value == value and
    value ~= math.huge and value ~= -math.huge
end
local function integer(value)
  return finite(value) and value >= 0 and value <= MAX_INTEGER and value % 1 == 0
end

-- Persist through module reloads. A wall/CPU-clock seed also separates normal
-- full GE VM reloads, where globals are discarded. It is not a durable counter
-- across processes; pending commands belong to the running game session only.
local seed = math.floor(os.time() * 1000000 + (os.clock() % 1) * 1000000)
local previous = rawget(_G, SEQUENCE_KEY)
if not integer(previous) or previous < seed then
  rawset(_G, SEQUENCE_KEY, seed)
end
local function nextToken()
  local value = rawget(_G, SEQUENCE_KEY)
  if not integer(value) or value >= MAX_INTEGER then return nil end
  value = value + 1
  rawset(_G, SEQUENCE_KEY, value)
  return value
end

local vehicleId, pendingToken, value
local pollAge, pendingAge, sampleAge = INTERVAL, 0, EXPIRES_AFTER
local status = 'idle'

function M.reset()
  vehicleId, pendingToken, value = nil, nil, nil
  pollAge, pendingAge, sampleAge = INTERVAL, 0, EXPIRES_AFTER
  status = 'idle'
end

function M.get()
  if value ~= nil and sampleAge < EXPIRES_AFTER then
    return value, true, 'ready'
  end
  return 0, false, status
end

function M.receive(id, token, rpm)
  if not integer(id) or not integer(token) or
    id ~= vehicleId or token ~= pendingToken then return false end
  pendingToken, pendingAge = nil, 0
  if not finite(rpm) or rpm < 0 or rpm > 30000 then
    value, sampleAge, status = nil, EXPIRES_AFTER, 'unavailable'
    return false
  end
  value, sampleAge, status = rpm, 0, 'ready'
  return true
end

function M.step(veh, id, dtReal)
  if not veh or not integer(id) then
    M.reset()
    status = 'unavailable'
    return M.get()
  end
  if vehicleId ~= id then M.reset(); vehicleId = id end
  if type(veh.queueLuaCommand) ~= 'function' then
    pendingToken, value, sampleAge, status = nil, nil, EXPIRES_AFTER, 'unavailable'
    return M.get()
  end
  local dt = finite(dtReal) and math.max(0, dtReal) or 0
  pollAge = pollAge + dt
  sampleAge = sampleAge + dt
  if value ~= nil and sampleAge >= EXPIRES_AFTER then
    value, status = nil, 'stale'
  end
  if pendingToken then
    pendingAge = pendingAge + dt
    if pendingAge >= RETRY_AFTER then
      pendingToken, pendingAge = nil, 0
    end
  end
  if not pendingToken and pollAge >= INTERVAL then
    local token = nextToken()
    if not token then status = 'unavailable'; return M.get() end
    pollAge, pendingAge, pendingToken = 0, 0, token
    -- Only our fixed callback and validated numeric literals cross the VM.
    -- Both caller and receiver reject non-finite values; no arbitrary strings
    -- from settings, vehicles or UI are used as source code.
    local prefix = string.format(
      'if extensions.feel4speed_main and extensions.feel4speed_main.receiveRpm then ' ..
      'extensions.feel4speed_main.receiveRpm(%.0f,%.0f,', id, token)
    local command = string.format(
      "local e=electrics and electrics.values; local r=e and e.rpm; " ..
      "if type(r)=='number' and r==r and r~=math.huge and r~=-math.huge and r>=0 and r<=30000 then " ..
      "obj:queueGameEngineLua(%q..string.format('%%.17g',r)..') end') end", prefix)
    local ok = pcall(veh.queueLuaCommand, veh, command)
    if not ok then
      pendingToken, value, sampleAge, status = nil, nil, EXPIRES_AFTER, 'unavailable'
    elseif value == nil then status = 'waiting' end
  end
  return M.get()
end

return M
