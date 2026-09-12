-- Run from the repository root: lua hammerspoon/tests/remote-input-source-test.lua
local secure, enabled, failStart = false, false, false
local starts, selectedSource = 0, nil
local bundleID = 'com.apple.TextEdit'
local onKey, onWake, onHealth, onRecovery
local tap = {}
function tap:start()
  starts = starts + 1
  enabled = not failStart
  return self
end
function tap:stop() enabled = false; return self end
function tap:isEnabled() return enabled end
local timer = {start = function(self) return self end}
hs = {
  eventtap = {
    event = {types = {keyDown = 1, keyUp = 2}},
    new = function(_, callback) onKey = callback; return tap end,
    isSecureInputEnabled = function() return secure end,
  },
  application = {frontmostApplication = function()
    if not bundleID then return nil end
    return {bundleID = function() return bundleID end}
  end},
  keycodes = {
    map = {f18 = 79, f19 = 80},
    currentSourceID = function(id) selectedSource = id end,
  },
  logger = {new = function() return {i = function() end} end},
  caffeinate = {watcher = {
    systemDidWake = 1, screensDidWake = 2, screensDidUnlock = 3,
    sessionDidBecomeActive = 4,
    new = function(callback) onWake = callback; return timer end,
  }},
  timer = {
    delayed = {new = function(_, callback) onRecovery = callback; return timer end},
    doEvery = function(_, callback) onHealth = callback; return timer end,
  },
}

local function key(code, kind)
  return onKey({getKeyCode = function() return code end,
    getType = function() return kind end})
end

local module = dofile('hammerspoon/keyboard/remote-input-source.lua')
assert(module.tap == tap and enabled)
assert(key(79, 1) and selectedSource == 'com.apple.keylayout.ABC')
assert(key(80, 1) and selectedSource == 'com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese')
selectedSource = nil
assert(key(80, 2) and selectedSource == nil)
assert(not key(0, 1))
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
print('PASS: input switching, Jump passthrough, wake/unlock, Secure Input, startup retries')
