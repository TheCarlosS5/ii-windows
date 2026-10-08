// Minimal stand-in for Abseil's StrCat/Hex, enough for material-color-utilities
// (utils.cc: HexFromArgb). Saves pulling in all of Abseil.
#pragma once
#include <cstdint>
#include <cstdio>
#include <string>

namespace absl {
struct Hex {
	explicit Hex(uint32_t value): value(value) {}
	uint32_t value;
};
inline std::string StrCat(const Hex& hex) {
	char buffer[16];
	std::snprintf(buffer, sizeof(buffer), "%x", hex.value);
	return buffer;
}
} // namespace absl
