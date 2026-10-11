#include "jsonlite.h"

#include <cmath>
#include <cstdlib>

namespace jsonlite {

const Value* Value::find(const std::string& key) const {
	for (const auto& member: members) {
		if (member.first == key) return &member.second;
	}
	return nullptr;
}

Value* Value::find(const std::string& key) {
	for (auto& member: members) {
		if (member.first == key) return &member.second;
	}
	return nullptr;
}

Value& Value::set(const std::string& key, Value value) {
	if (auto* existing = find(key)) {
		*existing = std::move(value);
		return *existing;
	}
	members.emplace_back(key, std::move(value));
	return members.back().second;
}

bool Value::erase(const std::string& key) {
	for (auto it = members.begin(); it != members.end(); ++it) {
		if (it->first == key) {
			members.erase(it);
			return true;
		}
	}
	return false;
}

double Value::asDouble() const { return type == Type::Number ? std::strtod(number.c_str(), nullptr) : 0.0; }

bool Value::isInteger() const {
	if (type != Type::Number) return false;
	if (number.find_first_of(".eE") == std::string::npos) return true;
	auto d = asDouble();
	return std::isfinite(d) && d == std::floor(d);
}

namespace {

struct Parser {
	const std::string& s;
	size_t i = 0;
	int maxDepth;
	std::string error;
	size_t errorAt = 0;

	Parser(const std::string& text, int depth): s(text), maxDepth(depth) {}

	bool fail(const char* message) {
		if (error.empty()) {
			error = message;
			errorAt = i;
		}
		return false;
	}

	void skipSpace() {
		while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i;
	}

	static void appendUtf8(std::string& out, unsigned cp) {
		if (cp < 0x80) {
			out += static_cast<char>(cp);
		} else if (cp < 0x800) {
			out += static_cast<char>(0xC0 | (cp >> 6));
			out += static_cast<char>(0x80 | (cp & 0x3F));
		} else if (cp < 0x10000) {
			out += static_cast<char>(0xE0 | (cp >> 12));
			out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
			out += static_cast<char>(0x80 | (cp & 0x3F));
		} else {
			out += static_cast<char>(0xF0 | (cp >> 18));
			out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
			out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
			out += static_cast<char>(0x80 | (cp & 0x3F));
		}
	}

	bool hex4(unsigned& out) {
		if (i + 4 > s.size()) return fail("unexpected end of file in a \\u escape");
		out = 0;
		for (int k = 0; k < 4; ++k) {
			auto c = s[i + static_cast<size_t>(k)];
			unsigned digit;
			if (c >= '0' && c <= '9') digit = static_cast<unsigned>(c - '0');
			else if (c >= 'a' && c <= 'f') digit = static_cast<unsigned>(c - 'a' + 10);
			else if (c >= 'A' && c <= 'F') digit = static_cast<unsigned>(c - 'A' + 10);
			else return fail("bad \\u escape");
			out = out * 16 + digit;
		}
		i += 4;
		return true;
	}

	// One UTF-8 sequence starting at s[i] (a byte >= 0x80), checked for overlong forms, surrogates
	// and the Unicode ceiling, and copied through.
	bool copyUtf8(std::string& out) {
		auto b0 = static_cast<unsigned char>(s[i]);
		size_t length = b0 >= 0xF0 ? 4 : b0 >= 0xE0 ? 3 : b0 >= 0xC2 ? 2 : 0;
		if (length == 0 || b0 > 0xF4) return fail("invalid UTF-8");
		if (i + length > s.size()) return fail("invalid UTF-8 at the end of the file");
		unsigned cp = length == 2 ? (b0 & 0x1Fu) : length == 3 ? (b0 & 0x0Fu) : (b0 & 0x07u);
		for (size_t k = 1; k < length; ++k) {
			auto b = static_cast<unsigned char>(s[i + k]);
			if ((b & 0xC0) != 0x80) return fail("invalid UTF-8");
			cp = (cp << 6) | (b & 0x3Fu);
		}
		if ((length == 3 && cp < 0x800) || (length == 4 && cp < 0x10000) || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return fail("invalid UTF-8");
		out.append(s, i, length);
		i += length;
		return true;
	}

	bool string(std::string& out) {
		++i; // opening quote
		while (true) {
			if (i >= s.size()) return fail("unexpected end of file in a string");
			auto c = static_cast<unsigned char>(s[i]);
			if (c == '"') {
				++i;
				return true;
			}
			if (c < 0x20) return fail("control character in a string");
			if (c >= 0x80) {
				if (!copyUtf8(out)) return false;
				continue;
			}
			if (c != '\\') {
				out += static_cast<char>(c);
				++i;
				continue;
			}
			if (++i >= s.size()) return fail("unexpected end of file in an escape");
			auto e = s[i++];
			switch (e) {
			case '"': out += '"'; break;
			case '\\': out += '\\'; break;
			case '/': out += '/'; break;
			case 'b': out += '\b'; break;
			case 'f': out += '\f'; break;
			case 'n': out += '\n'; break;
			case 'r': out += '\r'; break;
			case 't': out += '\t'; break;
			case 'u': {
				unsigned cp = 0;
				if (!hex4(cp)) return false;
				if (cp >= 0xD800 && cp <= 0xDBFF) {
					unsigned low = 0;
					if (i + 2 > s.size() || s[i] != '\\' || s[i + 1] != 'u') return fail("lone surrogate");
					i += 2;
					if (!hex4(low)) return false;
					if (low < 0xDC00 || low > 0xDFFF) return fail("lone surrogate");
					cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
				} else if (cp >= 0xDC00 && cp <= 0xDFFF) {
					return fail("lone surrogate");
				}
				appendUtf8(out, cp);
				break;
			}
			default: --i; return fail("bad escape");
			}
		}
	}

	bool number(Value& out) {
		auto start = i;
		if (i < s.size() && s[i] == '-') ++i;
		if (i >= s.size()) return fail("unexpected end of file in a number");
		if (s[i] == '0') {
			++i;
		} else if (s[i] >= '1' && s[i] <= '9') {
			while (i < s.size() && s[i] >= '0' && s[i] <= '9') ++i;
		} else {
			return fail("bad number");
		}
		if (i < s.size() && s[i] == '.') {
			++i;
			auto digits = i;
			while (i < s.size() && s[i] >= '0' && s[i] <= '9') ++i;
			if (i == digits) return fail("bad number");
		}
		if (i < s.size() && (s[i] == 'e' || s[i] == 'E')) {
			++i;
			if (i < s.size() && (s[i] == '+' || s[i] == '-')) ++i;
			auto digits = i;
			while (i < s.size() && s[i] >= '0' && s[i] <= '9') ++i;
			if (i == digits) return fail("bad number");
		}
		out.type = Type::Number;
		out.number = s.substr(start, i - start);
		return true;
	}

	bool literal(const char* word, Value& out, Type type, bool boolean) {
		std::string w(word);
		if (s.compare(i, w.size(), w) != 0) return fail("unexpected character");
		i += w.size();
		out.type = type;
		out.boolean = boolean;
		return true;
	}

	bool value(Value& out, int depth) {
		if (depth > maxDepth) return fail("nested too deeply");
		skipSpace();
		if (i >= s.size()) return fail("unexpected end of file");
		auto c = s[i];
		if (c == '{') {
			out.type = Type::Object;
			++i;
			skipSpace();
			if (i < s.size() && s[i] == '}') {
				++i;
				return true;
			}
			while (true) {
				skipSpace();
				if (i >= s.size()) return fail("unexpected end of file in an object");
				if (s[i] != '"') return fail("expected a key");
				std::string key;
				if (!string(key)) return false;
				skipSpace();
				if (i >= s.size() || s[i] != ':') return fail("expected ':'");
				++i;
				Value member;
				if (!value(member, depth + 1)) return false;
				out.set(key, std::move(member));
				skipSpace();
				if (i >= s.size()) return fail("unexpected end of file in an object");
				if (s[i] == ',') {
					++i;
					continue;
				}
				if (s[i] == '}') {
					++i;
					return true;
				}
				return fail("expected ',' or '}'");
			}
		}
		if (c == '[') {
			out.type = Type::Array;
			++i;
			skipSpace();
			if (i < s.size() && s[i] == ']') {
				++i;
				return true;
			}
			while (true) {
				Value item;
				if (!value(item, depth + 1)) return false;
				out.items.push_back(std::move(item));
				skipSpace();
				if (i >= s.size()) return fail("unexpected end of file in an array");
				if (s[i] == ',') {
					++i;
					continue;
				}
				if (s[i] == ']') {
					++i;
					return true;
				}
				return fail("expected ',' or ']'");
			}
		}
		if (c == '"') {
			out.type = Type::String;
			return string(out.text);
		}
		if (c == 't') return literal("true", out, Type::Bool, true);
		if (c == 'f') return literal("false", out, Type::Bool, false);
		if (c == 'n') return literal("null", out, Type::Null, false);
		if (c == '-' || (c >= '0' && c <= '9')) return number(out);
		return fail("unexpected character");
	}
};

void escapeInto(std::string& out, const std::string& text) {
	out += '"';
	for (unsigned char c: text) {
		switch (c) {
		case '"': out += "\\\""; break;
		case '\\': out += "\\\\"; break;
		case '\b': out += "\\b"; break;
		case '\f': out += "\\f"; break;
		case '\n': out += "\\n"; break;
		case '\r': out += "\\r"; break;
		case '\t': out += "\\t"; break;
		default:
			if (c < 0x20) {
				static const char* digits = "0123456789abcdef";
				out += "\\u00";
				out += digits[c >> 4];
				out += digits[c & 15];
			} else {
				out += static_cast<char>(c);
			}
		}
	}
	out += '"';
}

void write(std::string& out, const Value& v, bool pretty, int indent) {
	auto newline = [&](int level) {
		if (!pretty) return;
		out += '\n';
		out.append(static_cast<size_t>(level) * 4, ' ');
	};
	switch (v.type) {
	case Type::Null: out += "null"; break;
	case Type::Bool: out += v.boolean ? "true" : "false"; break;
	case Type::Number: out += v.number.empty() ? "0" : v.number; break;
	case Type::String: escapeInto(out, v.text); break;
	case Type::Array:
		if (v.items.empty()) {
			out += "[]";
			break;
		}
		out += '[';
		for (size_t k = 0; k < v.items.size(); ++k) {
			newline(indent + 1);
			write(out, v.items[k], pretty, indent + 1);
			if (k + 1 < v.items.size()) out += ',';
		}
		newline(indent);
		out += ']';
		break;
	case Type::Object:
		if (v.members.empty()) {
			out += "{}";
			break;
		}
		out += '{';
		for (size_t k = 0; k < v.members.size(); ++k) {
			newline(indent + 1);
			escapeInto(out, v.members[k].first);
			out += pretty ? ": " : ":";
			write(out, v.members[k].second, pretty, indent + 1);
			if (k + 1 < v.members.size()) out += ',';
		}
		newline(indent);
		out += '}';
		break;
	}
}

} // namespace

ParseResult parse(const std::string& text, int maxDepth) {
	ParseResult result;
	Parser parser(text, maxDepth);
	if (text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF && static_cast<unsigned char>(text[1]) == 0xBB && static_cast<unsigned char>(text[2]) == 0xBF) parser.i = 3;
	if (!parser.value(result.value, 0)) {
		result.error = parser.error + " (byte " + std::to_string(parser.errorAt) + ")";
		result.offset = parser.errorAt;
		result.value = Value();
		return result;
	}
	parser.skipSpace();
	if (parser.i != text.size()) {
		result.error = "unexpected data after the end (byte " + std::to_string(parser.i) + ")";
		result.offset = parser.i;
		result.value = Value();
		return result;
	}
	result.ok = true;
	return result;
}

std::string stringify(const Value& value, bool pretty) {
	std::string out;
	write(out, value, pretty, 0);
	if (pretty) out += '\n';
	return out;
}

bool equal(const Value& a, const Value& b) {
	if (a.type != b.type) return false;
	switch (a.type) {
	case Type::Null: return true;
	case Type::Bool: return a.boolean == b.boolean;
	case Type::Number: return a.number == b.number || a.asDouble() == b.asDouble();
	case Type::String: return a.text == b.text;
	case Type::Array:
		if (a.items.size() != b.items.size()) return false;
		for (size_t k = 0; k < a.items.size(); ++k) {
			if (!equal(a.items[k], b.items[k])) return false;
		}
		return true;
	case Type::Object:
		if (a.members.size() != b.members.size()) return false;
		for (const auto& member: a.members) {
			const auto* other = b.find(member.first);
			if (!other || !equal(member.second, *other)) return false;
		}
		return true;
	}
	return false;
}

} // namespace jsonlite
