// wttr.in's current weather, nearest location, and today's astronomy without curl/jq.
#include "http.h"

#include <algorithm>
#include <cstdio>
#include <stdexcept>

// clang-format off
#include <winrt/base.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.Collections.h>
// clang-format on

namespace {

namespace json = winrt::Windows::Data::Json;

void require(bool ok, const char* reason) {
	if (!ok) throw std::runtime_error(reason);
}

struct Apartment {
	Apartment() { winrt::init_apartment(winrt::apartment_type::single_threaded); }
	~Apartment() { winrt::uninit_apartment(); }
};

std::wstring encodePlace(std::wstring place) {
	// Weather.qml formatCityName trims whitespace and joins words with '+'. wttr treats
	// that separator as a space. Encode the resulting UTF-8 path segment exactly once.
	std::replace(place.begin(), place.end(), L'+', L' ');
	auto bytes = winrt::to_string(place);
	const wchar_t* hex = L"0123456789ABCDEF";
	std::wstring encoded;
	for (unsigned char c: bytes) {
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
		    || c == '-' || c == '.' || c == '_' || c == '~') encoded += static_cast<wchar_t>(c);
		else { encoded += L'%'; encoded += hex[c >> 4]; encoded += hex[c & 15]; }
	}
	return encoded;
}

json::JsonObject firstObject(const json::JsonObject& parent, const wchar_t* name) {
	require(parent.HasKey(name) && parent.GetNamedValue(name).ValueType() == json::JsonValueType::Array,
	        "invalid weather JSON: missing array");
	auto array = parent.GetNamedArray(name);
	require(array.Size() != 0 && array.GetAt(0).ValueType() == json::JsonValueType::Object,
	        "invalid weather JSON: missing first object");
	return array.GetObjectAt(0);
}

} // namespace

int weather(const std::vector<std::wstring>& args) {
	try {
		const char* usage = "usage: weather <place-or-lat,long> [--test]";
		require(!args.empty() && args[0].rfind(L"--", 0) != 0 && args.size() <= 2
		        && (args.size() == 1 || args[1] == L"--test"), usage);
		Apartment apartment;
		http::Client client(L"ii-windows/weather", args.size() == 2);
		auto bytes = client.get(L"https://wttr.in/" + encodePlace(args[0]) + L"?format=j1", 1024 * 1024);
		json::JsonObject response;
		require(json::JsonObject::TryParse(winrt::to_hstring(bytes), response), "invalid JSON from wttr.in");
		json::JsonObject result;
		result.Insert(L"current", firstObject(response, L"current_condition"));
		result.Insert(L"location", firstObject(response, L"nearest_area"));
		result.Insert(L"astronomy", firstObject(firstObject(response, L"weather"), L"astronomy"));
		http::writeStdout(winrt::to_string(result.Stringify()) + "\n");
		return 0;
	} catch (const winrt::hresult_error&) {
		std::fputs("weather: invalid JSON/URL or Windows API failure\n", stderr);
	} catch (const std::exception& error) {
		std::fprintf(stderr, "weather: %s\n", error.what());
	}
	return 1;
}
