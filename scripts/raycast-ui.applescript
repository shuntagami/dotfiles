-- Raycast v2 UI adapter. Operates only on Raycast, using accessibility labels.
-- Only the bundled click helper is executed. No terminal UI, sign-in,
-- permission grants, or database access.
property inputHelperPath : ""

on uiName(e)
 tell application "System Events"
  try
   set n to name of e as text
   if n is "" or n is "missing value" then set n to description of e as text
   if n is "" or n is "missing value" then
    if (role of e as text) is "AXStaticText" then set n to value of e as text
   end if
   return n
  on error
   return ""
  end try
 end tell
end uiName

on findNodes(e, wantedRole, wantedName, prefixMatch, depth)
 if depth > 18 then return {}
 if depth is 0 and inputHelperPath is not "" then
  tell application "System Events" to set rootRole to role of e as text
  if rootRole is "AXWindow" then
   set prefixValue to "0"
   if prefixMatch then set prefixValue to "1"
   set commandText to (quoted form of inputHelperPath) & " --find-window " & (quoted form of my uiName(e)) & " " & (quoted form of wantedRole) & " " & (quoted form of wantedName) & " " & prefixValue
   set pathOutput to do shell script commandText
   set fastMatches to {}
   if pathOutput is "" then return fastMatches
   set oldDelimiters to AppleScript's text item delimiters
   try
    repeat with pathText in paragraphs of pathOutput
     set nodeRef to e
     if (contents of pathText) is not "root" then
      set AppleScript's text item delimiters to "."
      set indices to text items of (contents of pathText)
      repeat with childIndex in indices
       tell application "System Events" to set nodeRef to UI element (childIndex as integer) of nodeRef
      end repeat
     end if
     tell application "System Events" to set resolvedRole to role of nodeRef as text
     set resolvedName to my uiName(nodeRef)
     if wantedRole is not "any" and resolvedRole is not wantedRole then error "Raycast role changed during lookup"
     if wantedName is not "" and resolvedName is not wantedName and not (prefixMatch and resolvedName starts with wantedName) then error "Raycast label changed during lookup"
     set end of fastMatches to nodeRef
    end repeat
    set AppleScript's text item delimiters to oldDelimiters
    return fastMatches
   on error
    set AppleScript's text item delimiters to oldDelimiters
    error "Raycast UI changed during lookup; no action was applied"
   end try
  end if
 end if
 set matches to {}
 tell application "System Events"
  try
   set r to role of e as text
   set n to name of e as text
   if n is "" or n is "missing value" then set n to description of e as text
   if n is "" or n is "missing value" then
    if r is "AXStaticText" then set n to value of e as text
   end if
   if r is wantedRole or wantedRole is "any" then
    if wantedName is "" or n is wantedName or (prefixMatch and n starts with wantedName) then set end of matches to e
   end if
  end try
  try
   set children to UI elements of e
  on error
   set children to {}
  end try
 end tell
 repeat with childNode in children
  set matches to matches & my findNodes(contents of childNode, wantedRole, wantedName, prefixMatch, depth + 1)
 end repeat
 return matches
end findNodes

on raycastWindow(windowName)
 tell application "System Events" to tell process "Raycast"
  if exists window windowName then return window windowName
 end tell
 return missing value
end raycastWindow

on requireWindow(windowName)
 repeat 30 times
  set w to my raycastWindow(windowName)
  if w is not missing value then return w
  delay 0.1
 end repeat
 error "Raycast window unavailable: " & windowName
end requireWindow

on requireNode(w, roleName, labelText, prefixMatch)
 repeat 20 times
  set foundItems to my findNodes(w, roleName, labelText, prefixMatch, 0)
  if (count foundItems) > 0 then exit repeat
  delay 0.1
 end repeat
 if (count foundItems) is not 1 then error "Expected one Raycast control: " & labelText
 return item 1 of foundItems
end requireNode

on requireFrontmost()
 -- Raycast's launcher does not activate its app. Verify actual keyboard focus
 -- through AX rather than reactivating Settings and hiding the launcher.
 do shell script (quoted form of inputHelperPath) & " --focus"
end requireFrontmost

on pressNode(e)
 tell application "System Events" to perform action "AXPress" of e
 delay 0.1
end pressNode

on clickPoint(e, xFraction, rowHeight)
 tell application "System Events"
  try
   perform action "AXScrollToVisible" of e
  end try
  set p to position of e
  set s to size of e
  set x to (item 1 of p) + (item 1 of s) * xFraction
  set y to (item 2 of p) + rowHeight / 2
  set w to value of attribute "AXWindow" of e
  try
   perform action "AXRaise" of w
  end try
  set wp to position of w
  set ws to size of w
  if x < item 1 of wp or x > (item 1 of wp) + (item 1 of ws) or y < item 2 of wp or y > (item 2 of wp) + (item 2 of ws) then error "Raycast control is outside its window; no click was sent"
 end tell
 -- System Events can report a successful AXPress without opening WebKit menus.
 -- The bundled helper sends only this already-validated, in-window mouse click.
 do shell script (quoted form of inputHelperPath) & " " & x & " " & y
 delay 0.1
end clickPoint

on startRaycast()
 tell application "System Events"
  if not UI elements enabled then error "Allow your terminal app in macOS Accessibility, then rerun setup"
 end tell
 tell application "Raycast" to activate
 repeat 5 times
  set w to my raycastWindow("Welcome")
  if w is missing value then return
  if (do shell script (quoted form of inputHelperPath) & " --legal-check Welcome") is "required" then error "Complete Raycast's legal first-launch step yourself, then rerun setup"
  set buttons to my findNodes(w, "AXButton", "Open Raycast", false, 0)
  if (count buttons) is 0 then set buttons to my findNodes(w, "AXButton", "Continue", true, 0)
  if (count buttons) is not 1 then error "Complete the current Raycast first-launch step, then rerun setup"
  my pressNode(item 1 of buttons)
  delay 0.2
 end repeat
 if my raycastWindow("Welcome") is not missing value then error "Raycast onboarding did not finish"
end startRaycast

on openSettings()
 my startRaycast()
 tell application "System Events" to tell process "Raycast" to keystroke "," using command down
 return my requireWindow("Settings")
end openSettings

on section(sectionName)
 set w to my openSettings()
 my pressNode(my requireNode(w, "AXLink", sectionName, false))
 return my requireWindow("Settings")
end section

on setToggle(labelText, expectedValue)
 set w to my requireWindow("Settings")
 set e to my requireNode(w, "AXCheckBox", labelText, false)
 tell application "System Events" to set actualValue to value of e as integer
 if actualValue is not expectedValue then my pressNode(e)
 set e to my requireNode(my requireWindow("Settings"), "AXCheckBox", labelText, false)
 tell application "System Events" to set actualValue to value of e as integer
 if actualValue is not expectedValue then error "Could not verify Raycast switch: " & labelText
 return "verified " & labelText
end setToggle

on chooseOption(windowName, labelText, queryText, optionText, chooseLast)
 set w to my requireWindow(windowName)
 set buttonNode to my requireNode(w, "AXButton", labelText, false)
 my pressNode(buttonNode)
 set w to my requireWindow(windowName)
 set searches to my findNodes(w, "AXTextField", "Search…", false, 0)
 if (count searches) is 0 then
  my clickPoint(buttonNode, 0.5, 24)
  set searches to my findNodes(my requireWindow(windowName), "AXTextField", "Search…", false, 0)
 end if
 if (count searches) is not 1 then error "Raycast setting menu did not open: " & labelText
 my requireFrontmost()
 tell application "System Events" to set value of item 1 of searches to queryText
 delay 0.15
 set popupRoot to item 1 of searches
 repeat 12 times
  tell application "System Events"
   if (role of popupRoot as text) is "AXWebArea" then exit repeat
   set popupRoot to value of attribute "AXParent" of popupRoot
  end tell
 end repeat
 set choices to my findNodes(popupRoot, "AXStaticText", optionText, false, 0)
 if (count choices) is 0 then set choices to my findNodes(popupRoot, "any", optionText, false, 0)
 if (count choices) is 0 then error "Raycast setting option unavailable: " & optionText
 if chooseLast then
  set e to last item of choices
 else
  set e to item 1 of choices
 end if
 my clickPoint(e, 0.5, 18)
 if (count my findNodes(my requireWindow(windowName), "AXTextField", "Search…", false, 0)) is not 0 then error "Raycast setting menu did not close: " & labelText
 return "selected " & optionText
end chooseOption

on quicklinkRow(quicklinkName)
 set foundRows to my findNodes(my requireWindow("Settings"), "AXButton", quicklinkName & linefeed, true, 0)
 if (count foundRows) > 1 then error "Duplicate Quicklink title; resolve duplicates before setup: " & quicklinkName
 if (count foundRows) is 0 then return missing value
 return item 1 of foundRows
end quicklinkRow

on setAlias(quicklinkName, aliasText)
 set rowNode to my quicklinkRow(quicklinkName)
 if rowNode is missing value then error "Quicklink missing: " & quicklinkName
 set wantedLabel to "Edit Alias for " & quicklinkName & ": " & aliasText
 if my uiName(rowNode) contains wantedLabel then return "verified alias " & aliasText
 -- Raycast merges the row's alias field into one AX button. In v2, the
 -- alias column is at 59% of the row width. Verify the editor before typing.
 -- AXSize.height is cumulative in this view; use the 46-point row height.
 my clickPoint(rowNode, 0.59, 46)
 my requireFrontmost()
 set rowNode to my quicklinkRow(quicklinkName)
 if my uiName(rowNode) does not contain (linefeed & "Alias for " & quicklinkName & linefeed) then error "Raycast alias editor did not open; no text was entered"
 tell application "System Events" to tell process "Raycast"
  keystroke "a" using command down
  keystroke aliasText
  key code 36
 end tell
 if my uiName(my quicklinkRow(quicklinkName)) does not contain wantedLabel then error "Could not verify alias: " & quicklinkName
 return "verified alias " & aliasText
end setAlias

on openCommand(commandName)
 -- Reopen the launcher, then select a qualified built-in command. This also
 -- avoids relying on old/new Quicklinks deeplink aliases across Raycast v2.
 set settingsPanel to my raycastWindow("Settings")
 if settingsPanel is not missing value then
  tell application "System Events" to perform action "AXPress" of (value of attribute "AXCloseButton" of settingsPanel)
 end if
 do shell script "/usr/bin/open -a Raycast"
 set w to my requireWindow("Main Window")
 repeat 6 times
  set searches to my findNodes(w, "AXTextField", "Search for apps or commands", true, 0)
  if (count searches) is 1 then exit repeat
  my pressNode(my requireNode(w, "AXButton", "Back", false))
  set w to my requireWindow("Main Window")
 end repeat
 if (count searches) is not 1 then error "Raycast root search unavailable"
 my clickPoint(item 1 of searches, 0.5, 20)
 tell application "System Events" to set value of item 1 of searches to commandName
 delay 0.2
 set w to my requireWindow("Main Window")
 set commandNodes to my findNodes(w, "AXStaticText", commandName, false, 0)
 if (count commandNodes) is not 1 then error "Expected one built-in Quicklinks command; nothing was launched"
 set commandParent to item 1 of commandNodes
 set qualifiedCommand to false
 repeat 4 times
  tell application "System Events" to set commandParent to value of attribute "AXParent" of commandParent
  if (count my findNodes(commandParent, "AXStaticText", "Quicklinks", false, 0)) > 0 and (count my findNodes(commandParent, "AXStaticText", "Command", false, 0)) > 0 then
   set qualifiedCommand to true
   exit repeat
  end if
 end repeat
 if not qualifiedCommand then error "Qualified Quicklinks command not found; nothing was launched"
 my clickPoint(item 1 of commandNodes, 0.5, 20)
 set w to my requireWindow("Main Window")
 if (count my findNodes(w, "AXTextField", "Search for apps or commands", true, 0)) is 1 then
  my requireFrontmost()
  tell application "System Events" to tell process "Raycast" to key code 36
 end if
end openCommand

on updateQuicklink(quicklinkName, linkURL, appName)
 my openCommand("Search Quicklinks")
 set w to my requireWindow("Main Window")
 set searchNode to my requireNode(w, "AXTextField", "Search for Quicklinks", true)
 my clickPoint(searchNode, 0.5, 20)
 my requireFrontmost()
 tell application "System Events" to set value of searchNode to quicklinkName
 delay 0.2
 tell application "System Events" to tell process "Raycast" to keystroke "e" using command down
 delay 0.2
 set w to my requireWindow("Main Window")
 set nameNode to my requireNode(w, "AXTextField", "Name & Icon", false)
 tell application "System Events" to set currentName to value of nameNode as text
 if currentName is not quicklinkName then error "Selected Quicklink does not match; nothing was edited"
 set linkNode to my requireNode(w, "AXTextArea", "Link", false)
 tell application "System Events"
  try
   set value of linkNode to linkURL
  on error
   error "Could not set Quicklink URL"
  end try
 end tell
 if appName is "default" then
  my chooseOption("Main Window", "Open With", "default", "Google Chrome", false)
 else
  my chooseOption("Main Window", "Open With", appName, appName, true)
 end if
 set w to my requireWindow("Main Window")
 set buttons to my findNodes(w, "AXButton", "Update Quicklink", true, 0)
 if (count buttons) is 0 then error "Quicklink save control unavailable"
 my pressNode(last item of buttons)
 set w to my requireWindow("Main Window")
 if (count my findNodes(w, "AXTextField", "Name & Icon", false, 0)) > 0 then error "Quicklink editor did not close"
 if (count my findNodes(w, "AXStaticText", linkURL, false, 0)) is 0 then error "Saved Quicklink URL could not be verified"
 return "verified Quicklink " & quicklinkName
end updateQuicklink

on importQuicklinksFile(filePath)
 my openCommand("Import Quicklinks")
 set w to my requireWindow("Main Window")
 set selectButtons to my findNodes(w, "AXButton", "Select file", true, 0)
 if (count selectButtons) is not 1 then error "Quicklinks file picker unavailable"
 my pressNode(item 1 of selectButtons)
 my requireFrontmost()
 tell application "System Events" to tell process "Raycast"
  keystroke "g" using {command down, shift down}
  delay 0.2
  keystroke filePath
  key code 36
  delay 0.2
  key code 36
 end tell
 return my waitImportResult("Quicklink")
end importQuicklinksFile

on confirmImport(kindName)
 set w to my requireWindow("Main Window")
 set candidates to my findNodes(w, "AXButton", "Import ", true, 0)
 set importButton to missing value
 repeat with e in candidates
  set n to my uiName(contents of e)
  try
   set importCount to word 2 of n as integer
   if n contains kindName then set importButton to contents of e
  end try
 end repeat
 if importButton is missing value then error "Raycast import confirmation unavailable: " & kindName
 my pressNode(importButton)
 return my waitImportResult(kindName)
end confirmImport

on waitImportResult(kindName)
 repeat 30 times
  set w to my requireWindow("Main Window")
  if (count my findNodes(w, "AXButton", "Import successful", false, 0)) is 1 then
   set countsText to do shell script (quoted form of inputHelperPath) & " --import-counts " & (quoted form of "Main Window")
   return "verified import " & kindName & "|" & countsText
  end if
  delay 0.1
 end repeat
 error "Could not verify successful Raycast import: " & kindName
end waitImportResult

on run argv
 set inputHelperPath to system attribute "RAYCAST_SETUP_INPUT_HELPER"
 if inputHelperPath is "" then error "Missing Raycast native input helper"
 set commandName to item 1 of argv
 if commandName is not "start" and commandName is not "restart" and commandName is not "import" and commandName is not "quicklink" and commandName is not "import-file" then
  tell application "System Events" to tell process "Raycast" to set frontmost to true
 end if
 if commandName is "import" then
  set mainPanel to my requireWindow("Main Window")
  tell application "System Events" to perform action "AXRaise" of mainPanel
 end if
 if commandName is "start" then
  my startRaycast()
  return "Raycast ready"
 else if commandName is "restart" then
  tell application "Raycast" to quit
  repeat 40 times
   tell application "System Events" to set stillRunning to exists process "Raycast"
   if not stillRunning then exit repeat
   delay 0.1
  end repeat
  if stillRunning then error "Raycast did not quit; setup stopped"
  my startRaycast()
  return "Raycast restarted to reload permissions"
 else if commandName is "section" then
  my section(item 2 of argv)
  return "opened " & item 2 of argv
 else if commandName is "toggle" then
  return my setToggle(item 2 of argv, item 3 of argv as integer)
 else if commandName is "choose" then
  return my chooseOption("Settings", item 2 of argv, item 3 of argv, item 3 of argv, false)
 else if commandName is "spotlight" then
  -- The caller temporarily enables only Spotlight's known Cmd+Space binding.
  -- Remount General so Raycast refreshes native shortcut availability.
  my section("Snippets")
  set w to my section("General")
  repeat 15 times
   set matches to my findNodes(w, "AXButton", "Replace Spotlight", false, 0)
   if (count matches) is 1 then exit repeat
   delay 0.2
   set w to my requireWindow("Settings")
  end repeat
  if (count matches) is not 1 then error "Replace Spotlight control unavailable"
  my pressNode(item 1 of matches)
  if (count my findNodes(my requireWindow("Settings"), "AXButton", "Replace Spotlight", false, 0)) is not 0 then error "Could not verify Spotlight replacement"
  return "verified Spotlight replacement"
 else if commandName is "alias" then
  return my setAlias(item 2 of argv, item 3 of argv)
 else if commandName is "quicklink-present" then
  set foundRows to my findNodes(my requireWindow("Settings"), "AXButton", (item 2 of argv) & linefeed, true, 0)
  if (count foundRows) > 1 then error "Duplicate Quicklink title; resolve duplicates before setup"
  if (count foundRows) is 0 then return "missing"
  return "present"
 else if commandName is "quicklink" then
  return my updateQuicklink(item 2 of argv, item 3 of argv, item 4 of argv)
 else if commandName is "import-file" then
  return my importQuicklinksFile(item 2 of argv)
 else if commandName is "expansion-access" then
  set w to my requireWindow("Settings")
  if (count my findNodes(w, "AXButton", "Grant access in System Settings.", false, 0)) > 0 then return "required"
  return "ready"
 else if commandName is "request-access" then
  set w to my section("Snippets")
  set matches to my findNodes(w, "AXButton", "Grant access in System Settings.", false, 0)
  if (count matches) is 1 then my pressNode(item 1 of matches)
  -- Only request the OS permission UI. Never approve/grant it here.
  return "Raycast Accessibility approval is required in macOS"
 else if commandName is "import" then
  return my confirmImport(item 2 of argv)
 end if
 error "Unsupported Raycast UI operation"
end run
