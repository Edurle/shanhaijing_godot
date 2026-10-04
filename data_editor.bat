@echo off
rem Double-click to open the data editor (no need to open the Godot editor first)
start "" godot --path "%~dp0." scenes/data_editor.tscn
