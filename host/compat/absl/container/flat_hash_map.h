// Minimal stand-in for Abseil's flat_hash_map, enough for material-color-utilities
// (quantize/wsmeans.cc only uses find/insert/iteration). Saves pulling in all of Abseil.
#pragma once
#include <unordered_map>

namespace absl {
template <typename K, typename V>
using flat_hash_map = std::unordered_map<K, V>;
} // namespace absl
