#include "http.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cwctype>
#include <filesystem>
#include <limits>
#include <stdexcept>
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
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
// clang-format on

namespace {

namespace json = winrt::Windows::Data::Json;

struct InternetClose {
	void operator()(void* handle) const { WinHttpCloseHandle(handle); }
};
using Internet = std::unique_ptr<void, InternetClose>;

struct FileClose {
	void operator()(void* handle) const { CloseHandle(handle); }
};
using File = std::unique_ptr<void, FileClose>;

void require(bool ok, const char* reason) {
	if (!ok) throw std::runtime_error(reason);
}

void httpRequire(bool ok, const char* reason) {
	if (!ok) throw std::runtime_error(std::string(reason) + " (WinHTTP " + std::to_string(GetLastError()) + ")");
}

bool hasControl(const std::wstring& value) {
	return std::any_of(value.begin(), value.end(), [](wchar_t c) { return c < 32 || c == 127; });
}

size_t byteCount(const std::wstring& text, const char* reason) {
	require(!text.empty(), reason);
	size_t value = 0;
	for (auto c: text) {
		require(c >= L'0' && c <= L'9', reason);
		auto digit = static_cast<size_t>(c - L'0');
		require(value <= (std::numeric_limits<size_t>::max() - digit) / 10, reason);
		value = value * 10 + digit;
	}
	return value;
}

std::wstring env(const wchar_t* name) {
	auto size = GetEnvironmentVariableW(name, nullptr, 0);
	if (!size) return {};
	std::wstring value(size, L'\0');
	auto count = GetEnvironmentVariableW(name, value.data(), size);
	if (!count || count >= size) return {};
	value.resize(count);
	return value;
}

File openRead(const std::wstring& path) {
	auto handle = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
	                          nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
	require(handle != INVALID_HANDLE_VALUE, "cannot read HTTP fixture");
	return File(handle);
}

std::wstring header(HINTERNET request, DWORD name) {
	DWORD size = 0;
	if (!WinHttpQueryHeaders(request, name, WINHTTP_HEADER_NAME_BY_INDEX, nullptr, &size, WINHTTP_NO_HEADER_INDEX)) {
		if (GetLastError() == ERROR_WINHTTP_HEADER_NOT_FOUND) return {};
		require(GetLastError() == ERROR_INSUFFICIENT_BUFFER, "cannot read HTTP headers");
	}
	std::wstring value(size / sizeof(wchar_t), L'\0');
	require(WinHttpQueryHeaders(request, name, WINHTTP_HEADER_NAME_BY_INDEX, value.data(), &size, WINHTTP_NO_HEADER_INDEX) != 0,
	        "cannot read HTTP headers");
	while (!value.empty() && value.back() == L'\0') value.pop_back();
	return value;
}

std::wstring customHeader(HINTERNET request, const wchar_t* name) {
	DWORD size = 0;
	if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_CUSTOM, name, nullptr, &size, WINHTTP_NO_HEADER_INDEX)) {
		if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) return {};
	}
	std::wstring value(size / sizeof(wchar_t), L'\0');
	if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_CUSTOM, name, value.data(), &size, WINHTTP_NO_HEADER_INDEX)) return {};
	while (!value.empty() && value.back() == L'\0') value.pop_back();
	return value;
}

std::wstring lowerHost(std::wstring host) {
	std::transform(host.begin(), host.end(), host.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
	return host;
}

struct Response {
	DWORD status = 0;
	std::wstring location;
	std::wstring length;
	std::wstring etag;
	std::wstring retryAfter;
	std::wstring rateReset;
	std::wstring contentRange;
	Internet connection;
	Internet request;
	File fixture;

	DWORD read(char* buffer, DWORD size) {
		DWORD count = 0;
		if (request) httpRequire(WinHttpReadData(request.get(), buffer, size, &count) != 0, "HTTP download failed");
		else if (fixture) require(ReadFile(fixture.get(), buffer, size, &count, nullptr) != 0, "cannot read HTTP fixture");
		return count;
	}
};

json::JsonObject fixtures(const std::wstring& path) {
	auto file = openRead(path);
	LARGE_INTEGER size {};
	require(GetFileSizeEx(file.get(), &size) != 0 && size.QuadPart >= 0 && size.QuadPart <= 1024 * 1024,
	        "HTTP fixture map exceeds size limit");
	std::string text(static_cast<size_t>(size.QuadPart), '\0');
	DWORD read = 0;
	require(ReadFile(file.get(), text.data(), static_cast<DWORD>(text.size()), &read, nullptr) != 0
	        && read == text.size(), "cannot read HTTP fixture map");
	if (text.rfind("\xEF\xBB\xBF", 0) == 0) text.erase(0, 3);
	json::JsonObject result;
	require(json::JsonObject::TryParse(winrt::to_hstring(text), result), "invalid JSON HTTP fixture map");
	return result;
}

std::wstring outputPath(std::wstring path) {
	// QML's FileUtils.trimFileProtocol can leave /C:/... . Plain path characters stay literal.
	if (path.size() > 3 && path[0] == L'/' && path[2] == L':' && std::iswalpha(path[1])) path.erase(0, 1);
	auto size = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
	require(size != 0, "invalid output path");
	std::wstring result(size, L'\0');
	auto count = GetFullPathNameW(path.c_str(), size, result.data(), nullptr);
	require(count != 0 && count < size, "invalid output path");
	result.resize(count);
	return result;
}

bool existingFile(const std::wstring& path) {
	auto attributes = GetFileAttributesW(path.c_str());
	return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
}

void saveAtomic(const std::wstring& path, const std::string& bytes, bool keep) {
	std::error_code error;
	std::filesystem::create_directories(std::filesystem::path(path).parent_path(), error);
	require(!error, "cannot create output folder");
	auto temp = path + L"." + std::to_wstring(GetCurrentProcessId()) + L"."
	          + std::to_wstring(GetTickCount64()) + L".tmp";
	auto handle = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
	require(handle != INVALID_HANDLE_VALUE, "cannot create temporary output file");
	File file(handle);
	try {
		for (size_t offset = 0; offset < bytes.size();) {
			auto size = static_cast<DWORD>(std::min<size_t>(bytes.size() - offset, 64 * 1024));
			DWORD written = 0;
			require(WriteFile(file.get(), bytes.data() + offset, size, &written, nullptr) != 0 && written == size,
			        "cannot write output file");
			offset += written;
		}
		require(FlushFileBuffers(file.get()) != 0, "cannot flush output file");
		file.reset();
		auto flags = MOVEFILE_WRITE_THROUGH | (keep ? 0 : MOVEFILE_REPLACE_EXISTING);
		if (!MoveFileExW(temp.c_str(), path.c_str(), flags)) {
			auto code = GetLastError();
			// Another downloader may have created the cache entry while this request was in flight.
			if (keep && (code == ERROR_ALREADY_EXISTS || code == ERROR_FILE_EXISTS) && existingFile(path)) {
				DeleteFileW(temp.c_str());
				return;
			}
			throw std::runtime_error("cannot rename output file");
		}
	} catch (...) {
		file.reset();
		DeleteFileW(temp.c_str());
		throw;
	}
}

struct Apartment {
	Apartment() { winrt::init_apartment(winrt::apartment_type::single_threaded); }
	~Apartment() { winrt::uninit_apartment(); }
};

} // namespace

namespace http {

Url parseUrl(const std::wstring& text) {
	require(!hasControl(text) && text.find_first_of(L" \\") == std::wstring::npos, "invalid HTTPS URL");
	URL_COMPONENTS parts {};
	parts.dwStructSize = sizeof(parts);
	parts.dwHostNameLength = parts.dwUrlPathLength = parts.dwExtraInfoLength = static_cast<DWORD>(-1);
	parts.dwUserNameLength = parts.dwPasswordLength = static_cast<DWORD>(-1);
	require(WinHttpCrackUrl(text.c_str(), 0, 0, &parts) != 0, "invalid HTTPS URL");
	require(parts.nScheme == INTERNET_SCHEME_HTTPS, "only HTTPS URLs are allowed");
	require(parts.dwHostNameLength != 0 && parts.dwUserNameLength == 0 && parts.dwPasswordLength == 0,
	        "invalid HTTPS URL");
	Url url;
	url.host.assign(parts.lpszHostName, parts.dwHostNameLength);
	if (parts.dwUrlPathLength) url.path.assign(parts.lpszUrlPath, parts.dwUrlPathLength);
	url.target = url.path.empty() ? L"/" : url.path;
	if (parts.dwExtraInfoLength) url.target.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
	auto fragment = url.target.find(L'#');
	if (fragment != std::wstring::npos) url.target.resize(fragment);
	url.port = parts.nPort;
	return url;
}

struct Client::State {
	Internet session;
	json::JsonObject responses {nullptr};
	std::wstring agent;
	std::vector<std::wstring> hosts; // lower case; empty = any

	void checkHost(const Url& parts) const {
		if (hosts.empty()) return;
		auto host = lowerHost(parts.host);
		require(std::find(hosts.begin(), hosts.end(), host) != hosts.end(), "host not allowed for this request");
	}

	State(const std::wstring& userAgent, bool testing): agent(userAgent) {
		require(!hasControl(agent), "invalid User-Agent");
		if (testing) {
			auto path = env(L"II_HTTP_TEST_RESPONSES");
			require(!path.empty(), "--test requires II_HTTP_TEST_RESPONSES");
			responses = fixtures(path);
		} else {
			session.reset(WinHttpOpen(agent.c_str(), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
			                         WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0));
			require(session != nullptr, "cannot open WinHTTP session");
			require(WinHttpSetTimeouts(session.get(), 20000, 20000, 20000, 20000) != 0, "cannot set HTTP timeouts");
		}
	}

	Response request(const std::wstring& url, const Url& parts, const std::wstring& extraHeaders = L"") {
		checkHost(parts);
		Response response;
		if (responses) {
			require(responses.HasKey(url), "URL missing from HTTP fixture map");
			auto entry = responses.GetNamedObject(url);
			// A conditional request whose ETag matches gets the fixture's "notModified" answer (304).
			auto etag = std::wstring(entry.GetNamedString(L"etag", L""));
			if (!etag.empty() && extraHeaders.find(L"If-None-Match: " + etag) != std::wstring::npos) {
				response.status = 304;
				response.etag = etag;
				return response;
			}
			auto status = entry.GetNamedNumber(L"status");
			require(std::isfinite(status) && status >= 100 && status <= 599 && status == std::floor(status),
			        "invalid fixture HTTP status");
			response.status = static_cast<DWORD>(status);
			response.location = entry.GetNamedString(L"location", L"");
			response.length = entry.GetNamedString(L"contentLength", L"");
			response.etag = etag;
			response.retryAfter = entry.GetNamedString(L"retryAfter", L"");
			if (entry.HasKey(L"agent")) require(std::wstring(entry.GetNamedString(L"agent")) == agent, "incorrect fixture User-Agent");
			auto body = entry.GetNamedString(L"bodyFile", L"");
			if (!body.empty()) response.fixture = openRead(std::wstring(body));
			return response;
		}
		response.connection.reset(WinHttpConnect(session.get(), parts.host.c_str(), parts.port, 0));
		require(response.connection != nullptr, "HTTP connection failed");
		response.request.reset(WinHttpOpenRequest(response.connection.get(), L"GET", parts.target.c_str(), nullptr,
		                                      WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE));
		require(response.request != nullptr, "cannot create HTTP request");
		// Never let WinHTTP follow a redirect before we validate its scheme and credentials.
		DWORD policy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
		require(WinHttpSetOption(response.request.get(), WINHTTP_OPTION_REDIRECT_POLICY, &policy, sizeof(policy)) != 0,
		        "cannot set redirect policy");
		httpRequire(WinHttpSendRequest(response.request.get(), extraHeaders.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : extraHeaders.c_str(),
		                               extraHeaders.empty() ? 0 : static_cast<DWORD>(-1L), WINHTTP_NO_REQUEST_DATA, 0, 0, 0) != 0
		        && WinHttpReceiveResponse(response.request.get(), nullptr) != 0, "HTTP request failed");
		DWORD size = sizeof(response.status);
		require(WinHttpQueryHeaders(response.request.get(), WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
		                           WINHTTP_HEADER_NAME_BY_INDEX, &response.status, &size, WINHTTP_NO_HEADER_INDEX) != 0,
		        "cannot read HTTP status");
		response.location = header(response.request.get(), WINHTTP_QUERY_LOCATION);
		response.length = header(response.request.get(), WINHTTP_QUERY_CONTENT_LENGTH);
		response.etag = header(response.request.get(), WINHTTP_QUERY_ETAG);
		response.retryAfter = header(response.request.get(), WINHTTP_QUERY_RETRY_AFTER);
		response.rateReset = customHeader(response.request.get(), L"X-RateLimit-Reset");
		response.contentRange = customHeader(response.request.get(), L"Content-Range");
		return response;
	}

	// Follows redirects (validated like get()); the final response, its body not read yet.
	Response follow(std::wstring& url, const std::wstring& extraHeaders, ULONGLONG started) {
		for (int redirects = 0; redirects <= 5; ++redirects) {
			auto parts = parseUrl(url);
			auto response = request(url, parts, extraHeaders);
			if (response.status == 301 || response.status == 302 || response.status == 303 || response.status == 307 || response.status == 308) {
				require(!response.location.empty(), "HTTP redirect has no location");
				require(!hasControl(response.location) && response.location.find(L'\\') == std::wstring::npos, "invalid HTTPS redirect URL");
				url = winrt::Windows::Foundation::Uri(url).CombineUri(response.location).AbsoluteUri();
				parseUrl(url);
				require(GetTickCount64() - started < 60000, "HTTP request timed out");
				continue;
			}
			return response;
		}
		throw std::runtime_error("too many HTTP redirects");
	}
};

void Client::allowHosts(std::vector<std::wstring> hosts) {
	for (auto& h: hosts) h = lowerHost(h);
	state_->hosts = std::move(hosts);
}

Reply Client::request(std::wstring url, const std::vector<std::wstring>& headers, size_t cap) {
	std::wstring extra;
	for (const auto& h: headers) {
		require(!hasControl(h) && h.find(L':') != std::wstring::npos, "invalid HTTP header");
		extra += h + L"\r\n";
	}
	auto started = GetTickCount64();
	auto response = state_->follow(url, extra, started);
	Reply reply;
	reply.status = response.status;
	reply.etag = response.etag;
	reply.retryAfter = response.retryAfter;
	reply.rateReset = response.rateReset;
	if (response.status == 304) return reply;
	char buffer[16 * 1024];
	for (;;) {
		require(GetTickCount64() - started < 60000, "HTTP request timed out");
		auto read = response.read(buffer, sizeof(buffer));
		if (!read) break;
		require(read <= cap - std::min(cap, reply.body.size()), "download exceeds size limit");
		reply.body.append(buffer, read);
	}
	return reply;
}

unsigned long long Client::download(std::wstring url, const std::wstring& part, unsigned long long expected,
                                    const std::function<bool(unsigned long long, unsigned long long)>& progress) {
	WIN32_FILE_ATTRIBUTE_DATA info {};
	unsigned long long have = 0;
	if (GetFileAttributesExW(part.c_str(), GetFileExInfoStandard, &info)) have = (static_cast<unsigned long long>(info.nFileSizeHigh) << 32) | info.nFileSizeLow;
	if (expected && have > expected) have = 0; // not this file: start again
	if (expected && have == expected) return have;
	std::wstring extra;
	if (have) extra = L"Range: bytes=" + std::to_wstring(have) + L"-\r\n";
	auto started = GetTickCount64();
	auto response = state_->follow(url, extra, started);
	require(response.status == 200 || response.status == 206, ("HTTP status " + std::to_string(response.status)).c_str());
	if (response.status == 200) have = 0; // the server sent the whole file: the part is replaced
	auto handle = CreateFileW(part.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, have ? OPEN_ALWAYS : CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
	require(handle != INVALID_HANDLE_VALUE, "cannot write the download");
	File file(handle);
	LARGE_INTEGER end {};
	end.QuadPart = static_cast<LONGLONG>(have);
	require(SetFilePointerEx(file.get(), end, nullptr, FILE_BEGIN) != 0 && SetEndOfFile(file.get()) != 0, "cannot write the download");
	auto total = expected;
	if (!total && !response.length.empty()) total = have + byteCount(response.length, "invalid HTTP content length");
	std::vector<char> buffer(256 * 1024);
	auto lastReport = GetTickCount64();
	if (progress && !progress(have, total)) return have;
	for (;;) {
		auto read = response.read(buffer.data(), static_cast<DWORD>(buffer.size()));
		if (!read) break;
		DWORD written = 0;
		require(WriteFile(file.get(), buffer.data(), read, &written, nullptr) != 0 && written == read, "cannot write the download");
		have += read;
		require(!expected || have <= expected, "download larger than expected");
		if (GetTickCount64() - lastReport >= 1000) {
			lastReport = GetTickCount64();
			if (progress && !progress(have, total)) return have;
		}
	}
	FlushFileBuffers(file.get());
	if (progress) progress(have, total);
	return have;
}

Client::Client(const std::wstring& agent, bool testing): state_(std::make_unique<State>(agent, testing)) {}
Client::~Client() = default;

std::string Client::get(std::wstring url, size_t cap) {
	auto started = GetTickCount64();
	for (int redirects = 0; redirects <= 5; ++redirects) {
		auto parts = parseUrl(url);
		auto response = state_->request(url, parts);
		if (response.status == 301 || response.status == 302 || response.status == 303
		    || response.status == 307 || response.status == 308) {
			require(!response.location.empty(), "HTTP redirect has no location");
			require(!hasControl(response.location) && response.location.find(L'\\') == std::wstring::npos,
			        "invalid HTTPS redirect URL");
			url = winrt::Windows::Foundation::Uri(url).CombineUri(response.location).AbsoluteUri();
			parseUrl(url);
			require(GetTickCount64() - started < 60000, "HTTP request timed out");
			continue;
		}
		require(response.status >= 200 && response.status < 300, ("HTTP status " + std::to_string(response.status)).c_str());
		size_t expected = 0;
		if (!response.length.empty()) {
			expected = byteCount(response.length, "invalid HTTP content length");
			require(expected <= cap, "download exceeds size limit");
		}
		std::string bytes;
		char buffer[64 * 1024];
		for (;;) {
			require(GetTickCount64() - started < 60000, "HTTP request timed out");
			auto read = response.read(buffer, sizeof(buffer));
			if (!read) break;
			require(read <= cap - bytes.size(), "download exceeds size limit");
			bytes.append(buffer, read);
		}
		require(response.length.empty() || bytes.size() == expected, "incomplete HTTP download");
		return bytes;
	}
	throw std::runtime_error("too many HTTP redirects");
}

void writeStdout(const std::string& bytes) {
	require(_setmode(_fileno(stdout), _O_BINARY) != -1, "cannot set binary stdout");
	require(std::fwrite(bytes.data(), 1, bytes.size(), stdout) == bytes.size() && std::fflush(stdout) == 0,
	        "cannot write stdout");
}

} // namespace http

int fetch(const std::vector<std::wstring>& args) {
	try {
		const char* usage = "usage: fetch <https-url> [--out <file>] [--keep] [--agent <user-agent>] [--max <bytes>] [--test]";
		require(!args.empty() && !args[0].empty() && args[0].rfind(L"--", 0) != 0, usage);
		bool keep = false, testing = false;
		std::wstring output, agent = L"ii-windows/fetch";
		size_t cap = http::DEFAULT_LIMIT;
		for (size_t i = 1; i < args.size(); ++i) {
			if (args[i] == L"--keep") keep = true;
			else if (args[i] == L"--test") testing = true;
			else if ((args[i] == L"--out" || args[i] == L"--agent" || args[i] == L"--max")
			         && i + 1 < args.size() && args[i + 1].rfind(L"--", 0) != 0) {
				auto flag = args[i];
				auto value = args[++i];
				if (flag == L"--out") { require(!value.empty(), usage); output = value; }
				else if (flag == L"--agent") agent = value;
				else { cap = byteCount(value, "invalid --max byte count"); require(cap != 0, "--max must be positive"); }
			} else throw std::runtime_error(usage);
		}
		require(!keep || !output.empty(), usage);
		require(!hasControl(agent), "invalid User-Agent");
		http::parseUrl(args[0]);
		if (!output.empty()) {
			output = outputPath(output);
			if (keep && existingFile(output)) return 0;
			// Like `mkdir -p` before curl -o: the folder may not exist yet.
			std::error_code ignored;
			std::filesystem::create_directories(std::filesystem::path(output).parent_path(), ignored);
		}
		Apartment apartment;
		http::Client client(agent, testing);
		auto bytes = client.get(args[0], cap);
		if (output.empty()) http::writeStdout(bytes);
		else saveAtomic(output, bytes, keep);
		return 0;
	} catch (const winrt::hresult_error&) {
		std::fputs("fetch: invalid JSON/URL or Windows API failure\n", stderr);
	} catch (const std::exception& error) {
		std::fprintf(stderr, "fetch: %s\n", error.what());
	}
	return 1;
}
