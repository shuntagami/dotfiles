local eventTypes = hs.eventtap.event.types

local jumpDesktopBundleIDs = {
  ['com.p5sys.jump.mac.viewer'] = true,
  ['com.p5sys.jump.mac.viewer.web'] = true,
}

local inputSourceIDsByKeyCode = {
  [hs.keycodes.map.f18] = 'com.apple.keylayout.ABC',
  [hs.keycodes.map.f19] = 'com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese',
}

local inputSourceTap = hs.eventtap.new(
  {eventTypes.keyDown, eventTypes.keyUp},
  function(event)
    local inputSourceID = inputSourceIDsByKeyCode[event:getKeyCode()]
    if not inputSourceID then
      return false
    end

    local frontmostApplication = hs.application.frontmostApplication()
    local frontmostBundleID = frontmostApplication and frontmostApplication:bundleID()
    if jumpDesktopBundleIDs[frontmostBundleID] then
      return false
    end

    if event:getType() == eventTypes.keyDown then
      hs.keycodes.currentSourceID(inputSourceID)
    end

    return true
  end
)

inputSourceTap:start()

return inputSourceTap
