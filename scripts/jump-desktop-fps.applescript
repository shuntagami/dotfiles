-- Use the live menu so changes apply without restarting or disconnecting.
on run argv
    if (count of argv) is not 1 then error "status・60・30・auto のいずれかを指定してください。"
    set mode to item 1 of argv
    if mode is not in {"status", "60", "30", "auto"} then error "status・60・30・auto のいずれかを指定してください。"

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
        set sessionNames to {}
        -- AppKit appends window titles after the final separator.
        repeat with entry in menu items of windowMenu
            set labelText to name of entry
            if labelText is missing value then
                set sessionNames to {}
            else if labelText is not "Jump Desktop" then
                set end of sessionNames to labelText as text
            end if
        end repeat
        if (count of sessionNames) is 0 then error "Jump Desktopの接続が見つかりません。MacBookで接続してから実行してください。"
        if (count of sessionNames) is not 1 then error "接続先を1つにし、設定画面やダイアログを閉じてください。Windowメニューの候補: " & (sessionNames as text)
        set sessionName to item 1 of sessionNames
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
        if not (exists menu item "Framerate" of menu "Remote" of menu bar 1) then error "接続中のRemote > Framerateが見つかりません。Fluid接続を確認してください。"
        set fpsMenu to menu 1 of menu item "Framerate" of menu "Remote" of menu bar 1

        if mode is not "status" then
            if mode is "auto" then
                set targetLabel to "Auto"
            else
                set targetLabel to mode & " fps"
            end if
            if not (exists menu item targetLabel of fpsMenu) then error "Framerateに「" & targetLabel & "」がありません。"
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
