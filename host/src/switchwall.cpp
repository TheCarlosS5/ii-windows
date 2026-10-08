// switchwall: ii's scripts/colors/switchwall.sh for Windows. Sets the wallpaper in ii's config and
// writes the Material 3 palette ii reads (colors.json, the keys of its matugen template).
//
//   switchwall [--mode dark|light] [--type scheme-...|auto] [--image <file> | <file>]
//              [--noswitch] [--color [#rrggbb|clear]]
//
// Colors come from Google's material-color-utilities (Celebi quantizer + Score + dynamic scheme),
// the algorithm ii uses through matugen / materialyoucolor. "auto" picks the scheme the way ii's
// scheme_for_image.py does (image colorfulness). With no wallpaper given, Windows' file dialog
// replaces kdialog; with a bare --color, Windows' color dialog replaces hyprpicker.

#include <algorithm>
#include <cmath>
#include <cstdio>
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

} // namespace

int switchwall(const Args& args) {
	winrt::init_apartment(winrt::apartment_type::single_threaded); // dialogs need an STA

	std::wstring mode;
	std::wstring type;
	std::wstring image;
	bool noswitch = false;
	bool colorGiven = false;
	std::wstring colorArg;
	for (size_t i = 0; i < args.size(); ++i) {
		const auto& a = args[i];
		auto next = [&]() { return i + 1 < args.size() ? args[++i] : std::wstring(); };
		if (a == L"--mode") mode = next();
		else if (a == L"--type") type = next();
		else if (a == L"--image") image = next();
		else if (a == L"--noswitch") noswitch = true;
		else if (a == L"--color") {
			colorGiven = true;
			mcu::Argb ignored = 0;
			if (i + 1 < args.size() && (parseHex(args[i + 1], ignored) || args[i + 1] == L"clear")) colorArg = next();
		} else if (image.empty()) image = a;
	}

	auto config = loadConfig();
	auto appearance = child(config, L"appearance");
	auto palette = child(appearance, L"palette");
	auto background = child(config, L"background");

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

	if (noswitch) image = getString(background, L"wallpaperPath");
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
	writeUtf8(configPath(), toUtf8(std::wstring(config.Stringify())));
	writeUtf8(sourceColorPath(), hex(source) + "\n");
	if (!writeUtf8(colorsPath(), out)) return 1;
	std::printf("source %s, %s, %s -> %zu colors\n", hex(source).c_str(), schemeType.c_str(), dark ? "dark" : "light", keys.size());
	return 0;
}
