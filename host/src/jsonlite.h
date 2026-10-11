// A small strict JSON reader/writer for the config tools (configtool.cpp). ii-host and ii-shim have no
// JSON dependency of their own and the config tools must be testable without WinRT, so this is the
// whole of what they need: RFC 8259 text in, an ordered tree out, and text back with the numbers
// exactly as they were written (no double round trip). Qt's own parser is what ii's loader uses, so
// this one is as strict as that: no comments, no trailing commas, no NaN, no leading zeros, valid
// UTF-8 only. It never throws.
#pragma once

#include <string>
#include <utility>
#include <vector>

namespace jsonlite {

enum class Type { Null, Bool, Number, String, Array, Object };

struct Value {
	Type type = Type::Null;
	bool boolean = false;
	std::string number;  // as written, e.g. "0.18" or "1e3"
	std::string text;    // UTF-8
	std::vector<Value> items;
	std::vector<std::pair<std::string, Value>> members; // in file order; keys unique (the last duplicate wins)

	[[nodiscard]] const Value* find(const std::string& key) const;
	Value* find(const std::string& key);
	Value& set(const std::string& key, Value value); // adds at the end, or replaces in place
	bool erase(const std::string& key);
	[[nodiscard]] bool isObject() const { return type == Type::Object; }
	[[nodiscard]] bool isInteger() const; // a Number written without fraction/exponent, or with a zero one
	[[nodiscard]] double asDouble() const;

	static Value makeObject() { Value v; v.type = Type::Object; return v; }
	static Value makeArray() { Value v; v.type = Type::Array; return v; }
	static Value makeString(std::string s) { Value v; v.type = Type::String; v.text = std::move(s); return v; }
	static Value makeNumber(std::string s) { Value v; v.type = Type::Number; v.number = std::move(s); return v; }
	static Value makeBool(bool b) { Value v; v.type = Type::Bool; v.boolean = b; return v; }
};

struct ParseResult {
	bool ok = false;
	std::string error; // "unexpected character at byte 12", "unexpected end of file", ...
	size_t offset = 0;
	Value value;
};

ParseResult parse(const std::string& text, int maxDepth = 64);
// 4-space indentation like Qt's writer; compact when pretty is false.
std::string stringify(const Value& value, bool pretty = true);
bool equal(const Value& a, const Value& b);

} // namespace jsonlite
