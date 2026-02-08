; --------------------------------------------------------------
; NOTES
; --------------------------------------------------------------
; ! = ALT
; ^ = CTRL
; + = SHIFT
; # = WIN

#Requires AutoHotkey v2.0

InstallKeybdHook
#SingleInstance force
SetTitleMatchMode(2)
SendMode("Input")

#include "macKeyboard.ahk"
#include "altIme.ahk" ; comment out this for JIS keyboard
