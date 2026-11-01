local eventTypes = hs.eventtap.event.types
local userData = hs.eventtap.event.properties.eventSourceUserData
local probeTag = 0x52494D45 -- RIME: a null event, never a synthetic keystroke
local probePending = false
local probeReplies, restarts = 0, 0
local log = hs.logger.new('remote-input', 'info')
local requestedSourceID
local switchTimer = hs.timer.delayed.new(0.01, function()
  -- Input methods may take time to activate. Do not hold up the event tap:
  -- macOS can disable taps whose callbacks take too long.
  if not hs.keycodes.currentSourceID(requestedSourceID) then
    log.w('Unable to select input source: ' .. requestedSourceID)
  end
end)

local jumpDesktopBundleIDs = {
  ['com.p5sys.jump.mac.viewer'] = true,
  ['com.p5sys.jump.mac.viewer.web'] = true,
}

local inputSourceIDsByKeyCode = {
  [hs.keycodes.map.f18] = 'com.apple.keylayout.ABC',
  [hs.keycodes.map.f19] = 'com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese',
}

local inputSourceTap = hs.eventtap.new(
  {eventTypes.keyDown, eventTypes.keyUp, eventTypes.nullEvent},
  function(event)
    if event:getType() == eventTypes.nullEvent then
      if event:getProperty(userData) == probeTag then
        probePending = false
        probeReplies = probeReplies + 1
        return true
      end
      return false
    end

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
      requestedSourceID = inputSourceID
      switchTimer:start()
    end

    return true
  end
)

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

  -- isEnabled() alone cannot prove the callback is still receiving events.
  -- A probe left unanswered until this check requires a fresh event tap.
  if restartPending or secureInputWasEnabled or not inputSourceTap:isEnabled() or probePending then
    if probePending and not secureInputWasEnabled then
      log.w('Input monitoring did not answer health probe; recreating event tap')
    end
    inputSourceTap:stop():start()
    restarts = restarts + 1
    probePending = false
    restartPending = not inputSourceTap:isEnabled()
    secureInputWasEnabled = false
    if not restartPending then
      log.i('Input source key monitoring started')
    end
  end

  if inputSourceTap:isEnabled() then
    probePending = true
    hs.eventtap.event.newEvent():setProperty(userData, probeTag):post()
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
  switchTimer = switchTimer,
  status = function()
    return {
      enabled = inputSourceTap:isEnabled(),
      secureInput = hs.eventtap.isSecureInputEnabled(),
      healthTimerRunning = healthTimer:running(),
      probePending = probePending,
      probeReplies = probeReplies,
      restarts = restarts,
    }
  end,
}
