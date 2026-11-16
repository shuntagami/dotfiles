-- Use the live menu so changes apply without restarting or disconnecting.
on windowNamesFrom(menuLabels)
    set windowNames to {}
    -- AppKit appends window titles after the final separator.
    repeat with labelText in menuLabels
        set labelText to contents of labelText
        if labelText is missing value then
            set windowNames to {}
        else if labelText is not "Jump Desktop" then
            set end of windowNames to labelText as text
        end if
    end repeat
    return windowNames
end windowNamesFrom

on isAdditionalDisplay(windowName, sessionName)
    set displayPrefix to sessionName & " - Display "
    if windowName does not start with displayPrefix then return false
    if (length of windowName) is not greater than (length of displayPrefix) then return false
    set displayNumber to text ((length of displayPrefix) + 1) thru -1 of windowName
    repeat with digit in characters of displayNumber
        if "0123456789" does not contain (digit as text) then return false
    end repeat
    return true
end isAdditionalDisplay

on chooseSession(windowNames, requestedName)
    set sessionNames to {}
    repeat with windowName in windowNames
        set windowName to windowName as text
        set additionalDisplay to false
        -- Only group a numbered display when its exact base title also exists.
        -- Keep unrelated titles (including settings) as ambiguous candidates.
        repeat with baseName in windowNames
            if my isAdditionalDisplay(windowName, baseName as text) then
                set additionalDisplay to true
                exit repeat
            end if
        end repeat
        if not additionalDisplay then set end of sessionNames to windowName
    end repeat
    if (count of sessionNames) is 0 then error "Jump Desktopの接続が見つかりません。MacBookで接続してから実行してください。"
    set candidateText to ""
    repeat with sessionName in sessionNames
        if candidateText is not "" then set candidateText to candidateText & ", "
        set candidateText to candidateText & "「" & (sessionName as text) & "」"
    end repeat
    if requestedName is not "" then
        if sessionNames contains requestedName then return requestedName
        error "接続先「" & requestedName & "」が見つかりません。候補: " & candidateText
    end if
    if (count of sessionNames) is not 1 then error "接続先を特定できません。jump-fps 30 '接続名' のように指定するか、設定画面やダイアログを閉じてください。候補: " & candidateText
    return item 1 of sessionNames
end chooseSession

on statsTextFor(sessionName)
    tell application "System Events" to tell process "Jump Desktop"
        set textValues to value of every static text of window sessionName
    end tell
    repeat with textValue in textValues
        if textValue is not missing value then
            set textValue to textValue as text
            if textValue starts with "Frames" and textValue contains "Max Frames" then return textValue
        end if
    end repeat
    return ""
end statsTextFor

on toggleStats()
    tell application "System Events" to tell process "Jump Desktop"
        -- The menu title stays 'Show ...' even when the overlay is visible.
        click menu item "Show Fluid Connection Stats" of menu "Help" of menu bar 1
    end tell
end toggleStats

on readStats(sessionName)
    set statsText to my statsTextFor(sessionName)
    if statsText is not "" then return statsText

    my toggleStats()
    try
        -- Statistics update once a second. Wait for a fresh sample after enabling.
        delay 1.1
        repeat 20 times
            set statsText to my statsTextFor(sessionName)
            if statsText is not "" then exit repeat
            delay 0.1
        end repeat
        if statsText is "" then error "接続統計を取得できませんでした。Jump Desktopの接続状態を確認してください。"
    on error errorMessage number errorNumber
        my toggleStats()
        error errorMessage number errorNumber
    end try
    my toggleStats()
    return statsText
end readStats

on run argv
    if (count of argv) < 1 or (count of argv) > 2 then error "status・stats・rates・auto・fps値と、必要なら接続名を指定してください。"
    set mode to item 1 of argv
    set requestedName to ""
    if (count of argv) is 2 then
        set requestedName to item 2 of argv
        if requestedName is "" then error "接続名を空にはできません。"
    end if

    tell application "System Events"
        if not (exists process "Jump Desktop") then error "MacBookでJump Desktopを起動し、接続してから実行してください。"
    end tell
    tell application "System Events" to tell process "Jump Desktop"
        -- Application.activate can open the Computers window and move away from
        -- a fullscreen session. Focus the process, then select the session via
        -- Window, which also lists windows on other Spaces.
        set frontmost to true
        delay 0.2
        set windowMenu to menu "Window" of menu bar 1
        set windowNames to my windowNamesFrom(name of every menu item of windowMenu)
        set sessionName to my chooseSession(windowNames, requestedName)
        click menu item sessionName of windowMenu
        set ready to false
        repeat 30 times
            set sessions to windows whose name is sessionName and subrole is "AXStandardWindow"
            if (count of sessions) is 1 then
                perform action "AXRaise" of item 1 of sessions
                set ready to true
                exit repeat
            end if
            delay 0.1
        end repeat
        if not ready then error "接続画面「" & sessionName & "」を表示できませんでした。"
        if mode is "stats" then
            set statsText to my readStats(sessionName)
            return "Jump Desktop [" & sessionName & "]" & linefeed & statsText
        end if
        if not (exists menu item "Framerate" of menu "Remote" of menu bar 1) then error "接続中のRemote > Framerateが見つかりません。Fluid接続を確認してください。"
        set fpsMenu to menu 1 of menu item "Framerate" of menu "Remote" of menu bar 1
        set availableRates to ""
        repeat with entry in menu items of fpsMenu
            set labelText to name of entry
            if labelText is not missing value then
                if labelText is "Auto" or labelText ends with " fps" then
                    if availableRates is not "" then set availableRates to availableRates & ", "
                    set availableRates to availableRates & labelText
                end if
            end if
        end repeat
        if mode is "rates" then return availableRates

        if mode is not "status" then
            if mode is "auto" then
                set targetLabel to "Auto"
            else
                set targetLabel to mode & " fps"
            end if
            if not (exists menu item targetLabel of fpsMenu) then error "「" & targetLabel & "」は選択できません。利用可能: " & availableRates
            if not (enabled of menu item targetLabel of fpsMenu) then error "Framerateを変更できません。接続状態を確認してください。"
            click menu item targetLabel of fpsMenu
        end if

        repeat 20 times
            set selectedLabel to ""
            repeat with entry in menu items of fpsMenu
                set mark to value of attribute "AXMenuItemMarkChar" of entry
                if mark is not missing value and mark is not "" then
                    set selectedLabel to name of entry
                    exit repeat
                end if
            end repeat
            if mode is "status" then exit repeat
            if selectedLabel is targetLabel then exit repeat
            delay 0.1
        end repeat
        if selectedLabel is "" then error "現在のFramerate設定を取得できませんでした。"
        if mode is not "status" then
            if selectedLabel is not targetLabel then error "Framerateの変更を確認できませんでした。現在: " & selectedLabel
        end if
    end tell
    return "Jump Desktop [" & sessionName & "]: Framerate = " & selectedLabel
end run
