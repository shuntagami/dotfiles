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

local log = hs.logger.new('remote-input', 'info')
local watcherEvents = hs.caffeinate.watcher
local restartPending = true
local secureInputWasEnabled = false

local function ensureInputSourceTap()
  -- Password entry (including the lock screen) temporarily blocks event taps.
  -- Wait for it to finish before recreating the tap, even if isEnabled is true.
  if hs.eventtap.isSecureInputEnabled() then
    secureInputWasEnabled = true
    return
  end

  if restartPending or secureInputWasEnabled or not inputSourceTap:isEnabled() then
    inputSourceTap:stop():start()
    restartPending = not inputSourceTap:isEnabled()
    secureInputWasEnabled = false
    if not restartPending then
      log.i('Input source key monitoring started')
    end
  end
end

local wakeEvents = {
  [watcherEvents.systemDidWake] = true,
  [watcherEvents.screensDidWake] = true,
  [watcherEvents.screensDidUnlock] = true,
  [watcherEvents.sessionDidBecomeActive] = true,
}

-- Delay until macOS has finished restoring the session; the periodic check
-- below retries if Secure Input or Accessibility still prevents startup.
local recoveryTimer = hs.timer.delayed.new(1, ensureInputSourceTap)
local wakeWatcher = watcherEvents.new(function(event)
  if wakeEvents[event] then
    restartPending = true
    recoveryTimer:start()
  end
end):start()

local healthTimer = hs.timer.doEvery(2, ensureInputSourceTap)
ensureInputSourceTap()

-- Keep watchers and timers alive along with the tap in package.loaded.
return {
  tap = inputSourceTap,
  wakeWatcher = wakeWatcher,
  recoveryTimer = recoveryTimer,
  healthTimer = healthTimer,
}
