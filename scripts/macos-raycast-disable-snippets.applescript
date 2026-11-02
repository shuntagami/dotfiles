-- Only disable expansion. Leave the launcher and existing links available.
on findControl(e, wantedRole, wantedLabel)
 tell application "System Events"
  try
   set r to role of e as text
   if r is wantedRole then
    set n to name of e as text
    if n is "" or n is "missing value" then set n to description of e as text
    if n is wantedLabel then return e
   end if
  end try
  set children to UI elements of e
 end tell
 repeat with childNode in children
  set found to my findControl(contents of childNode, wantedRole, wantedLabel)
  if found is not missing value then return found
 end repeat
 return missing value
end findControl

on run
 tell application "Raycast" to activate
 tell application "System Events" to tell process "Raycast"
  set frontmost to true
  keystroke "," using command down
 end tell
 repeat 30 times
  tell application "System Events" to tell process "Raycast"
   if exists window "Settings" then exit repeat
  end tell
  delay 0.1
 end repeat
 tell application "System Events" to tell process "Raycast" to set w to window "Settings"
 set sectionLink to my findControl(w, "AXLink", "Snippets")
 if sectionLink is missing value then error "Open Raycast Settings > Snippets and disable Enable Snippet Expansion."
 tell application "System Events" to perform action "AXPress" of sectionLink
 delay 0.2
 set expansionSwitch to my findControl(w, "AXCheckBox", "Enable Snippet Expansion")
 if expansionSwitch is missing value then error "Raycast snippet expansion switch unavailable."
 tell application "System Events"
  if (value of expansionSwitch as integer) is 1 then perform action "AXPress" of expansionSwitch
 end tell
 delay 0.2
 set expansionSwitch to my findControl(w, "AXCheckBox", "Enable Snippet Expansion")
 tell application "System Events"
  if (value of expansionSwitch as integer) is not 0 then error "Raycast snippet expansion is still enabled."
 end tell
 return "Raycast snippet expansion is off."
end run
