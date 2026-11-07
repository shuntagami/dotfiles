-- Repair a live session through Jump Desktop 10's own display preset.
-- No connection files are written and the viewer is not restarted.
on run argv
    if (count of argv) is not 1 then error "接続名を1つ指定してください。"
    set targetName to item 1 of argv

    tell application "System Events"
        if not (exists process "Jump Desktop") then error "MacBookでJump Desktopを起動し、Mac miniに接続してから実行してください。"
        tell process "Jump Desktop"
            set targets to windows whose name is targetName
            if (count of targets) is not 1 then error "接続ウィンドウ「" & targetName & "」が1つ必要です。Mac miniに接続し、ダイアログを閉じてから実行してください。"
            set targetWindow to item 1 of targets
            set wasFullscreen to value of attribute "AXFullScreen" of targetWindow
            if not (exists menu item "Single Virtual Display" of menu "Display" of menu bar 1) then error "Jump Desktop 10のDisplayメニューが必要です。"
            if not (exists menu item "Fit In Window" of menu "View" of menu bar 1) then error "Jump DesktopのView > Fit In Windowが見つかりません。"

            perform action "AXRaise" of targetWindow
            set frontmost to true
            delay 0.2
            click menu item "Single Virtual Display" of menu "Display" of menu bar 1
        end tell
    end tell

    -- Applying the preset can recreate the session window asynchronously.
    set ready to false
    repeat 40 times
        delay 0.25
        tell application "System Events" to tell process "Jump Desktop"
            try
                set targets to windows whose name is targetName
                if (count of targets) is 1 then
                    set displayLabels to name of every menu item of menu "Display" of menu bar 1
                    repeat with labelText in displayLabels
                        if labelText is not missing value and (labelText as text) ends with " Virtual" then set ready to true
                    end repeat
                end if
            end try
        end tell
        if ready then exit repeat
    end repeat
    if not ready then error "仮想ディスプレイを確認できませんでした。接続状態とDisplayメニューを確認してください。"

    tell application "System Events" to tell process "Jump Desktop"
        set targetWindow to item 1 of (windows whose name is targetName)
        perform action "AXRaise" of targetWindow
        click menu item "Fit In Window" of menu "View" of menu bar 1
        if wasFullscreen and not (value of attribute "AXFullScreen" of targetWindow) then
            click menu item "Fullscreen" of menu "View" of menu bar 1
        end if
    end tell
    delay 1

    tell application "System Events" to tell process "Jump Desktop"
        tell menu "Display" of menu bar 1
            if (value of attribute "AXMenuItemMarkChar" of menu item "Match Display Resolution") is missing value then error "解像度追従が有効になっていません。Displayメニューを確認してください。"
            if (value of attribute "AXMenuItemMarkChar" of menu item "Use Retina Resolution") is missing value then error "Retina設定が有効になっていません。Displayメニューを確認してください。"
            set displayLabels to name of every menu item
        end tell
    end tell
    set virtualLabel to ""
    repeat with labelText in displayLabels
        if labelText is not missing value and (labelText as text) ends with " Virtual" then set virtualLabel to labelText as text
    end repeat
    if virtualLabel is "" then error "調整後の仮想ディスプレイを確認できませんでした。"
    return "表示の自動調整を再適用しました: " & targetName & " / " & virtualLabel
end run
