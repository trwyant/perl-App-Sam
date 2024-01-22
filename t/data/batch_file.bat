@echo off
rem This is a comment
@REM so is this
:: and, by a strange quirk of fate, so is this.
set name=world
if .%1.==.. goto greet
set name=%1
:greet
echo Hello %name%!
