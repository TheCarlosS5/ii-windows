// Shared HTTPS GET transport. Callers initialize a WinRT apartment for relative redirects.
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace http {

constexpr size_t DEFAULT_LIMIT = 40 * 1024 * 1024;

struct Url {
	std::wstring host;
	std::wstring target;
	std::wstring path;
	uint16_t port;
};

Url parseUrl(const std::wstring& text); // HTTPS only, no credentials or control characters.

// Plan 2026-10-31, B2/B4: what the updater needs beyond get().
struct Reply {
	unsigned long status = 0;
	std::wstring etag;
	std::wstring retryAfter; // seconds, as sent
	std::wstring rateReset;  // X-RateLimit-Reset (epoch seconds), as sent
	std::string body;
};

class Client {
public:
	explicit Client(const std::wstring& agent, bool testing = false);
	~Client();
	std::string get(std::wstring url, size_t cap);
	// Every URL (and every redirect) must be on one of these hosts; empty = any HTTPS host.
	void allowHosts(std::vector<std::wstring> hosts);
	// GET with extra request headers ("Name: value"); any status is returned (redirects are followed), the body up to cap.
	Reply request(std::wstring url, const std::vector<std::wstring>& headers, size_t cap);
	// Downloads to `part`, resuming from its current size (Range); a server that answers 200 instead of 206 starts it
	// again. progress(done, total) is called now and then; returning false stops (the part stays for later). Returns
	// the final size. Throws on HTTP errors.
	unsigned long long download(std::wstring url, const std::wstring& part, unsigned long long expected,
	                            const std::function<bool(unsigned long long, unsigned long long)>& progress);

private:
	struct State;
	std::unique_ptr<State> state_;
};

// CRT stdout defaults to text mode on Windows: do not translate binary response bytes.
void writeStdout(const std::string& bytes);

} // namespace http

int fetch(const std::vector<std::wstring>& args);
