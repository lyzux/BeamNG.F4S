-- Feel4Speed: an additive camera filter. No stock camera files are replaced.
local C = {}
C.__index = C

function C:init()
  self.isGlobal = true
  self.isFilter = true
  self.hidden = true
  self.runningOrder = 0.9
  self.loadAttempted = false
  self.processorFailed = false
  self.processing = false
end

local function reportOnce(self, reason)
  if self.processorFailed then return end
  self.processorFailed = true
  if type(log) == 'function' then
    log('E', 'Feel4Speed.camera', tostring(reason))
  end
  local main = rawget(_G, 'feel4speed_main')
  if main and type(main.suspend) == 'function' then
    pcall(main.suspend, tostring(reason))
  end
end

function C:update(data)
  if self.processorFailed or self.processing then return end

  local main = rawget(_G, 'feel4speed_main')
  if main then self.loadAttempted = true end
  if not main and not self.loadAttempted then
    self.loadAttempted = true
    if extensions and type(extensions.load) == 'function' then
      local ok, reason = pcall(extensions.load, 'feel4speed_main')
      if not ok then
        reportOnce(self, 'Unable to load Feel4Speed: ' .. tostring(reason))
        return
      end
    end
    main = rawget(_G, 'feel4speed_main')
  end

  -- After an explicit unload, do not reload the extension every frame.
  if not main or type(main.processCamera) ~= 'function' then return end

  self.processing = true
  local ok, reason = pcall(main.processCamera, data)
  self.processing = false
  if not ok then
    reportOnce(self, 'Camera filter suspended: ' .. tostring(reason))
  end
end

return function(...)
  local o = ... or {}
  setmetatable(o, C)
  o:init()
  return o
end
