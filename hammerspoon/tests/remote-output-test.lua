-- Run from the repository root: lua hammerspoon/tests/remote-output-test.lua
local output, effects, poll
local writes, fail = 0, false
local function device(name, uid)
  return {
    name = function() return name end,
    uid = function() return uid end,
    setDefaultEffectDevice = function(self)
      writes = writes + 1
      if fail then return false end
      effects = self
      return true
    end,
  }
end
local jump = device('Jump Desktop Audio', 'jump')
local monitor = device('Monitor', 'monitor')
local speakers = device('Speakers', 'speakers')
hs = {
  audiodevice = {
    defaultOutputDevice = function() return output end,
    defaultEffectDevice = function() return effects end,
  },
  timer = {doEvery = function(_, callback) poll = callback; return {} end},
}
output, effects = jump, monitor
dofile('hammerspoon/audio/remote-output.lua')
assert(effects == jump and writes == 1, 'route effects at login')
poll()
assert(writes == 1, 'do not rewrite an unchanged route')
effects = monitor
poll()
assert(effects == jump, 'recover an effects route reset after wake')
output = speakers
poll()
assert(effects == speakers, 'restore local effects after Jump disconnects')
effects = monitor
local before = writes
poll()
assert(effects == monitor and writes == before, 'preserve unrelated local routes')
output = nil
poll()
assert(writes == before, 'tolerate missing devices')
output, effects, fail = jump, nil, true
poll()
assert(effects == nil)
fail = false
poll()
assert(effects == jump, 'retry after devices become ready')
assert(output == jump, 'never change regular audio output')
print('PASS: login, wake, disconnect, local preferences, missing devices, retries')
