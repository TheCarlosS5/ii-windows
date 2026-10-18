// switchwall: ii's scripts/colors/switchwall.sh for Windows. Sets the wallpaper in ii's config and
// writes the Material 3 palette ii reads (colors.json, the keys of its matugen template).
//
//   switchwall [--mode dark|light] [--type scheme-...|auto] [--image <file> | <file>]
//              [--noswitch] [--color [#rrggbb|clear]] [--palette-from <image>]
//   --palette-from: only the colors, from this picture (a live wallpaper's preview); nothing else changes.
//   --desktop-still <image> / --desktop-still-restore: Windows' wallpaper of the current virtual desktop shows
//   a still of the live wallpaper (so the desktop-switch gap looks alike), and goes back when it is gone.
//
// Colors come from Google's material-color-utilities (Celebi quantizer + Score + dynamic scheme),
// the algorithm ii uses through matugen / materialyoucolor. "auto" picks the scheme the way ii's
// scheme_for_image.py does (image colorfulness). With no wallpaper given, Windows' file dialog
// replaces kdialog; with a bare --color, Windows' color dialog replaces hyprpicker.

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cwctype>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <commdlg.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wincodec.h>
#include <wrl/client.h>

// clang-format off
#include <winrt/base.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
// clang-format on

#include "cpp/cam/hct.h"
#include "cpp/dynamiccolor/material_dynamic_colors.h"
#include "cpp/quantize/celebi.h"
#include "cpp/scheme/scheme_content.h"
#include "cpp/scheme/scheme_expressive.h"
#include "cpp/scheme/scheme_fidelity.h"
#include "cpp/scheme/scheme_fruit_salad.h"
#include "cpp/scheme/scheme_monochrome.h"
#include "cpp/scheme/scheme_neutral.h"
#include "cpp/scheme/scheme_rainbow.h"
#include "cpp/scheme/scheme_tonal_spot.h"
#include "cpp/scheme/scheme_vibrant.h"
#include "cpp/score/score.h"
#include "cpp/utils/utils.h"

using Microsoft::WRL::ComPtr;
using Args = std::vector<std::wstring>;
namespace mcu = material_color_utilities;
namespace json = winrt::Windows::Data::Json;

namespace {

std::wstring localAppData() {
	PWSTR path = nullptr;
	SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path);
	std::wstring result = path ? path : L"";
	CoTaskMemFree(path);
	return result;
}

std::wstring configPath() { return localAppData() + L"\\quickshell\\illogical-impulse\\config.json"; }
std::wstring colorsPath() { return localAppData() + L"\\quickshell\\State\\user\\generated\\colors.json"; }
// The palette's source color, like switchwall.sh's cache; ii-host themes Windows' accent from it.
std::wstring sourceColorPath() { return localAppData() + L"\\quickshell\\State\\user\\generated\\color.txt"; }

std::string readUtf8(const std::wstring& path) {
	std::string bytes;
	auto* file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
	if (file == INVALID_HANDLE_VALUE) return bytes;
	LARGE_INTEGER size {};
	GetFileSizeEx(file, &size);
	bytes.resize(static_cast<size_t>(size.QuadPart));
	DWORD read = 0;
	ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &read, nullptr);
	CloseHandle(file);
	bytes.resize(read);
	if (bytes.rfind("\xEF\xBB\xBF", 0) == 0) bytes.erase(0, 3);
	return bytes;
}

// Write next to the target and move over it, so ii never reads a half-written file.
bool writeUtf8(const std::wstring& path, const std::string& bytes) {
	auto slash = path.find_last_of(L'\\');
	if (slash != std::wstring::npos) SHCreateDirectoryExW(nullptr, path.substr(0, slash).c_str(), nullptr);
	auto temp = path + L".tmp";
	auto* file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
	if (file == INVALID_HANDLE_VALUE) return false;
	DWORD written = 0;
	WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr);
	CloseHandle(file);
	return MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING) != 0;
}

std::string toUtf8(const std::wstring& text) {
	auto size = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
	std::string out(static_cast<size_t>(size), '\0');
	WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), out.data(), size, nullptr, nullptr);
	return out;
}

std::wstring fromUtf8(const std::string& text) {
	auto size = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(size), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), out.data(), size);
	return out;
}

// --- ii's config.json ------------------------------------------------------------------------

json::JsonObject loadConfig() {
	json::JsonObject config;
	auto text = readUtf8(configPath());
	if (!text.empty()) json::JsonObject::TryParse(winrt::to_hstring(text), config);
	return config ? config : json::JsonObject();
}

json::JsonObject child(const json::JsonObject& parent, const wchar_t* name) {
	if (parent.HasKey(name) && parent.GetNamedValue(name).ValueType() == json::JsonValueType::Object) {
		return parent.GetNamedObject(name);
	}
	json::JsonObject created;
	parent.SetNamedValue(name, created);
	return created;
}

// Like child(), but read-only: a missing object is an empty one, not added to the config.
json::JsonObject existing(const json::JsonObject& parent, const wchar_t* name) {
	if (parent.HasKey(name) && parent.GetNamedValue(name).ValueType() == json::JsonValueType::Object) {
		return parent.GetNamedObject(name);
	}
	return json::JsonObject();
}

std::wstring getString(const json::JsonObject& parent, const wchar_t* name) {
	if (!parent.HasKey(name) || parent.GetNamedValue(name).ValueType() != json::JsonValueType::String) return {};
	return std::wstring(parent.GetNamedString(name));
}

// --- the wallpaper -------------------------------------------------------------------------

struct Image {
	UINT width = 0;
	UINT height = 0;
	std::vector<uint32_t> argb;
};

// Decoded and scaled to about 128x128 pixels in area, like ii's generator.
bool loadImage(const std::wstring& path, Image& out) {
	ComPtr<IWICImagingFactory> factory;
	ComPtr<IWICBitmapDecoder> decoder;
	ComPtr<IWICBitmapFrameDecode> frame;
	ComPtr<IWICBitmapScaler> scaler;
	ComPtr<IWICFormatConverter> converter;
	if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) return false;
	if (FAILED(factory->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))) {
		return false;
	}
	if (FAILED(decoder->GetFrame(0, &frame))) return false;
	UINT width = 0;
	UINT height = 0;
	frame->GetSize(&width, &height);
	if (width == 0 || height == 0) return false;
	constexpr double area = 128.0 * 128.0;
	auto scale = static_cast<double>(width) * height > area ? std::sqrt(area / (static_cast<double>(width) * height)) : 1.0;
	out.width = std::max(1u, static_cast<UINT>(std::lround(width * scale)));
	out.height = std::max(1u, static_cast<UINT>(std::lround(height * scale)));
	factory->CreateBitmapScaler(&scaler);
	scaler->Initialize(frame.Get(), out.width, out.height, WICBitmapInterpolationModeHighQualityCubic);
	factory->CreateFormatConverter(&converter);
	if (FAILED(converter->Initialize(scaler.Get(), GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom))) {
		return false;
	}
	out.argb.resize(static_cast<size_t>(out.width) * out.height);
	// 32bpp BGRA in memory is 0xAARRGGBB as a little-endian uint32: Argb as-is.
	return SUCCEEDED(converter->CopyPixels(nullptr, out.width * 4, static_cast<UINT>(out.argb.size() * 4), reinterpret_cast<BYTE*>(out.argb.data())));
}

mcu::Argb sourceColor(const Image& image) {
	std::vector<mcu::Argb> opaque;
	opaque.reserve(image.argb.size());
	for (auto pixel: image.argb) opaque.push_back(pixel | 0xFF000000u);
	auto quantized = mcu::QuantizeCelebi(opaque, 128);
	auto ranked = mcu::RankedSuggestions(quantized.color_to_count);
	return ranked.empty() ? 0xFF4285F4u : ranked.front();
}

// Hasler & Suesstrunk colorfulness, as in ii's scheme_for_image.py: grey-ish images get the
// neutral scheme, the rest tonal spot.
std::string schemeForImage(const Image& image) {
	if (image.argb.empty()) return "scheme-tonal-spot";
	double sumRg = 0, sumYb = 0, sqRg = 0, sqYb = 0;
	for (auto pixel: image.argb) {
		double r = (pixel >> 16) & 0xFF, g = (pixel >> 8) & 0xFF, b = pixel & 0xFF;
		auto rg = std::abs(r - g);
		auto yb = std::abs(0.5 * (r + g) - b);
		sumRg += rg;
		sumYb += yb;
		sqRg += rg * rg;
		sqYb += yb * yb;
	}
	auto n = static_cast<double>(image.argb.size());
	auto meanRg = sumRg / n, meanYb = sumYb / n;
	auto stdRg = std::sqrt(std::max(0.0, sqRg / n - meanRg * meanRg));
	auto stdYb = std::sqrt(std::max(0.0, sqYb / n - meanYb * meanYb));
	auto colorfulness = std::sqrt(stdRg * stdRg + stdYb * stdYb) + 0.3 * std::sqrt(meanRg * meanRg + meanYb * meanYb);
	return colorfulness < 40 ? "scheme-neutral" : "scheme-tonal-spot";
}

std::unique_ptr<mcu::DynamicScheme> makeScheme(const std::string& type, mcu::Argb source, bool dark) {
	auto hct = mcu::Hct(source);
	if (type == "scheme-content") return std::make_unique<mcu::SchemeContent>(hct, dark, 0.0);
	if (type == "scheme-expressive") return std::make_unique<mcu::SchemeExpressive>(hct, dark, 0.0);
	if (type == "scheme-fidelity") return std::make_unique<mcu::SchemeFidelity>(hct, dark, 0.0);
	if (type == "scheme-fruit-salad") return std::make_unique<mcu::SchemeFruitSalad>(hct, dark, 0.0);
	if (type == "scheme-monochrome") return std::make_unique<mcu::SchemeMonochrome>(hct, dark, 0.0);
	if (type == "scheme-neutral") return std::make_unique<mcu::SchemeNeutral>(hct, dark, 0.0);
	if (type == "scheme-rainbow") return std::make_unique<mcu::SchemeRainbow>(hct, dark, 0.0);
	if (type == "scheme-vibrant") return std::make_unique<mcu::SchemeVibrant>(hct, dark, 0.0);
	return std::make_unique<mcu::SchemeTonalSpot>(hct, dark, 0.0);
}

// Keys of ii's matugen template (dots/.config/matugen/templates/colors.json).
const std::vector<std::pair<const char*, std::function<mcu::DynamicColor()>>>& colorKeys() {
	using M = mcu::MaterialDynamicColors;
	static const std::vector<std::pair<const char*, std::function<mcu::DynamicColor()>>> keys = {
	    {"background", M::Background},
	    {"error", M::Error},
	    {"error_container", M::ErrorContainer},
	    {"inverse_on_surface", M::InverseOnSurface},
	    {"inverse_primary", M::InversePrimary},
	    {"inverse_surface", M::InverseSurface},
	    {"on_background", M::OnBackground},
	    {"on_error", M::OnError},
	    {"on_error_container", M::OnErrorContainer},
	    {"on_primary", M::OnPrimary},
	    {"on_primary_container", M::OnPrimaryContainer},
	    {"on_primary_fixed", M::OnPrimaryFixed},
	    {"on_primary_fixed_variant", M::OnPrimaryFixedVariant},
	    {"on_secondary", M::OnSecondary},
	    {"on_secondary_container", M::OnSecondaryContainer},
	    {"on_secondary_fixed", M::OnSecondaryFixed},
	    {"on_secondary_fixed_variant", M::OnSecondaryFixedVariant},
	    {"on_surface", M::OnSurface},
	    {"on_surface_variant", M::OnSurfaceVariant},
	    {"on_tertiary", M::OnTertiary},
	    {"on_tertiary_container", M::OnTertiaryContainer},
	    {"on_tertiary_fixed", M::OnTertiaryFixed},
	    {"on_tertiary_fixed_variant", M::OnTertiaryFixedVariant},
	    {"outline", M::Outline},
	    {"outline_variant", M::OutlineVariant},
	    {"primary", M::Primary},
	    {"primary_container", M::PrimaryContainer},
	    {"primary_fixed", M::PrimaryFixed},
	    {"primary_fixed_dim", M::PrimaryFixedDim},
	    {"scrim", M::Scrim},
	    {"secondary", M::Secondary},
	    {"secondary_container", M::SecondaryContainer},
	    {"secondary_fixed", M::SecondaryFixed},
	    {"secondary_fixed_dim", M::SecondaryFixedDim},
	    {"shadow", M::Shadow},
	    {"surface", M::Surface},
	    {"surface_bright", M::SurfaceBright},
	    {"surface_container", M::SurfaceContainer},
	    {"surface_container_high", M::SurfaceContainerHigh},
	    {"surface_container_highest", M::SurfaceContainerHighest},
	    {"surface_container_low", M::SurfaceContainerLow},
	    {"surface_container_lowest", M::SurfaceContainerLowest},
	    {"surface_dim", M::SurfaceDim},
	    {"surface_tint", M::SurfaceTint},
	    {"surface_variant", M::SurfaceVariant},
	    {"tertiary", M::Tertiary},
	    {"tertiary_container", M::TertiaryContainer},
	    {"tertiary_fixed", M::TertiaryFixed},
	    {"tertiary_fixed_dim", M::TertiaryFixedDim},
	};
	return keys;
}

std::string hex(mcu::Argb argb) {
	char buffer[8];
	std::snprintf(buffer, sizeof(buffer), "#%06x", argb & 0xFFFFFFu);
	return buffer;
}

bool parseHex(std::wstring text, mcu::Argb& out) {
	if (!text.empty() && text[0] == L'#') text.erase(0, 1);
	if (text.size() != 6 || text.find_first_not_of(L"0123456789abcdefABCDEF") != std::wstring::npos) return false;
	out = 0xFF000000u | static_cast<mcu::Argb>(std::wcstoul(text.c_str(), nullptr, 16));
	return true;
}

// Dark unless the current palette is light (ii decides the same way from the background).
bool currentlyDark() {
	auto text = readUtf8(colorsPath());
	json::JsonObject colors;
	if (text.empty() || !json::JsonObject::TryParse(winrt::to_hstring(text), colors)) return true;
	mcu::Argb background = 0;
	if (!parseHex(getString(colors, L"background"), background)) return true;
	double r = (background >> 16) & 0xFF, g = (background >> 8) & 0xFF, b = background & 0xFF;
	return (std::max({r, g, b}) + std::min({r, g, b})) / 2.0 / 255.0 < 0.5;
}

std::wstring pickWallpaper() {
	ComPtr<IFileOpenDialog> dialog;
	if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) return {};
	COMDLG_FILTERSPEC filter[] = {{L"Images", L"*.jpg;*.jpeg;*.png;*.webp;*.bmp;*.gif"}};
	dialog->SetFileTypes(1, filter);
	dialog->SetTitle(L"Choose wallpaper");
	PWSTR pictures = nullptr;
	if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Pictures, 0, nullptr, &pictures))) {
		auto start = std::wstring(pictures) + L"\\Wallpapers";
		if (GetFileAttributesW(start.c_str()) == INVALID_FILE_ATTRIBUTES) start = pictures;
		ComPtr<IShellItem> folder;
		if (SUCCEEDED(SHCreateItemFromParsingName(start.c_str(), nullptr, IID_PPV_ARGS(&folder)))) dialog->SetFolder(folder.Get());
		CoTaskMemFree(pictures);
	}
	if (FAILED(dialog->Show(nullptr))) return {};
	ComPtr<IShellItem> item;
	PWSTR path = nullptr;
	if (FAILED(dialog->GetResult(&item)) || FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) return {};
	std::wstring result = path;
	CoTaskMemFree(path);
	return result;
}

bool pickColor(mcu::Argb& out) {
	static COLORREF custom[16] = {};
	CHOOSECOLORW choose {};
	choose.lStructSize = sizeof(choose);
	choose.lpCustColors = custom;
	choose.Flags = CC_FULLOPEN | CC_ANYCOLOR;
	if (!ChooseColorW(&choose)) return false;
	out = 0xFF000000u | (GetRValue(choose.rgbResult) << 16) | (GetGValue(choose.rgbResult) << 8) | GetBValue(choose.rgbResult);
	return true;
}

// --- terminal colors (ii's generate_colors_material.py, --termscheme with --blend_bg_fg) ---

// ii's scripts/colors/terminal/scheme-base.json
const char* const TERM_DARK[16] = {"282828", "CC241D", "98971A", "D79921", "458588", "B16286", "689D6A", "A89984",
                                   "928374", "FB4934", "B8BB26", "FABD2F", "83A598", "D3869B", "8EC07C", "EBDBB2"};
const char* const TERM_LIGHT[16] = {"FDF9F3", "FF6188", "A9DC76", "FC9867", "FFD866", "F47FD4", "78DCE8", "333034",
                                    "121212", "FF6188", "A9DC76", "FC9867", "FFD866", "F47FD4", "78DCE8", "333034"};

mcu::Argb harmonize(mcu::Argb design, mcu::Argb source, double threshold, double harmony) {
	auto from = mcu::Hct(design);
	auto to = mcu::Hct(source);
	auto rotation = std::min(mcu::DiffDegrees(from.get_hue(), to.get_hue()) * harmony, threshold);
	auto hue = mcu::SanitizeDegreesDouble(from.get_hue() + rotation * mcu::RotationDirection(from.get_hue(), to.get_hue()));
	return mcu::Hct(hue, from.get_chroma(), from.get_tone()).ToInt();
}

mcu::Argb boost(mcu::Argb color, double chroma, double tone) {
	auto hct = mcu::Hct(color);
	return mcu::Hct(hct.get_hue(), hct.get_chroma() * chroma, hct.get_tone() * tone).ToInt();
}

struct TermProps {
	double harmony = 0.6; // ii's defaults (appearance.wallpaperTheming.terminalGenerationProps)
	double threshold = 100;
	double fgBoost = 0.35;
};

std::vector<mcu::Argb> terminalColors(const mcu::DynamicScheme& scheme, bool dark, bool monochrome, const TermProps& props) {
	const auto* base = dark ? TERM_DARK : TERM_LIGHT;
	auto key = mcu::MaterialDynamicColors::PrimaryPaletteKeyColor().GetArgb(scheme);
	std::vector<mcu::Argb> out;
	for (int i = 0; i < 16; ++i) {
		auto color = 0xFF000000u | static_cast<mcu::Argb>(std::strtoul(base[i], nullptr, 16));
		if (monochrome) out.push_back(color);
		else if (i == 0) out.push_back(boost(mcu::MaterialDynamicColors::SurfaceContainerLow().GetArgb(scheme), 1.2, 0.95));
		else if (i == 15) out.push_back(boost(mcu::MaterialDynamicColors::OnSurface().GetArgb(scheme), 3, 1));
		else out.push_back(boost(harmonize(color, key, props.threshold, props.harmony), 1, 1 + props.fgBoost * (dark ? 1 : -1)));
	}
	return out;
}

bool terminalFontInstalled() {
	constexpr wchar_t nerdFamily[] = L"JetBrainsMono Nerd Font";
	constexpr wchar_t nfFamily[] = L"JetBrainsMono NF";
	for (auto root: {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
		HKEY key = nullptr;
		if (RegOpenKeyExW(root, L"Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts", 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) continue;
		DWORD maxName = 0;
		if (RegQueryInfoKeyW(key, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, &maxName, nullptr, nullptr, nullptr) != ERROR_SUCCESS) {
			RegCloseKey(key);
			continue;
		}
		std::vector<wchar_t> name(static_cast<size_t>(maxName) + 1);
		bool found = false;
		for (DWORD i = 0;; ++i) {
			DWORD length = static_cast<DWORD>(name.size());
			auto status = RegEnumValueW(key, i, name.data(), &length, nullptr, nullptr, nullptr, nullptr);
			if (status == ERROR_NO_MORE_ITEMS) break;
			if (status != ERROR_SUCCESS) continue;
			if (_wcsnicmp(name.data(), nerdFamily, _countof(nerdFamily) - 1) == 0 || _wcsnicmp(name.data(), nfFamily, _countof(nfFamily) - 1) == 0) {
				found = true;
				break;
			}
		}
		RegCloseKey(key);
		if (found) return true;
	}
	return false;
}

std::wstring terminalPowerShell() {
	std::vector<wchar_t> path(32768);
	auto length = SearchPathW(nullptr, L"pwsh.exe", nullptr, static_cast<DWORD>(path.size()), path.data(), nullptr);
	std::wstring exe;
	if (length > 0 && length < path.size()) exe.assign(path.data(), length);
	if (exe.empty()) {
		PWSTR programFiles = nullptr;
		if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_ProgramFiles, 0, nullptr, &programFiles))) {
			auto candidate = std::wstring(programFiles) + L"\\PowerShell\\7\\pwsh.exe";
			auto attributes = GetFileAttributesW(candidate.c_str());
			if (attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY)) exe = candidate;
		}
		CoTaskMemFree(programFiles);
	}
	return (exe.empty() ? L"powershell.exe" : L"\"" + exe + L"\"") + std::wstring(L" -NoLogo -NoExit -Command fastfetch");
}

// A Windows Terminal fragment: adds ii's scheme and profiles without touching settings.json.
bool writeTerminalScheme(const mcu::DynamicScheme& scheme, const std::vector<mcu::Argb>& term) {
	static const char* const names[16] = {"black", "red", "green", "yellow", "blue", "purple", "cyan", "white",
	                                      "brightBlack", "brightRed", "brightGreen", "brightYellow", "brightBlue",
	                                      "brightPurple", "brightCyan", "brightWhite"};
	using M = mcu::MaterialDynamicColors;
	auto field = [](const char* name, mcu::Argb color) { return std::string("      \"") + name + "\": \"" + hex(color) + "\""; };
	std::string json = "{\n  \"schemes\": [\n    {\n      \"name\": \"ii-windows\",\n";
	json += field("background", term[0]) + ",\n";
	json += field("foreground", term[15]) + ",\n";
	json += field("cursorColor", M::Primary().GetArgb(scheme)) + ",\n";
	json += field("selectionBackground", M::PrimaryContainer().GetArgb(scheme));
	for (int i = 0; i < 16; ++i) json += ",\n" + field(names[i], term[i]);
	json += "\n    }\n  ],\n  \"profiles\": [\n";
	// Stringify the command through the JSON API: an absolute pwsh path needs quotes and escapes.
	auto command = toUtf8(std::wstring(winrt::Windows::Data::Json::JsonValue::CreateStringValue(terminalPowerShell()).Stringify()));
	const char* const guids[] = {"{495a2d45-6aed-4548-8692-8479d8ea50b8}", "{0ecc530a-0128-423d-91f9-8c75d854077d}"};
	const char* const profiles[] = {"ii \xC2\xB7 PowerShell", "ii \xC2\xB7 CMD"}; // "\u00b7" as UTF-8 bytes
	auto haveFont = terminalFontInstalled();
	for (int i = 0; i < 2; ++i) {
		json += "    {\n      \"guid\": \"" + std::string(guids[i]) + "\",\n";
		json += "      \"name\": \"" + std::string(profiles[i]) + "\",\n";
		json += "      \"commandline\": " + (i == 0 ? command : "\"cmd.exe /k fastfetch\"") + ",\n";
		json += "      \"colorScheme\": \"ii-windows\",\n";
		// The bundled TTF's English typographic family (name ID 16).
		if (haveFont) json += "      \"font\": { \"face\": \"JetBrainsMono Nerd Font\", \"size\": 11 },\n";
		json += "      \"opacity\": 92,\n      \"useAcrylic\": false,\n      \"padding\": \"10\"\n    }";
		json += i == 0 ? ",\n" : "\n";
	}
	json += "  ]\n}\n";
	return writeUtf8(localAppData() + L"\\Microsoft\\Windows Terminal\\Fragments\\ii-windows\\ii-windows.json", json);
}

// --- Windows' own wallpaper -------------------------------------------------------------------
// One background, not two: ii adopts the wallpaper Windows has the first time (and whenever the user
// changes it in Windows), and a wallpaper chosen in ii becomes Windows' too. The file Windows had
// before ii is noted once so the rescue/uninstall can put it back.

std::wstring windowsWallpaper() {
	wchar_t buffer[MAX_PATH * 2] = {};
	if (SystemParametersInfoW(SPI_GETDESKWALLPAPER, static_cast<UINT>(sizeof(buffer) / sizeof(buffer[0])), buffer, 0) && buffer[0]) return buffer;
	// A slideshow (or Spotlight) has no single file for SPI_GETDESKWALLPAPER: Explorer notes the picture
	// it is showing in its own key.
	buffer[0] = 0;
	DWORD size = sizeof(buffer);
	if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Wallpapers", L"CurrentWallpaperPath",
	                 RRF_RT_REG_SZ, nullptr, buffer, &size) == ERROR_SUCCESS && buffer[0]) return buffer;
	return {};
}

std::wstring syncStatePath() { return localAppData() + L"\\ii-windows\\wallpaper-sync.ini"; }

std::wstring normalizedPath(std::wstring path) {
	for (auto& c: path) c = c == L'\\' ? L'/' : static_cast<wchar_t>(towlower(c));
	if (path.rfind(L"file:///", 0) == 0) path = path.substr(8);
	return path;
}

std::wstring syncStateValue(const char* key) {
	auto text = readUtf8(syncStatePath());
	auto prefix = std::string(key) + "=";
	size_t at = 0;
	while (at < text.size()) {
		auto end = text.find('\n', at);
		if (end == std::string::npos) end = text.size();
		auto line = text.substr(at, end - at);
		if (!line.empty() && line.back() == '\r') line.pop_back();
		if (line.rfind(prefix, 0) == 0) return std::wstring(winrt::to_hstring(line.substr(prefix.size())));
		at = end + 1;
	}
	return {};
}

void writeSyncState(const std::wstring& applied, const std::wstring& original, const std::wstring& originalStyle) {
	CreateDirectoryW((localAppData() + L"\\ii-windows").c_str(), nullptr);
	auto text = std::string("applied=") + toUtf8(applied) + "\noriginal=" + toUtf8(original) + "\noriginalStyle=" + toUtf8(originalStyle) + "\n";
	writeUtf8(syncStatePath(), text);
}

std::wstring wallpaperStyleValue() {
	wchar_t buffer[16] = {};
	DWORD size = sizeof(buffer);
	if (RegGetValueW(HKEY_CURRENT_USER, L"Control Panel\\Desktop", L"WallpaperStyle", RRF_RT_REG_SZ, nullptr, buffer, &size) != ERROR_SUCCESS) return L"10";
	return buffer;
}

// Makes `path` Windows' wallpaper, filled (cropped to the screen like ii does).
bool applyToWindows(const std::wstring& path) {
	auto original = syncStateValue("original");
	auto originalStyle = syncStateValue("originalStyle");
	if (original.empty()) {
		original = windowsWallpaper();
		originalStyle = wallpaperStyleValue();
	}
	std::wstring native = path;
	for (auto& c: native) {
		if (c == L'/') c = L'\\';
	}
	HKEY key = nullptr;
	if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\Desktop", 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
		RegSetValueExW(key, L"WallpaperStyle", 0, REG_SZ, reinterpret_cast<const BYTE*>(L"10"), 3 * sizeof(wchar_t));
		RegSetValueExW(key, L"TileWallpaper", 0, REG_SZ, reinterpret_cast<const BYTE*>(L"0"), 2 * sizeof(wchar_t));
		RegCloseKey(key);
	}
	auto ok = SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, native.data(), SPIF_UPDATEINIFILE | SPIF_SENDCHANGE) != 0;
	writeSyncState(native, original, originalStyle);
	return ok;
}

// ---- A still of a live wallpaper as Windows' own wallpaper -------------------------------------------------
// Wallpaper Engine / Lively draw above Windows' wallpaper, which stays visible for a moment on every
// virtual-desktop switch (the live window is redrawn a few hundred ms late): a different static picture
// shows. Windows 11 keeps one wallpaper PER DESKTOP and SPI_SETDESKWALLPAPER sets the current one, so
// while a live wallpaper runs, each desktop gets a still of it (the preview picture) the moment ii sees it.
std::wstring stillPath() { return localAppData() + L"\\ii-windows\\extwall-still.png"; }

// First frame of `src` as a PNG in `dst` (a sidecar remembers which source it came from). True when `dst`
// was (re)made.
bool convertToPng(const std::wstring& src, const std::wstring& dst, bool& remade) {
	remade = false;
	WIN32_FILE_ATTRIBUTE_DATA data {};
	if (!GetFileAttributesExW(src.c_str(), GetFileExInfoStandard, &data)) return false;
	auto stamp = toUtf8(src) + "|" + std::to_string((static_cast<unsigned long long>(data.ftLastWriteTime.dwHighDateTime) << 32) | data.ftLastWriteTime.dwLowDateTime);
	auto sidecar = dst + L".txt";
	if (GetFileAttributesW(dst.c_str()) != INVALID_FILE_ATTRIBUTES && readUtf8(sidecar) == stamp) return true;

	ComPtr<IWICImagingFactory> wic;
	ComPtr<IWICBitmapDecoder> decoder;
	ComPtr<IWICBitmapFrameDecode> frame;
	ComPtr<IWICFormatConverter> converter;
	if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&wic)))
	    || FAILED(wic->CreateDecoderFromFilename(src.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &decoder))
	    || FAILED(decoder->GetFrame(0, &frame)) || FAILED(wic->CreateFormatConverter(&converter))
	    || FAILED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom)))
		return false;
	CreateDirectoryW((localAppData() + L"\\ii-windows").c_str(), nullptr);
	auto temp = dst + L".tmp";
	// A preview is small (often 160 x 160): Windows would blow it up in blocks. Scaled here with a smooth
	// filter to cover the screen and cropped to its shape, it is a soft version of the scene instead.
	IWICBitmapSource* source = converter.Get();
	ComPtr<IWICBitmapScaler> scaler;
	ComPtr<IWICBitmapClipper> clipper;
	{
		UINT w = 0, h = 0;
		converter->GetSize(&w, &h);
		auto screenW = static_cast<UINT>(std::max(1280, GetSystemMetrics(SM_CXSCREEN)));
		auto screenH = static_cast<UINT>(std::max(720, GetSystemMetrics(SM_CYSCREEN)));
		if (w > 0 && h > 0 && (w < screenW || h < screenH)) {
			auto k = std::max(static_cast<double>(screenW) / w, static_cast<double>(screenH) / h);
			auto nw = static_cast<UINT>(std::ceil(w * k)), nh = static_cast<UINT>(std::ceil(h * k));
			WICRect crop {static_cast<INT>((nw - screenW) / 2), static_cast<INT>((nh - screenH) / 2), static_cast<INT>(screenW), static_cast<INT>(screenH)};
			if (SUCCEEDED(wic->CreateBitmapScaler(&scaler)) && SUCCEEDED(scaler->Initialize(converter.Get(), nw, nh, WICBitmapInterpolationModeHighQualityCubic))
			    && SUCCEEDED(wic->CreateBitmapClipper(&clipper)) && SUCCEEDED(clipper->Initialize(scaler.Get(), &crop)))
				source = clipper.Get();
		}
	}
	{
		ComPtr<IWICStream> stream;
		ComPtr<IWICBitmapEncoder> encoder;
		ComPtr<IWICBitmapFrameEncode> out;
		ComPtr<IPropertyBag2> options;
		UINT width = 0, height = 0;
		source->GetSize(&width, &height);
		WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
		if (FAILED(wic->CreateStream(&stream)) || FAILED(stream->InitializeFromFilename(temp.c_str(), GENERIC_WRITE))
		    || FAILED(wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder)) || FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))
		    || FAILED(encoder->CreateNewFrame(&out, &options)) || FAILED(out->Initialize(options.Get())) || FAILED(out->SetSize(width, height))
		    || FAILED(out->SetPixelFormat(&format)) || FAILED(out->WriteSource(source, nullptr)) || FAILED(out->Commit()) || FAILED(encoder->Commit()))
			return false;
	}
	if (!MoveFileExW(temp.c_str(), dst.c_str(), MOVEFILE_REPLACE_EXISTING)) return false;
	writeUtf8(sidecar, stamp);
	remade = true;
	return true;
}

bool setWindowsWallpaperFile(const std::wstring& path) {
	std::wstring native = path;
	for (auto& c: native) {
		if (c == L'/') c = L'\\';
	}
	return SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, native.data(), SPIF_UPDATEINIFILE | SPIF_SENDCHANGE) != 0;
}

// The current desktop's Windows wallpaper becomes the still, but only if it shows ii's own picture (or the
// still already): a wallpaper the user chose for that desktop is left alone.
int desktopStill(const std::wstring& image, const std::wstring& iiPath) {
	auto still = stillPath();
	bool remade = false;
	if (image.empty() || !convertToPng(image, still, remade)) return 1;
	auto current = windowsWallpaper();
	auto known = syncStateValue("applied");
	auto isStill = normalizedPath(current) == normalizedPath(still);
	auto isIi = (!iiPath.empty() && normalizedPath(current) == normalizedPath(iiPath)) || (!known.empty() && normalizedPath(current) == normalizedPath(known));
	if ((isStill && remade) || (!isStill && isIi)) setWindowsWallpaperFile(still); // a new picture at the same path: set it again
	return 0;
}

// The live wallpaper is gone: this desktop's Windows wallpaper goes back to ii's (or the original) if it still shows the still.
int desktopStillRestore() {
	if (normalizedPath(windowsWallpaper()) != normalizedPath(stillPath())) return 0;
	auto target = syncStateValue("applied");
	if (target.empty() || GetFileAttributesW(target.c_str()) == INVALID_FILE_ATTRIBUTES) target = syncStateValue("original");
	if (target.empty()) return 0;
	setWindowsWallpaperFile(target);
	return 0;
}

// Copies Windows' current wallpaper next to ii's own wallpapers and returns the copy ("" = nothing to adopt).
std::wstring adoptedWindowsWallpaper(const std::wstring& currentConfigPath, bool force) {
	auto windows = windowsWallpaper();
	// The still of a live wallpaper (above) is ours, not a picture the user chose in Windows.
	if (normalizedPath(windows) == normalizedPath(stillPath())) return {};
	auto windowsUsable = !windows.empty() && GetFileAttributesW(windows.c_str()) != INVALID_FILE_ATTRIBUTES;
	auto known = syncStateValue("applied");
	if (known.empty() && !force) {
		// First time ii looks at Windows' wallpaper. If ii still has its stock picture (or the file is gone),
		// the user's own wallpaper wins and ii takes it. If ii already has a picture the user chose, that
		// one is kept and becomes Windows' too (the original is noted for the rescue).
		std::wstring native = currentConfigPath;
		for (auto& c: native) {
			if (c == L'/') c = L'\\';
		}
		auto stock = currentConfigPath.empty() || normalizedPath(currentConfigPath).find(L"default_wallpaper") != std::wstring::npos
		             || GetFileAttributesW(native.c_str()) == INVALID_FILE_ATTRIBUTES;
		if (!stock) {
			applyToWindows(currentConfigPath);
			return {};
		}
	}
	if (!windowsUsable) return {};
	auto sameAsIi = normalizedPath(windows) == normalizedPath(currentConfigPath);
	if (!force && !known.empty() && normalizedPath(known) == normalizedPath(windows)) return {}; // nothing changed in Windows
	auto original = syncStateValue("original");
	if (sameAsIi) {
		writeSyncState(windows, original.empty() ? windows : original, syncStateValue("originalStyle"));
		return {};
	}
	// A copy ii owns: Windows may delete or replace its own file (the slideshow keeps rewriting it).
	wchar_t* pictures = nullptr;
	std::wstring folder = localAppData() + L"\\ii-windows\\wallpapers";
	if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Pictures, 0, nullptr, &pictures)) && pictures) {
		folder = std::wstring(pictures) + L"\\Wallpapers";
		CoTaskMemFree(pictures);
	}
	CreateDirectoryW(folder.c_str(), nullptr);
	if (GetFileAttributesW(folder.c_str()) == INVALID_FILE_ATTRIBUTES) {
		CreateDirectoryW((localAppData() + L"\\ii-windows").c_str(), nullptr);
		folder = localAppData() + L"\\ii-windows\\wallpapers";
		CreateDirectoryW(folder.c_str(), nullptr);
	}
	auto dot = windows.find_last_of(L'.');
	auto slash = windows.find_last_of(L"\\/");
	auto ext = (dot != std::wstring::npos && (slash == std::wstring::npos || dot > slash)) ? windows.substr(dot) : std::wstring(L".jpg");
	auto target = folder + L"\\windows-wallpaper" + ext;
	if (!CopyFileW(windows.c_str(), target.c_str(), FALSE)) {
		// The start-up adoption and a new install's first run come at the same moment and write this very copy:
		// wait for the other one instead of giving up (a new install then fell back to ii's own picture).
		auto sizeOf = [](const std::wstring& path) -> uint64_t {
			WIN32_FILE_ATTRIBUTE_DATA data {};
			if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return 0;
			return (static_cast<uint64_t>(data.nFileSizeHigh) << 32) | data.nFileSizeLow;
		};
		auto copied = false;
		for (int i = 0; i < 15 && !copied; ++i) {
			Sleep(200);
			copied = CopyFileW(windows.c_str(), target.c_str(), FALSE) || (sizeOf(target) != 0 && sizeOf(target) == sizeOf(windows));
		}
		if (!copied) return {};
	}
	writeSyncState(windows, original.empty() ? windows : original, syncStateValue("originalStyle"));
	return target;
}

// Puts back the wallpaper Windows had before ii (rescue / uninstall).
bool restoreWindowsWallpaper() {
	auto original = syncStateValue("original");
	if (original.empty()) return false;
	HKEY key = nullptr;
	auto style = syncStateValue("originalStyle");
	if (!style.empty() && RegOpenKeyExW(HKEY_CURRENT_USER, L"Control Panel\\Desktop", 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
		RegSetValueExW(key, L"WallpaperStyle", 0, REG_SZ, reinterpret_cast<const BYTE*>(style.c_str()), static_cast<DWORD>((style.size() + 1) * sizeof(wchar_t)));
		RegCloseKey(key);
	}
	return SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, original.data(), SPIF_UPDATEINIFILE | SPIF_SENDCHANGE) != 0;
}

} // namespace

int switchwall(const Args& args) {
	winrt::init_apartment(winrt::apartment_type::single_threaded); // dialogs need an STA

	// One switchwall at a time: several start together (the start-up adoption, a new install's first run, the
	// light/dark switch...) and each reads config.json, copies files and writes it back. Run side by side, one
	// lost its copy or its write and a new install was left on ii's own picture.
	struct Turn {
		HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\ii-windows-switchwall");
		bool owned = mutex && WaitForSingleObject(mutex, 20000) != WAIT_TIMEOUT;
		~Turn() {
			if (owned) ReleaseMutex(mutex);
			if (mutex) CloseHandle(mutex);
		}
	} turn;

	std::wstring mode;
	std::wstring type;
	std::wstring image;
	bool noswitch = false;
	bool adoptWindows = false;
	bool forceAdopt = false;
	bool restoreWindows = false;
	bool colorGiven = false;
	std::wstring colorArg;
	// --palette-from <image>: the colors come from this picture (the preview of a Wallpaper Engine / Lively
	// wallpaper), but the wallpaper ii shows, Windows' wallpaper and config.json stay as they are.
	std::wstring paletteFrom;
	std::wstring desktopStillImage;
	bool desktopStillGiven = false, desktopStillRestoreGiven = false;
	// --first-run <ii's own picture>: a new install. The wallpaper the user already has in Windows becomes ii's;
	// ii's own picture only when Windows has none to give (a plain colour), and then Windows keeps its colour.
	std::wstring firstRunDefault;
	for (size_t i = 0; i < args.size(); ++i) {
		const auto& a = args[i];
		auto next = [&]() { return i + 1 < args.size() ? args[++i] : std::wstring(); };
		if (a == L"--palette-from") paletteFrom = next();
		else if (a == L"--desktop-still") { desktopStillGiven = true; desktopStillImage = next(); }
		else if (a == L"--desktop-still-restore") desktopStillRestoreGiven = true;
		else if (a == L"--mode") mode = next();
		else if (a == L"--type") type = next();
		else if (a == L"--image") image = next();
		else if (a == L"--noswitch") noswitch = true;
		else if (a == L"--adopt-windows") adoptWindows = true;
		else if (a == L"--first-run") firstRunDefault = next();
		else if (a == L"--force") forceAdopt = true;
		else if (a == L"--restore-windows") restoreWindows = true;
		else if (a == L"--color") {
			colorGiven = true;
			mcu::Argb ignored = 0;
			if (i + 1 < args.size() && (parseHex(args[i + 1], ignored) || args[i + 1] == L"clear")) colorArg = next();
		} else if (image.empty()) image = a;
	}

	if (restoreWindows) return restoreWindowsWallpaper() ? 0 : 1;
	if (desktopStillRestoreGiven) return desktopStillRestore();
	if (desktopStillGiven) return desktopStill(desktopStillImage, getString(child(loadConfig(), L"background"), L"wallpaperPath"));

	auto config = loadConfig();
	auto appearance = child(config, L"appearance");
	auto palette = child(appearance, L"palette");
	auto background = child(config, L"background");
	// background.syncWindowsWallpaper (default on): Windows and ii show the same picture.
	auto syncWindows = !(background.HasKey(L"syncWindowsWallpaper") && background.GetNamedValue(L"syncWindowsWallpaper").ValueType() == json::JsonValueType::Boolean
	                     && !background.GetNamedBoolean(L"syncWindowsWallpaper"));
	auto adopted = false;
	if (!firstRunDefault.empty()) {
		image = syncWindows ? adoptedWindowsWallpaper(L"", true) : std::wstring();
		if (image.empty()) image = firstRunDefault;
		adopted = true; // nothing is pushed to Windows either way
	} else if (adoptWindows) {
		if (!syncWindows) return 0;
		image = adoptedWindowsWallpaper(getString(background, L"wallpaperPath"), forceAdopt);
		if (image.empty()) return 0; // nothing new in Windows
		adopted = true;
	}

	// --color: an explicit accent replaces the wallpaper as the palette's source.
	if (colorGiven) {
		mcu::Argb picked = 0;
		if (colorArg == L"clear") palette.SetNamedValue(L"accentColor", json::JsonValue::CreateStringValue(L""));
		else if (parseHex(colorArg, picked) || pickColor(picked)) {
			palette.SetNamedValue(L"accentColor", json::JsonValue::CreateStringValue(fromUtf8(hex(picked))));
		} else {
			return 1; // color dialog cancelled
		}
	}

	if (!paletteFrom.empty()) noswitch = true; // nothing is switched, only the palette is computed
	if (noswitch) image = paletteFrom.empty() ? getString(background, L"wallpaperPath") : paletteFrom;
	mcu::Argb accent = 0;
	auto hasAccent = parseHex(getString(palette, L"accentColor"), accent);
	if (image.empty() && !hasAccent && !noswitch) {
		image = pickWallpaper();
		if (image.empty()) return 1;
	}
	for (auto& c: image) {
		if (c == L'\\') c = L'/';
	}
	if (image.rfind(L"file:///", 0) == 0) image = image.substr(8);

	// A newly chosen wallpaper drives the colors again.
	if (!image.empty() && !noswitch) {
		background.SetNamedValue(L"wallpaperPath", json::JsonValue::CreateStringValue(image));
		palette.SetNamedValue(L"accentColor", json::JsonValue::CreateStringValue(L""));
		hasAccent = false;
	}

	if (type.empty()) type = getString(palette, L"type");
	if (type.empty()) type = L"auto";
	auto dark = mode.empty() ? currentlyDark() : mode != L"light";

	Image pixels;
	auto haveImage = !image.empty() && loadImage(image, pixels);
	mcu::Argb source = 0xFF4285F4u;
	if (hasAccent) source = accent;
	else if (haveImage) source = sourceColor(pixels);
	auto schemeType = toUtf8(type);
	if (schemeType == "auto") schemeType = haveImage && !hasAccent ? schemeForImage(pixels) : "scheme-tonal-spot";

	auto scheme = makeScheme(schemeType, source, dark);
	std::string out = "{\n";
	const auto& keys = colorKeys();
	for (size_t i = 0; i < keys.size(); ++i) {
		out += "  \"" + std::string(keys[i].first) + "\": \"" + hex(keys[i].second().GetArgb(*scheme)) + "\"";
		out += i + 1 < keys.size() ? ",\n" : "\n";
	}
	out += "}\n";

	// Config first (wallpaper path), then the palette: ii reloads each file when it changes.
	if (paletteFrom.empty()) writeUtf8(configPath(), toUtf8(std::wstring(config.Stringify())));
	// What ii shows is what Windows shows (a picture, not a video wallpaper).
	if (!image.empty() && !noswitch && !adopted && syncWindows) {
		auto lower = normalizedPath(image);
		auto endsWith = [&](const wchar_t* suffix) {
			std::wstring s(suffix);
			return lower.size() >= s.size() && lower.compare(lower.size() - s.size(), s.size(), s) == 0;
		};
		if (!(endsWith(L".mp4") || endsWith(L".mkv") || endsWith(L".mov") || endsWith(L".avi") || endsWith(L".webm"))) applyToWindows(image);
	}
	writeUtf8(sourceColorPath(), hex(source) + "\n");
	TermProps props;
	auto termConfig = existing(existing(appearance, L"wallpaperTheming"), L"terminalGenerationProps");
	auto number = [&](const wchar_t* name, double& out) {
		if (termConfig.HasKey(name) && termConfig.GetNamedValue(name).ValueType() == json::JsonValueType::Number) {
			out = termConfig.GetNamedNumber(name);
		}
	};
	number(L"harmony", props.harmony);
	number(L"harmonizeThreshold", props.threshold);
	number(L"termFgBoost", props.fgBoost);
	// Terminal's fragment is a nicety: a failure there must not fail the wallpaper change.
	writeTerminalScheme(*scheme, terminalColors(*scheme, dark, schemeType == "scheme-monochrome", props));
	if (!writeUtf8(colorsPath(), out)) return 1;
	std::printf("source %s, %s, %s -> %zu colors\n", hex(source).c_str(), schemeType.c_str(), dark ? "dark" : "light", keys.size());
	return 0;
}
