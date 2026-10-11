-- Feel4Speed's own fullscreen PostFX. Requires no changes to game graphics settings.
-- Module API: set(vignette, blur, {x=0.5, y=0.5}) -> success, status; shutdown().
local M = {}

local NAMES = {
  shader = 'Feel4Speed_Shader',
  state = 'Feel4Speed_State',
  effect = 'Feel4Speed_PostFX',
  callback = 'Feel4Speed_PostFXCallbacks'
}
local OWNER = 'Feel4Speed/1'
local SHADER_PATH = 'art/feel4speed/shaders/feel4speedP.hlsl'
local owned = {}
local params = {0, 0, 0.5, 0.5}
local effect
local callbacks
local attempted = false
local enabled = false
local failure

local function finiteClamped(value, fallback, minimum, maximum)
  value = tonumber(value)
  if not value or value ~= value or value == math.huge or value == -math.huge then
    return fallback
  end
  return math.min(maximum, math.max(minimum, value))
end

local function removeOwnedObjects()
  -- Reverse order: effect must release shader/state references first.
  for i = #owned, 1, -1 do
    local object = owned[i]
    pcall(function()
      if object:getField('f4sOwner', 0) == OWNER then
        if i == #owned and effect == object then object:disable() end
        object:delete()
      end
    end)
  end
  owned = {}
  effect = nil
  enabled = false
  if callbacks and rawget(_G, NAMES.callback) == callbacks then
    rawset(_G, NAMES.callback, nil)
  end
  callbacks = nil
end

local function fail(message)
  failure = 'unavailable: ' .. tostring(message)
  if effect then pcall(function() effect:disable() end) end
  enabled = false
  return false, failure
end

local function makeObject(className, name)
  if scenetree.findObject(name) then
    -- Names are private to this mod. A collision is safer to reject than adopt.
    error('object name already in use: ' .. name)
  end
  local object = createObject(className)
  if not object then error('cannot create ' .. className) end
  object:setField('f4sOwner', 0, OWNER)
  owned[#owned + 1] = object
  object.canSave = false
  return object
end

local function setConstants()
  if effect and not failure then
    effect:setShaderConst('$f4sParams', string.format('%.6f %.6f %.6f %.6f',
      params[1], params[2], params[3], params[4]))
  end
end

local function initialize()
  attempted = true
  local ok, err = pcall(function()
    if not createObject or not scenetree or not scenetree.findObject then
      error('BeamNG PostFX API is not present')
    end
    if FS and FS.fileExists and not FS:fileExists('/' .. SHADER_PATH) then
      error('Feel4Speed shader file is missing')
    end

    local shader = makeObject('ShaderData', NAMES.shader)
    -- Current BeamNG compiles a shared source twice using SHADER_STAGE_VS.
    shader.DXVertexShaderFile = SHADER_PATH
    shader.DXPixelShaderFile = SHADER_PATH
    shader.pixVersion = 5.0
    shader:registerObject(NAMES.shader)

    local state = makeObject('GFXStateBlockData', NAMES.state)
    state.zDefined = true
    state.zEnable = false
    state.zWriteEnable = false
    state.blendDefined = true
    state.blendEnable = false
    state.samplersDefined = true
    state:setField('samplerStates', 0, 'SamplerClampLinear')
    state:registerObject(NAMES.state)

    callbacks = {
      onEnabled = function() return not failure end,
      setShaderConsts = function()
        if not failure then
          local constOk, constErr = pcall(setConstants)
          if not constOk then fail(constErr) end
        end
      end
    }
    rawset(_G, NAMES.callback, callbacks)

    effect = makeObject('PostEffect', NAMES.effect)
    effect.isEnabled = false
    effect.allowReflectPass = false
    effect:setField('shader', 0, NAMES.shader)
    effect:setField('stateBlock', 0, NAMES.state)
    effect:setField('texture', 0, '$backBuffer')
    effect:setField('target', 0, '$backBuffer')
    effect:setField('renderTime', 0, 'PFXAfterDiffuse')
    -- Later than regular antialiasing effects sharing PFXAfterDiffuse.
    effect:setField('renderPriority', 0, '-100')
    effect:registerObject(NAMES.effect)
  end)
  if not ok then
    removeOwnedObjects()
    return fail(err)
  end
  return true, 'ready'
end

function M.set(vignette, blur, center)
  params[1] = finiteClamped(vignette, 0, 0, 1)
  params[2] = finiteClamped(blur, 0, 0, 1)
  if type(center) == 'table' then
    params[3] = finiteClamped(center.x or center[1], 0.5, 0.05, 0.95)
    params[4] = finiteClamped(center.y or center[2], 0.5, 0.05, 0.95)
  else
    params[3], params[4] = 0.5, 0.5
  end
  if failure then return false, failure end

  local wantEnabled = params[1] > 0.0001 or params[2] > 0.0001
  if not effect then
    if not wantEnabled then return true, 'disabled' end
    if attempted then return fail('PostEffect was removed; reload Feel4Speed to recreate it') end
    local ok, status = initialize()
    if not ok then return false, status end
  end

  local ok, err = pcall(function()
    if not scenetree.findObject(NAMES.effect) then
      error('PostEffect was removed; reload Feel4Speed to recreate it')
    end
    if wantEnabled then
      setConstants()
      if not enabled then
        local accepted = effect:enable()
        if accepted == false then error('renderer declined the PostEffect') end
        enabled = true
      end
    elseif enabled then
      effect:disable()
      enabled = false
    end
  end)
  if not ok then return fail(err) end
  if failure then return false, failure end
  return true, enabled and 'enabled (GPU compilation not verified)' or 'disabled'
end

function M.shutdown()
  removeOwnedObjects()
  attempted = false
  failure = nil
  params = {0, 0, 0.5, 0.5}
end

return M
