@echo off
set /p TOKEN=Cole o token do PixelLab (comeca com pixl_) e aperte Enter: 
claude mcp remove pixellab >nul 2>&1
claude mcp add --transport http --header "Authorization: Bearer %TOKEN%" pixellab https://api.pixellab.ai/mcp
set TOKEN=
echo.
claude mcp list
pause
