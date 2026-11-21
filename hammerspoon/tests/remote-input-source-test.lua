-- Run from the repository root: lua hammerspoon/tests/remote-input-source-test.lua
local secure, enabled, failStart = false, false, false
local starts, selectedSource = 0, nil
local bundleID = 'com.apple.TextEdit'
local onKey, onWake, onHealth, onRecovery
local onSwitch, postedProbe
local receiveProbes = true
local switches = 0
local tap = {}
function tap:start()
  starts = starts + 1
  enabled = not failStart
  return self
end
function tap:stop() enabled = false; return self end
function tap:isEnabled() return enabled end
local timer = {start = function(self) return self end, running = function() return true end}
hs = {
  eventtap = {
    event = {
      types = {nullEvent = 0, keyDown = 1, keyUp = 2},
      properties = {eventSourceUserData = 42},
      newEvent = function()
        local event = {getType = function() return 0 end}
        function event:setProperty(_, value) self.tag = value; return self end
        function event:getProperty(_) return self.tag end
        function event:post()
          postedProbe = self
          if receiveProbes then assert(onKey(self), 'probe must be consumed') end
          return self
        end
        return event
      end,
    },
    new = function(_, callback) onKey = callback; return tap end,
    isSecureInputEnabled = function() return secure end,
  },
  application = {frontmostApplication = function()
    if not bundleID then return nil end
    return {bundleID = function() return bundleID end}
  end},
  keycodes = {
    map = {f18 = 79, f19 = 80},
    currentSourceID = function(id) selectedSource = id; switches = switches + 1; return true end,
  },
  logger = {new = function() return {i = function() end, w = function() end} end},
  caffeinate = {watcher = {
    systemDidWake = 1, screensDidWake = 2, screensDidUnlock = 3,
    sessionDidBecomeActive = 4,
    new = function(callback) onWake = callback; return timer end,
  }},
  timer = {
    delayed = {new = function(delay, callback)
      if delay == 0.01 then onSwitch = callback else onRecovery = callback end
      return timer
    end},
    doEvery = function(_, callback) onHealth = callback; return timer end,
  },
}

local function key(code, kind)
  return onKey({getKeyCode = function() return code end,
    getType = function() return kind end})
end

local module = dofile('hammerspoon/keyboard/remote-input-source.lua')
assert(module.tap == tap and enabled)
assert(module.status().probeReplies == 1)
assert(key(79, 1) and selectedSource == nil, 'switch must run outside the event callback')
onSwitch()
assert(selectedSource == 'com.apple.keylayout.ABC')
assert(key(80, 1))
onSwitch()
assert(selectedSource == 'com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese')
selectedSource = nil
assert(key(80, 2) and selectedSource == nil)
assert(not key(0, 1))
assert(not onKey({getType = function() return 0 end, getProperty = function() return 0 end}),
  'unrelated null events must pass through')
for _, id in ipairs({'com.p5sys.jump.mac.viewer', 'com.p5sys.jump.mac.viewer.web'}) do
  bundleID = id
  assert(not key(79, 1) and not key(80, 2) and selectedSource == nil)
end
bundleID = nil
assert(key(79, 1))

local before = starts
onHealth()
assert(starts == before, 'healthy taps should not restart')
enabled = false
onHealth()
assert(enabled and starts == before + 1, 'disabled taps should recover')

-- Model the missing case in the previous watchdog: macOS still reports the
-- tap as enabled, but no callbacks arrive. No keyboard input is synthesized.
before = starts
local beforeSwitches = switches
receiveProbes = false
onHealth()
assert(enabled and starts == before and module.status().probePending)
receiveProbes = true
onHealth()
assert(enabled and starts == before + 1 and not module.status().probePending,
  'enabled but unresponsive taps should recover on the next health check')
assert(postedProbe:getType() == 0 and switches == beforeSwitches,
  'health probes must not switch input sources')

for event = 1, 4 do
  before = starts
  onWake(event)
  onRecovery()
  assert(enabled and starts == before + 1, 'wake/unlock must recreate even enabled taps')
end

secure = true
before = starts
onWake(3)
onRecovery()
onHealth()
assert(starts == before, 'wait for Secure Input to end')
secure = false
onHealth()
assert(enabled and starts == before + 1)

secure = true
onHealth()
secure = false
before = starts
onHealth()
assert(starts == before + 1, 'recover after Secure Input without a wake event')

enabled, failStart = false, true
onHealth()
assert(not enabled)
failStart = false
onHealth()
assert(enabled, 'retry when macOS initially rejects startup')

secure = true
before = starts
dofile('hammerspoon/keyboard/remote-input-source.lua')
assert(starts == before, 'startup during Secure Input must wait')
secure = false
onHealth()
assert(starts == before + 1)
print('PASS: deferred input switching, Jump passthrough, wake/unlock, Secure Input, startup retries, unresponsive tap recovery')
