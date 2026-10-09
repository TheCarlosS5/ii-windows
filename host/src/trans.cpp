// translate-shell subset used by sidebarLeft/Translator.qml, with Google GTX.
// stdout is UTF-8, one language name per line or the translated text, no ANSI.
#include "http.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cwctype>
#include <future>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
// clang-format off
#include <winrt/base.h>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.Collections.h>
// clang-format on

namespace {

namespace json = winrt::Windows::Data::Json;
using Args = std::vector<std::wstring>;

struct Language { const wchar_t* code; const wchar_t* name; };
// Fixed Google language table, including translate-shell's regional aliases.
// Keep codes internal: QML stores each complete output line as a language name.
constexpr Language languages[] = {
	{L"af", L"Afrikaans"}, {L"sq", L"Albanian"}, {L"am", L"Amharic"}, {L"ar", L"Arabic"},
	{L"hy", L"Armenian"}, {L"as", L"Assamese"}, {L"ay", L"Aymara"}, {L"az", L"Azerbaijani"},
	{L"bm", L"Bambara"}, {L"eu", L"Basque"}, {L"be", L"Belarusian"}, {L"bn", L"Bengali"},
	{L"bho", L"Bhojpuri"}, {L"bs", L"Bosnian"}, {L"bg", L"Bulgarian"}, {L"ca", L"Catalan"},
	{L"ceb", L"Cebuano"}, {L"ny", L"Chichewa"}, {L"zh-CN", L"Chinese (Simplified)"},
	{L"zh-TW", L"Chinese (Traditional)"}, {L"co", L"Corsican"}, {L"hr", L"Croatian"},
	{L"cs", L"Czech"}, {L"da", L"Danish"}, {L"dv", L"Dhivehi"}, {L"doi", L"Dogri"},
	{L"nl", L"Dutch"}, {L"en", L"English"}, {L"eo", L"Esperanto"}, {L"et", L"Estonian"},
	{L"ee", L"Ewe"}, {L"tl", L"Filipino"}, {L"fi", L"Finnish"}, {L"fr", L"French"},
	{L"fy", L"Frisian"}, {L"gl", L"Galician"}, {L"ka", L"Georgian"}, {L"de", L"German"},
	{L"el", L"Greek"}, {L"gn", L"Guarani"}, {L"gu", L"Gujarati"}, {L"ht", L"Haitian Creole"},
	{L"ha", L"Hausa"}, {L"haw", L"Hawaiian"}, {L"he", L"Hebrew"}, {L"hi", L"Hindi"},
	{L"hmn", L"Hmong"}, {L"hu", L"Hungarian"}, {L"is", L"Icelandic"}, {L"ig", L"Igbo"},
	{L"ilo", L"Ilocano"}, {L"id", L"Indonesian"}, {L"ga", L"Irish"}, {L"it", L"Italian"},
	{L"ja", L"Japanese"}, {L"jv", L"Javanese"}, {L"kn", L"Kannada"}, {L"kk", L"Kazakh"},
	{L"km", L"Khmer"}, {L"rw", L"Kinyarwanda"}, {L"gom", L"Konkani"}, {L"ko", L"Korean"},
	{L"kri", L"Krio"}, {L"ku", L"Kurdish (Kurmanji)"}, {L"ckb", L"Kurdish (Sorani)"},
	{L"ky", L"Kyrgyz"}, {L"lo", L"Lao"}, {L"la", L"Latin"}, {L"lv", L"Latvian"},
	{L"ln", L"Lingala"}, {L"lt", L"Lithuanian"}, {L"lg", L"Luganda"}, {L"lb", L"Luxembourgish"},
	{L"mk", L"Macedonian"}, {L"mai", L"Maithili"}, {L"mg", L"Malagasy"}, {L"ms", L"Malay"},
	{L"ml", L"Malayalam"}, {L"mt", L"Maltese"}, {L"mi", L"Maori"}, {L"mr", L"Marathi"},
	{L"mni-Mtei", L"Meiteilon (Manipuri)"}, {L"lus", L"Mizo"}, {L"mn", L"Mongolian"},
	{L"my", L"Myanmar (Burmese)"}, {L"ne", L"Nepali"}, {L"no", L"Norwegian"},
	{L"or", L"Odia (Oriya)"}, {L"om", L"Oromo"}, {L"ps", L"Pashto"}, {L"fa", L"Persian"},
	{L"pl", L"Polish"}, {L"pt", L"Portuguese"}, {L"pt-BR", L"Portuguese (Brazilian)"},
	{L"pt-PT", L"Portuguese (European)"}, {L"pa", L"Punjabi"}, {L"qu", L"Quechua"},
	{L"ro", L"Romanian"}, {L"ru", L"Russian"}, {L"sm", L"Samoan"}, {L"sa", L"Sanskrit"},
	{L"gd", L"Scots Gaelic"}, {L"nso", L"Sepedi"}, {L"sr", L"Serbian"}, {L"st", L"Sesotho"},
	{L"sn", L"Shona"}, {L"sd", L"Sindhi"}, {L"si", L"Sinhala"}, {L"sk", L"Slovak"},
	{L"sl", L"Slovenian"}, {L"so", L"Somali"}, {L"es", L"Spanish"}, {L"su", L"Sundanese"},
	{L"sw", L"Swahili"}, {L"sv", L"Swedish"}, {L"tg", L"Tajik"}, {L"ta", L"Tamil"},
	{L"tt", L"Tatar"}, {L"te", L"Telugu"}, {L"th", L"Thai"}, {L"ti", L"Tigrinya"},
	{L"ts", L"Tsonga"}, {L"tr", L"Turkish"}, {L"tk", L"Turkmen"}, {L"ak", L"Twi"},
	{L"uk", L"Ukrainian"}, {L"ur", L"Urdu"}, {L"ug", L"Uyghur"}, {L"uz", L"Uzbek"},
	{L"vi", L"Vietnamese"}, {L"cy", L"Welsh"}, {L"xh", L"Xhosa"}, {L"yi", L"Yiddish"},
	{L"yo", L"Yoruba"}, {L"zu", L"Zulu"}
};

void require(bool ok, const char* reason) {
	if (!ok) throw std::runtime_error(reason);
}

std::wstring lower(std::wstring text) {
	for (auto& c: text) c = static_cast<wchar_t>(std::towlower(c));
	return text;
}

std::wstring languageCode(std::wstring value) {
	auto key = lower(value);
	std::replace(key.begin(), key.end(), L'_', L'-');
	if (key.empty() || key == L"auto") return L"auto";
	if (key == L"zh" || key == L"chinese") return L"zh-CN";
	if (key == L"iw") return L"he";
	if (key == L"in") return L"id";
	if (key == L"jw") return L"jv";
	if (key == L"fil" || key == L"tagalog") return L"tl";
	if (key == L"kurdish") return L"ku";
	for (const auto& language: languages) {
		if (key == lower(language.code) || key == lower(language.name)) return language.code;
	}
	throw std::runtime_error("unknown language: " + winrt::to_string(value));
}

std::wstring hostLanguage() {
	wchar_t locale[LOCALE_NAME_MAX_LENGTH] {}, code[16] {};
	if (GetUserDefaultLocaleName(locale, LOCALE_NAME_MAX_LENGTH)
	    && GetLocaleInfoEx(locale, LOCALE_SISO639LANGNAME, code, 16)) {
		try {
			if (std::wstring(code) == L"zh") {
				auto name = std::wstring(locale);
				return name.find(L"TW") != name.npos || name.find(L"HK") != name.npos
				    || name.find(L"MO") != name.npos || name.find(L"Hant") != name.npos ? L"zh-TW" : L"zh-CN";
			}
			if (std::wstring(code) == L"nb" || std::wstring(code) == L"nn") return L"no";
			return languageCode(code);
		} catch (const std::runtime_error&) {} // locale unsupported by the fixed table
	}
	return L"en";
}

std::wstring encode(const std::wstring& text) {
	const wchar_t* hex = L"0123456789ABCDEF";
	std::wstring result;
	for (unsigned char c: winrt::to_string(text)) {
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
		    || c == '-' || c == '_' || c == '.' || c == '~') result += wchar_t(c);
		else { result += L'%'; result += hex[c >> 4]; result += hex[c & 15]; }
	}
	return result;
}

struct Options {
	std::wstring source = L"auto", target = L"auto", text;
	bool list = false, codes = false, all = false, engines = false;
};

Options options(const Args& args) {
	Options result;
	bool literal = false, hasText = false, directionAllowed = true;
	for (size_t i = 0; i < args.size(); ++i) {
		const auto& arg = args[i];
		if (!literal && !hasText) {
			if (arg == L"--") { literal = true; continue; }
			if (arg == L"-brief" || arg == L"-b" || arg == L"-no-bidi") continue;
			if (arg == L"-list-languages" || arg == L"-list-languages-english") { result.list = true; continue; }
			if (arg == L"-list-codes") { result.codes = true; continue; }
			if (arg == L"-list-all") { result.all = true; continue; }
			if (arg == L"-list-engines") { result.engines = true; continue; }
			if (arg == L"-e" || arg == L"-engine" || arg == L"-source" || arg == L"-s"
			    || arg == L"-target" || arg == L"-t") {
				require(i + 1 < args.size(), "missing option value");
				auto value = args[++i];
				if (arg == L"-source" || arg == L"-s") { result.source = languageCode(value); directionAllowed = false; }
				else if (arg == L"-target" || arg == L"-t") { result.target = languageCode(value); directionAllowed = false; }
				else require(lower(value) == L"google" || lower(value) == L"auto", "only google and auto engines are supported");
				continue;
			}
			auto colon = arg.find(L':');
			if (directionAllowed && colon != arg.npos && arg.find(L':', colon + 1) == arg.npos) {
				try {
					auto source = languageCode(arg.substr(0, colon));
					auto target = languageCode(arg.substr(colon + 1));
					result.source = source; result.target = target;
					directionAllowed = false;
					continue;
				} catch (const std::runtime_error&) {
					// A leading/trailing colon is an explicit direction; ordinary
					// prose/URLs with a colon must remain literal translation text.
					if (colon == 0 || colon + 1 == arg.size()) throw;
				}
			}
			require(arg.empty() || arg[0] != L'-', "unsupported option (use -- before literal text)");
		}
		if (hasText) result.text += L' ';
		result.text += arg; hasText = true;
	}
	if (!(result.list || result.codes || result.all || result.engines)) {
		require(hasText && !result.text.empty(), "usage: trans -brief [-e google|auto] [source:target] <text>");
		require(result.text.size() <= 16384, "text exceeds 16384 UTF-16 code units");
		if (result.target == L"auto") result.target = hostLanguage();
	}
	return result;
}

std::string translation(const std::string& bytes) {
	json::JsonArray root;
	require(json::JsonArray::TryParse(winrt::to_hstring(bytes), root), "invalid JSON from Google Translate");
	require(root.Size() && root.GetAt(0).ValueType() == json::JsonValueType::Array, "missing translation array");
	auto segments = root.GetArrayAt(0);
	std::string text;
	for (const auto& segment: segments) {
		require(segment.ValueType() == json::JsonValueType::Array, "invalid translation segment");
		auto array = segment.GetArray();
		require(array.Size() != 0, "empty translation segment");
		if (array.GetAt(0).ValueType() == json::JsonValueType::Null) continue;
		require(array.GetAt(0).ValueType() == json::JsonValueType::String, "invalid translation text");
		text += winrt::to_string(array.GetStringAt(0));
	}
	require(!text.empty(), "empty translation from Google Translate");
	if (text.back() != '\n') text += '\n';
	return text;
}

struct Apartment {
	Apartment() { winrt::init_apartment(winrt::apartment_type::single_threaded); }
	~Apartment() { winrt::uninit_apartment(); }
};

std::string translateWithinDeadline(const Options& opts) {
	auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
	std::promise<std::string> promise;
	auto result = promise.get_future();
	std::thread worker([opts, completion = std::move(promise)]() mutable {
		try {
			std::string text;
			{
				Apartment apartment;
				http::Client client(L"ii-windows/trans");
				auto url = L"https://translate.googleapis.com/translate_a/single?client=gtx&sl=" + encode(opts.source)
				         + L"&tl=" + encode(opts.target) + L"&dt=t&q=" + encode(opts.text);
				text = translation(client.get(url, 1024 * 1024));
			} // include transport cleanup in the deadline, before publishing the result
			completion.set_value(std::move(text));
		} catch (...) { completion.set_exception(std::current_exception()); }
	});
	if (result.wait_until(deadline) != std::future_status::ready) {
		// http.h exposes no timeout control (its transport waits up to 20s per
		// stage). The worker owns all state and never writes stdout/stderr.
		// Return to ii-shim's wmain after 8s; normal process exit disposes of
		// the outstanding request. No unsafe thread/process termination API.
		worker.detach();
		throw std::runtime_error("Google Translate request timed out after 8 seconds");
	}
	worker.join();
	return result.get();
}

Args shellWords(const std::wstring& command) {
	// Only split literal shell words. QML escapes apostrophes as '\''.
	// Never invoke a shell, expand variables, redirect, or execute a pipeline.
	Args words;
	std::wstring word;
	wchar_t quote = 0;
	bool started = false;
	for (size_t i = 0; i < command.size(); ++i) {
		auto c = command[i];
		if (quote == L'\'') {
			if (c == quote) quote = 0; else word += c;
		} else if (c == L'\\') {
			require(i + 1 < command.size(), "incomplete quoted command");
			word += command[++i]; started = true;
		} else if (quote == L'"') {
			if (c == quote) quote = 0;
			else { require(c != L'$' && c != L'`', "shell expansion is unsupported"); word += c; }
		} else if (c == L'\'' || c == L'"') { quote = c; started = true; }
		else if (c == L' ' || c == L'\t') {
			if (started) { words.push_back(word); word.clear(); started = false; }
		} else {
			require(std::wstring(L"&|;<>$`()\r\n*?[]~").find(c) == std::wstring::npos, "shell syntax is unsupported");
			word += c; started = true;
		}
	}
	require(quote == 0, "unterminated quoted command");
	if (started) words.push_back(word);
	require(!words.empty() && words[0] == L"trans", "only a literal trans command is supported");
	words.erase(words.begin());
	// Translator.qml always ends this exact invocation with one quoted text
	// argument. Preserve its literal status even if it is "-brief" or ":es".
	if (words.size() == 7 && words[0] == L"-brief" && words[1] == L"-no-bidi"
	    && words[2] == L"-source" && words[4] == L"-target") words.insert(words.begin() + 6, L"--");
	return words;
}

int selftest() {
	Apartment apartment;
	require(languageCode(L"Spanish") == L"es" && languageCode(L"zh_TW") == L"zh-TW", "selftest: language mapping");
	for (const auto& language: languages)
		require(languageCode(language.name) == language.code, "selftest: selectable name must map back to its code");
	require(encode(L"hola &\n\u4e16\u754c") == L"hola%20%26%0A%E4%B8%96%E7%95%8C", "selftest: UTF-8 query encoding");
	auto opts = options({L"-brief", L"-no-bidi", L"-e", L"google", L"en:es", L"hello world"});
	require(opts.source == L"en" && opts.target == L"es" && opts.text == L"hello world", "selftest: colon arguments");
	auto qml = shellWords(L"trans -brief -no-bidi -source 'auto' -target 'Spanish' 'it'\\''s $literal; text\nnext'");
	opts = options(qml);
	require(opts.source == L"auto" && opts.target == L"es" && opts.text == L"it's $literal; text\nnext", "selftest: QML literal quoting");
	opts = options(shellWords(L"trans -brief -no-bidi -source 'English' -target 'Spanish' '-list-languages'"));
	require(!opts.list && opts.text == L"-list-languages", "selftest: option-looking QML text");
	opts = options({L"-brief", L"-source", L"English", L"-target", L"Spanish", L"Time: 12"});
	require(opts.source == L"en" && opts.target == L"es" && opts.text == L"Time: 12", "selftest: colon inside QML text");
	opts = options({L"-brief", L":es", L"Time:12"});
	require(opts.target == L"es" && opts.text == L"Time:12", "selftest: colon after direction");
	opts = options({L"-brief", L"Time:12"});
	require(opts.text == L"Time:12", "selftest: literal colon without direction");
	require(translation(R"([[["Hola ","Hello ",null,null,1],["mundo!\n","world!\n",null,null,1]],null,"en"])" ) == "Hola mundo!\n",
	        "selftest: multiple JSON segments/newline");
	require(translation(R"([[["\u4e16\u754c \"ok\"","world",null,null,1]],null,"en"])" ) == "\xE4\xB8\x96\xE7\x95\x8C \"ok\"\n",
	        "selftest: Unicode JSON escapes");
	bool rejected = false;
	try { shellWords(L"trans :es hello; bogus"); } catch (const std::runtime_error&) { rejected = true; }
	require(rejected, "selftest: unquoted shell syntax");
	rejected = false;
	try { translation("[null]"); } catch (const std::runtime_error&) { rejected = true; }
	require(rejected, "selftest: malformed translation");
	std::fputs("trans selftest: PASS (arguments, languages, UTF-8, JSON, QML quoting)\n", stdout);
	return 0;
}

} // namespace

int trans(const std::vector<std::wstring>& args) {
	try {
		if (args.size() == 1 && args[0] == L"--selftest") return selftest();
		auto opts = options(args);
		if (opts.list || opts.codes || opts.all || opts.engines) {
			std::string text;
			if (opts.engines) text = "auto\ngoogle\n";
			else {
				text = opts.all ? "auto\tauto\n" : "auto\n";
				for (const auto& language: languages) {
					if (opts.codes || opts.all) text += winrt::to_string(language.code);
					if (opts.all) text += '\t';
					if (!opts.codes || opts.all) text += winrt::to_string(language.name);
					text += '\n';
				}
			}
			http::writeStdout(text);
		} else http::writeStdout(translateWithinDeadline(opts));
		return 0;
	} catch (const winrt::hresult_error&) {
		std::fputs("trans: invalid JSON/Unicode or Windows API failure\n", stderr);
	} catch (const std::exception& error) {
		std::fprintf(stderr, "trans: %s\n", error.what());
	}
	return 1;
}

// Add a single guarded call from shim.cpp's existing bash() dispatcher.
int transShellCommand(const std::wstring& command) {
	try { return trans(shellWords(command)); }
	catch (const std::exception& error) {
		std::fprintf(stderr, "trans: %s\n", error.what());
		return 127;
	}
}
