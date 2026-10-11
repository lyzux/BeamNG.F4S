-- Register these sampler contracts with the main test suite's helpers.
return function(test, equal, truthy)
  local function sampler()
    package.loaded['ge/extensions/feel4speed/rpm'] = nil
    return require('ge/extensions/feel4speed/rpm')
  end
  local function vehicle()
    return {commands = {}, queueLuaCommand = function(self, command)
      self.commands[#self.commands + 1] = command
    end}
  end
  local function reply(rpm, veh, id, engineRpm)
    local queue = {}
    local env = {
      electrics = {values = {rpm = engineRpm}},
      obj = {queueGameEngineLua = function(_, command) queue[#queue + 1] = command end},
      string = string, math = math, type = type
    }
    assert(load(veh.commands[#veh.commands], 'RPM Vehicle Lua request', 't', env))()
    equal(#queue, 1)
    local token
    local ge = {extensions = {feel4speed_main = {receiveRpm = function(receivedId, receivedToken, value)
      equal(receivedId, id); token = receivedToken
      return rpm.receive(receivedId, receivedToken, value)
    end}}}
    assert(load(queue[1], 'RPM GE reply', 't', ge))()
    return token
  end
  test('RPM fixed VM queue request receives finite engine RPM independently of UI', function()
    local rpm, veh = sampler(), vehicle()
    local value, available = rpm.step(veh, 8, 0)
    equal(value, 0); equal(available, false); equal(#veh.commands, 1)
    reply(rpm, veh, 8, 6543.25)
    value, available = rpm.get()
    equal(value, 6543.25); equal(available, true)
    rpm.step(veh, 8, 0.049)
    equal(#veh.commands, 1)
    rpm.step(veh, 8, 0.0011)
    equal(#veh.commands, 2)
  end)
  test('RPM samples expire, retry once per step, and reject stale switch/reset replies', function()
    local rpm, veh = sampler(), vehicle()
    rpm.step(veh, 8, 0)
    local old = reply(rpm, veh, 8, 7000)
    rpm.step(veh, 8, 0.51)
    local value, available = rpm.get()
    equal(value, 0); equal(available, false); equal(#veh.commands, 2)
    equal(rpm.receive(8, old, 7500), false)
    rpm.step(veh, 9, 0)
    equal(rpm.receive(8, old, 7500), false)
    local switched = reply(rpm, veh, 9, 900)
    rpm.reset(); rpm.step(veh, 9, 0)
    equal(rpm.receive(9, switched, 7500), false)
    reply(rpm, veh, 9, 0)
    value, available = rpm.get(); equal(value, 0); equal(available, true)
  end)
  test('RPM outstanding requests are bounded and missing or failing vehicle APIs are soft', function()
    local rpm, veh = sampler(), vehicle()
    rpm.step(veh, 8, 0)
    for _ = 1, 10 do rpm.step(veh, 8, 0.01) end
    equal(#veh.commands, 1)
    rpm.step(veh, 8, 0.151); equal(#veh.commands, 2)
    rpm.step(veh, 8, 8); equal(#veh.commands, 3)
    local value, available = rpm.step({}, 8, 0.1)
    equal(value, 0); equal(available, false)
    value, available = rpm.step({queueLuaCommand = function() error('vehicle removed') end}, 8, 0.1)
    equal(value, 0); equal(available, false)
    value, available = rpm.step(nil, nil, 0.1)
    equal(value, 0); equal(available, false)
  end)
  test('RPM reply validation and module reload reject invalid and obsolete data', function()
    local rpm, veh = sampler(), vehicle()
    rpm.step(veh, 8, 0)
    local first = reply(rpm, veh, 8, 6000)
    rpm.step(veh, 8, 0.06)
    equal(rpm.receive(8, first, math.huge), false)
    equal(rpm.receive('8', first, 1000), false)
    equal(rpm.receive(8, tostring(first), 1000), false)
    local nextToken
    local command = veh.commands[#veh.commands]
    local env = {electrics = {values = {rpm = 6000}},
      obj = {queueGameEngineLua = function(_, source)
        nextToken = tonumber(source:match('receiveRpm%([^,]+,([^,]+),'))
      end}, string = string, math = math, type = type}
    assert(load(command, nil, 't', env))()
    truthy(nextToken > first)
    equal(rpm.receive(8, nextToken, -1), false)
    local fresh = sampler(); fresh.step(veh, 8, 0)
    equal(fresh.receive(8, nextToken, 6000), false)
    reply(fresh, veh, 8, 30000)
    local value, available = fresh.get(); equal(value, 30000); equal(available, true)
  end)
end
