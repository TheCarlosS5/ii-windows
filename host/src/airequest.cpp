// Streaming POST transport for Ai.qml. Credentials stay in the process environment.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <fcntl.h>
#include <io.h>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <winhttp.h>

// clang-format off
#include <winrt/base.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.Collections.h>
// clang-format on

namespace {

namespace json = winrt::Windows::Data::Json;

struct InternetClose {
	void operator()(void* handle) const { WinHttpCloseHandle(handle); }
};
using Internet = std::unique_ptr<void, InternetClose>;

struct Apartment {
	Apartment() { winrt::init_apartment(winrt::apartment_type::single_threaded); }
	~Apartment() { winrt::uninit_apartment(); }
};

void require(bool ok, const char* reason) {
	if (!ok) throw std::runtime_error(reason);
}

void httpRequire(bool ok, const char* reason) {
	if (!ok) throw std::runtime_error(std::string(reason) + " (WinHTTP " + std::to_string(GetLastError()) + ")");
}

bool hasControl(const std::wstring& value) {
	return std::any_of(value.begin(), value.end(), [](wchar_t c) { return c < 32 || c == 127; });
}

bool nameStart(wchar_t c) {
	return (c >= L'A' && c <= L'Z') || (c >= L'a' && c <= L'z') || c == L'_';
}

bool nameChar(wchar_t c) {
	return nameStart(c) || (c >= L'0' && c <= L'9');
}

std::wstring environment(const std::wstring& name) {
	auto size = GetEnvironmentVariableW(name.c_str(), nullptr, 0);
	if (!size) return {};
	std::wstring value(size, L'\0');
	auto count = GetEnvironmentVariableW(name.c_str(), value.data(), size);
	require(count < size, "environment variable changed during request");
	value.resize(count);
	return value;
}

std::wstring expandEnvironment(const std::wstring& text) {
	std::wstring result;
	for (size_t i = 0; i < text.size();) {
		if (text[i] != L'$') { result += text[i++]; continue; }
		auto start = i + 1;
		auto braced = start < text.size() && text[start] == L'{';
		if (braced) ++start;
		if (start == text.size() || !nameStart(text[start])) { result += text[i++]; continue; }
		auto end = start + 1;
		while (end < text.size() && nameChar(text[end])) ++end;
		if (braced && (end == text.size() || text[end] != L'}')) { result += text[i++]; continue; }
		// Substitute once, without interpreting dollars in the environment value.
		result += environment(text.substr(start, end - start));
		i = end + (braced ? 1 : 0);
	}
	return result;
}

json::JsonObject readRequest(std::wstring path) {
	// FileUtils.trimFileProtocol can leave /C:/... . Forward slashes work with Win32.
	if (path.size() > 3 && path[0] == L'/' && path[2] == L':' && nameStart(path[1])) path.erase(0, 1);
	std::ifstream file(std::filesystem::path(path), std::ios::binary | std::ios::ate);
	require(file.is_open(), "cannot read request file");
	auto size = file.tellg();
	require(size >= 0 && size <= std::numeric_limits<DWORD>::max(), "invalid request file size");
	std::string text(static_cast<size_t>(size), '\0');
	file.seekg(0);
	require(static_cast<bool>(file.read(text.data(), static_cast<std::streamsize>(text.size()))), "cannot read request file");
	file.close(); // Windows will not delete a file that is still open
	if (text.rfind("\xEF\xBB\xBF", 0) == 0) text.erase(0, 3);
	json::JsonObject request;
	require(json::JsonObject::TryParse(winrt::to_hstring(text), request), "invalid request JSON");
	// The request is in memory now; its file held the prompt and must not outlive this call (the
	// credentials never were in it: headers name environment variables). II_KEEP_REQUEST=1 keeps
	// it for debugging.
	if (environment(L"II_KEEP_REQUEST") != L"1") {
		std::error_code ignored;
		std::filesystem::remove(std::filesystem::path(path), ignored);
	}
	return request;
}

// Requests whose process never got to read them (a crash, a killed shell) would otherwise stay
// for ever. Only files named exactly like ours (request.<instance>.json) in the same folder, older
// than an hour, and at most 50 per call: nothing else is ever touched.
void sweepStaleRequests(std::wstring path) {
	if (path.size() > 3 && path[0] == L'/' && path[2] == L':' && nameStart(path[1])) path.erase(0, 1);
	std::error_code error;
	auto folder = std::filesystem::path(path).parent_path();
	if (folder.empty() || !std::filesystem::is_directory(folder, error)) return;
	auto now = std::filesystem::file_time_type::clock::now();
	int removed = 0;
	for (const auto& entry: std::filesystem::directory_iterator(folder, error)) {
		if (removed >= 50) break;
		if (!entry.is_regular_file(error)) continue;
		auto name = entry.path().filename().wstring();
		if (name.size() <= 13 || name.rfind(L"request.", 0) != 0 || name.compare(name.size() - 5, 5, L".json") != 0) continue;
		auto written = entry.last_write_time(error);
		if (!error && now - written > std::chrono::hours(1) && std::filesystem::remove(entry.path(), error)) ++removed;
	}
}

} // namespace

int aiRequest(const std::vector<std::wstring>& args) {
	try {
		require(args.size() == 1, "usage: ai-request <request.json>");
		Apartment apartment;
		sweepStaleRequests(args[0]);
		auto data = readRequest(args[0]);
		auto url = expandEnvironment(std::wstring(data.GetNamedString(L"url")));
		// POST by default; {"method":"GET"} (no body) lists what a provider offers, e.g. Gemini's models.
		std::wstring httpMethod = L"POST";
		if (data.HasKey(L"method") && std::wstring(data.GetNamedString(L"method")) == L"GET") httpMethod = L"GET";
		auto body = data.HasKey(L"body") ? winrt::to_string(data.GetNamedString(L"body")) : std::string();
		require(body.size() <= std::numeric_limits<DWORD>::max(), "request body too large");
		require(!hasControl(url) && url.find_first_of(L" \\") == std::wstring::npos, "invalid request URL");

		URL_COMPONENTS parts {};
		parts.dwStructSize = sizeof(parts);
		parts.dwHostNameLength = parts.dwUrlPathLength = parts.dwExtraInfoLength = static_cast<DWORD>(-1);
		parts.dwUserNameLength = parts.dwPasswordLength = static_cast<DWORD>(-1);
		require(WinHttpCrackUrl(url.c_str(), 0, 0, &parts) != 0, "invalid request URL");
		require(parts.nScheme == INTERNET_SCHEME_HTTP || parts.nScheme == INTERNET_SCHEME_HTTPS,
		        "only HTTP and HTTPS URLs are allowed");
		require(parts.dwHostNameLength != 0 && parts.dwUserNameLength == 0 && parts.dwPasswordLength == 0,
		        "invalid request URL");
		std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
		std::wstring target = parts.dwUrlPathLength ? std::wstring(parts.lpszUrlPath, parts.dwUrlPathLength) : L"/";
		if (parts.dwExtraInfoLength) target.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
		auto fragment = target.find(L'#');
		if (fragment != std::wstring::npos) target.resize(fragment);

		std::wstring headers;
		for (const auto& entry: data.GetNamedObject(L"headers")) {
			std::wstring name(entry.Key());
			require(!name.empty() && std::all_of(name.begin(), name.end(), [](wchar_t c) {
				return c > 32 && c < 127 && std::wstring(L"()<>@,;:\\\"/[]?={}").find(c) == std::wstring::npos;
			}), "invalid request header name");
			auto value = expandEnvironment(std::wstring(entry.Value().GetString()));
			require(!hasControl(value), "invalid request header value");
			headers += name + L": " + value + L"\r\n";
		}

		Internet session(WinHttpOpen(L"ii-windows/ai-request", WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
		                             WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
		httpRequire(session != nullptr, "cannot open WinHTTP session");
		// Long generations can pause between chunks; never apply fetch's short receive timeout.
		httpRequire(WinHttpSetTimeouts(session.get(), 15000, 15000, 300000, 300000) != 0, "cannot set HTTP timeouts");
		Internet connection(WinHttpConnect(session.get(), host.c_str(), parts.nPort, 0));
		httpRequire(connection != nullptr, "HTTP connection failed");
		auto flags = parts.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0;
		Internet request(WinHttpOpenRequest(connection.get(), httpMethod.c_str(), target.c_str(), nullptr,
		                                   WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags));
		httpRequire(request != nullptr, "cannot create HTTP request");
		// curl did not follow redirects; keep credentials on the specified endpoint.
		DWORD policy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
		httpRequire(WinHttpSetOption(request.get(), WINHTTP_OPTION_REDIRECT_POLICY, &policy, sizeof(policy)) != 0,
		            "cannot set redirect policy");
		if (!headers.empty()) {
			httpRequire(WinHttpAddRequestHeaders(request.get(), headers.c_str(), static_cast<DWORD>(-1),
			                                    WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE) != 0,
			            "cannot set HTTP headers");
		}
		auto length = static_cast<DWORD>(body.size());
		httpRequire(WinHttpSendRequest(request.get(), WINHTTP_NO_ADDITIONAL_HEADERS, 0,
		                               body.empty() ? WINHTTP_NO_REQUEST_DATA : body.data(), length, length, 0) != 0,
		            "HTTP request failed");
		httpRequire(WinHttpReceiveResponse(request.get(), nullptr) != 0, "HTTP response failed");
		DWORD status = 0, size = sizeof(status);
		httpRequire(WinHttpQueryHeaders(request.get(), WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
		                                WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX) != 0,
		            "cannot read HTTP status");
		require(_setmode(_fileno(stdout), _O_BINARY) != -1, "cannot set binary stdout");
		char buffer[8192];
		for (;;) {
			DWORD available = 0;
			httpRequire(WinHttpQueryDataAvailable(request.get(), &available) != 0, "HTTP stream failed");
			if (!available) break;
			DWORD count = 0;
			httpRequire(WinHttpReadData(request.get(), buffer, std::min<DWORD>(available, sizeof(buffer)), &count) != 0,
			            "HTTP stream failed");
			if (!count) break;
			require(std::fwrite(buffer, 1, count, stdout) == count && std::fflush(stdout) == 0, "cannot write stdout");
		}
		return status >= 200 && status < 300 ? 0 : 1;
	} catch (const winrt::hresult_error&) {
		std::fputs("ai-request: invalid request JSON or Windows API failure\n", stderr);
	} catch (const std::exception& error) {
		// All diagnostic text is fixed or a numeric error code, never the URL, headers or body.
		std::fprintf(stderr, "ai-request: %s\n", error.what());
	}
	return 1;
}
