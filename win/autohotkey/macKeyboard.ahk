;-----------------------------------------
; Mac keyboard to Windows Key Mappings
;=========================================

; --------------------------------------------------------------
; NOTES
; --------------------------------------------------------------
; ! = ALT
; ^ = CTRL
; + = SHIFT
; # = WIN
;
; Debug action snippet: MsgBox You pressed Control-A while Notepad is active.

; --------------------------------------------------------------
; Mac-like screenshots in Windows (requires Windows 10 Snip & Sketch)
; --------------------------------------------------------------

; Capture entire screen with CMD/WIN + SHIFT + 3
$!+3::Send("#{PrintScreen}")

; Capture portion of the screen with CMD/WIN + SHIFT + 4
$!+4::Send("+#s")

; --------------------------------------------------------------
; media/function keys all mapped to the right option key
; --------------------------------------------------------------

;RAlt & F7::Send("{Media_Prev}")
;RAlt & F8::Send("{Media_Play_Pause}")
;RAlt & F9::Send("{Media_Next}")
;F10::Send("{Volume_Mute}")
;F11::Send("{Volume_Down}")
;F12::Send("{Volume_Up}")

; swap left command/windows key with left alt
;LWin::LAlt
;LAlt::LWin ; add a semicolon in front of this line if you want to disable the windows key

; Remap Windows + Left OR Right to enable previous or next web page
; Use only if swapping left command/windows key with left alt
;Lwin & Left::Send("!{Left}")
;Lwin & Right::Send("!{Right}")

; Eject Key
;F20::Send("{Insert}") ; F20 doesn't show up on AHK anymore, see #3

; F13-15, standard windows mapping
;F13::Send("{PrintScreen}")
;F14::Send("{ScrollLock}")
;F15::Send("{Pause}")

;F16-19 custom app launchers, see http://www.autohotkey.com/docs/Tutorial.htm for usage info
;F16::Run("http://twitter.com")
;F17::Run("http://tumblr.com")
;F18::Run("http://www.reddit.com")
;F19::Run("https://facebook.com")

; --------------------------------------------------------------
; OS X system shortcuts
; --------------------------------------------------------------

; Make Ctrl + S work with cmd (windows) key
$!s::Send("^s")

; Selecting
$!a::Send("^a")

; Copying
$!c::Send("^c")

; Pasting
$!v::Send("^v")

; Cutting
$!x::Send("^x")

; Opening
$!o::Send("^o")

; Finding
$!f::Send("^f")

; Undo
$!z::Send("^z")

; Redo
$!y::Send("^y")

; New tab
$!t::Send("^t")

; close tab
$!w::Send("^w")

; Reload
$!r::Send("^r")
$!+r::Send("^+r")

; Close windows (cmd + q to Alt + F4)
$!q::Send("!{F4}")

; Send msg with cmd + Enter or cmd + shift + Enter
$!Enter::Send("^{Enter}")
$!+Enter::Send("^+{Enter}")

; minimize windows
$!m::WinMinimize("A")

; bind the arrow keys to alt+hjkl
$!h::Send("{left}")
$!j::Send("{down}")
$!k::Send("{up}")
$!l::Send("{right}")

; --------------------------------------------------------------
; OS X keyboard mappings for special chars
; --------------------------------------------------------------

; Map Alt + L to @
;!l::Send("{@}")

; Map Alt + N to \
;+!7::Send("{\}")

; Map Alt + N to ©
;!g::Send("{©}")

; Map Alt + o to ø
;!o::Send("{ø}")

; Map Alt + 5 to [
;!5::Send("{[}")

; Map Alt + 6 to ]
;!6::Send("{]}")

; Map Alt + E to €
;!e::Send("{€}")

; Map Alt + - to –
;!-::Send("{–}")

; Map Alt + 8 to {
;!8::Send("{{}")

; Map Alt + 9 to }
;!9::Send("{}")

; Map Alt + - to ±
;!+::Send("{±}")

; Map Alt + R to ®
;!r::Send("{®}")

; Map Alt + N to |
;!7::Send("{|}")

; Map Alt + W to ∑
;!w::Send("{∑}")

; Map Alt + N to ~
;!n::Send("{~}")

; Map Alt + 3 to #
;!3::Send("{#}")

; --------------------------------------------------------------
; Custom mappings for special chars
; --------------------------------------------------------------

;#ö::Send("{[}")
;#ä::Send("{]}")

;^ö::Send("{{}")
;^ä::Send("{}")

; --------------------------------------------------------------
; Application specific
; --------------------------------------------------------------

; Google Chrome
#HotIf WinActive("ahk_class Chrome_WidgetWin_1")

; Show Web Developer Tools with cmd + alt + i
#!i::Send("{F12}")

; Show source code with cmd + alt + u
#!u::Send("^u")

#HotIf
