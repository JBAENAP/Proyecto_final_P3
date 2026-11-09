@echo off
REM Abre una TERMINAL DE USUARIO conectada al servidor (nodo clienteN@<equipo>).
REM Ejecute este archivo en tantas terminales como usuarios quiera simular.
chcp 65001 >nul
cd /d "%~dp0"
mix cliente
