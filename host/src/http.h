// Shared HTTPS GET transport. Callers initialize a WinRT apartment for relative redirects.
#pragma once

#include <cstddef>
#include <cstdint>
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

class Client {
public:
	explicit Client(const std::wstring& agent, bool testing = false);
	~Client();
	std::string get(std::wstring url, size_t cap);

private:
	struct State;
	std::unique_ptr<State> state_;
};

// CRT stdout defaults to text mode on Windows: do not translate binary response bytes.
void writeStdout(const std::string& bytes);

} // namespace http

int fetch(const std::vector<std::wstring>& args);
