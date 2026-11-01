// a11y (plan 2026-10-31, F19/F20/H3): Windows' accessibility settings that ii follows.
//   ii-shim a11y   JSON: {"highContrast":false,"textScale":1.25,"animations":true,
//                         "colors":{"window":"#000000","windowText":"#ffffff","highlight":"#1aebff",
//                                   "highlightText":"#000000","grayText":"#3ff23f","hotlight":"#ffff00","buttonFace":"#000000"}}
// highContrast: a contrast theme is on (Configuración > Accesibilidad > Temas de contraste); colors are that theme's.
// textScale: Accesibilidad > Tamaño del texto (HKCU\Software\Microsoft\Accessibility\TextScaleFactor, 100–225 %).
// animations: Accesibilidad > Efectos visuales > Efectos de animación (SPI_GETCLIENTAREAANIMATION).
#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "user32.lib")

namespace {

std::string hex(int index) {
	const auto c = GetSysColor(index);
	char out[8];
	std::snprintf(out, sizeof(out), "#%02x%02x%02x", GetRValue(c), GetGValue(c), GetBValue(c));
	return out;
}

} // namespace

int a11y(const std::vector<std::wstring>&) {
	HIGHCONTRASTW contrast {};
	contrast.cbSize = sizeof(contrast);
	const bool high = SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0) && (contrast.dwFlags & HCF_HIGHCONTRASTON);
	BOOL animations = TRUE;
	if (!SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0)) animations = TRUE;
	DWORD scale = 100, size = sizeof(scale);
	if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Accessibility", L"TextScaleFactor", RRF_RT_REG_DWORD, nullptr, &scale, &size) != ERROR_SUCCESS)
		scale = 100;
	if (scale < 100 || scale > 225) scale = 100;
	char number[16];
	std::snprintf(number, sizeof(number), "%.2f", scale / 100.0);
	std::string out = std::string("{\"highContrast\":") + (high ? "true" : "false") + ",\"textScale\":" + number +
	                  ",\"animations\":" + (animations ? "true" : "false") + ",\"colors\":{\"window\":\"" + hex(COLOR_WINDOW) +
	                  "\",\"windowText\":\"" + hex(COLOR_WINDOWTEXT) + "\",\"highlight\":\"" + hex(COLOR_HIGHLIGHT) +
	                  "\",\"highlightText\":\"" + hex(COLOR_HIGHLIGHTTEXT) + "\",\"grayText\":\"" + hex(COLOR_GRAYTEXT) +
	                  "\",\"hotlight\":\"" + hex(COLOR_HOTLIGHT) + "\",\"buttonFace\":\"" + hex(COLOR_BTNFACE) + "\"}}\n";
	std::fputs(out.c_str(), stdout);
	return 0;
}
