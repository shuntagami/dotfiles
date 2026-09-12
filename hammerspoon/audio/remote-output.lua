local jumpAudioName = 'Jump Desktop Audio'

local function syncRemoteEffects()
  local output = hs.audiodevice.defaultOutputDevice()
  local effects = hs.audiodevice.defaultEffectDevice()
  if not output then return end
  if effects and output:uid() == effects:uid() then return end

  -- Jump Connect changes the regular output, but system effects can remain
  -- assigned to the Mac's monitor/speakers across login and reconnection.
  if output:name() == jumpAudioName then
    output:setDefaultEffectDevice()
  elseif effects and effects:name() == jumpAudioName then
    -- When Jump restores local playback, don't strand notifications on its
    -- virtual device. Leave other local sound-effect preferences alone.
    output:setDefaultEffectDevice()
  end
end

syncRemoteEffects()

-- Retained by require(); also handles devices arriving late at login and
-- retries after wake or a failed device selection without forcing audio output.
return hs.timer.doEvery(2, syncRemoteEffects)
