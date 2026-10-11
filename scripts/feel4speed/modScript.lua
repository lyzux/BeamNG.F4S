-- The mod manager loads manually retained extensions after scanning scripts.
-- The UI app also explicitly loads the extension when added during a session.
if setExtensionUnloadMode then
  setExtensionUnloadMode('feel4speed_main', 'manual')
else
  extensions.load('feel4speed_main')
end
