@echo off
REM Inicia el SERVIDOR del sistema de emergencias (nodo servidor@<equipo>).
REM --sname tambien inicia epmd, que permite a las terminales cliente encontrarlo.
chcp 65001 >nul
cd /d "%~dp0"
elixir --sname servidor --cookie emergencias -S mix servidor
