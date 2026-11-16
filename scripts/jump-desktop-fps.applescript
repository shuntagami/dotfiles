-- Use the live menu so changes apply without restarting or disconnecting.
on run argv
    if (count of argv) is not 1 then error "status・60・30・auto のいずれかを指定してください。"
    set mode to item 1 of argv
    if mode is not in {"status", "60", "30", "auto"} then error "status・60・30・auto のいずれかを指定してください。"

    tell application "System Events"
        if not (exists process "Jump Desktop") then error "MacBookでJump Desktopを起動し、接続してから実行してください。"
    end tell
    tell application "Jump Desktop" to activate
    delay 0.2

    tell application "System Events" to tell process "Jump Desktop"
        -- Refuse ambiguous sessions/dialogs rather than changing another connection.
        set sessions to windows whose name is not "Jump Desktop"
        if (count of sessions) is not 1 then error "Jump Desktopの接続ウィンドウを1つにし、設定画面やダイアログを閉じてください。"
        set sessionName to name of item 1 of sessions
        perform action "AXRaise" of item 1 of sessions
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
