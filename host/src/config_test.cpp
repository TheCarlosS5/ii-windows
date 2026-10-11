// Checks of the config tools (D01): the JSON reader, the schema validation, the guard / last-good
// logic, export and import. Everything happens in a throwaway folder (II_CONFIG_DIR); the real
// config.json is never read or written. Build: cmake --build host\build --target ii-config-test.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include "configtool.h"
#include "jsonlite.h"

using namespace configtool;

static int failed = 0;
static int total = 0;

static void check(bool ok, const std::string& what) {
	++total;
	if (!ok) {
		++failed;
		std::printf("FAIL %s\n", what.c_str());
	}
}

static std::wstring root;
static std::wstring dir;

static std::string slurp(const std::wstring& path) {
	std::string out;
	HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, 0, nullptr);
	if (h == INVALID_HANDLE_VALUE) return "<missing>";
	char buffer[4096];
	DWORD got = 0;
	while (ReadFile(h, buffer, sizeof(buffer), &got, nullptr) && got) out.append(buffer, got);
	CloseHandle(h);
	return out;
}

static void put(const std::wstring& path, const std::string& bytes) {
	HANDLE h = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
	DWORD wrote = 0;
	if (h != INVALID_HANDLE_VALUE) {
		WriteFile(h, bytes.data(), static_cast<DWORD>(bytes.size()), &wrote, nullptr);
		CloseHandle(h);
	}
}

static std::vector<std::wstring> names(const std::wstring& folder, const std::wstring& pattern = L"*") {
	std::vector<std::wstring> out;
	WIN32_FIND_DATAW data;
	HANDLE f = FindFirstFileW((folder + L"\\" + pattern).c_str(), &data);
	if (f == INVALID_HANDLE_VALUE) return out;
	do {
		if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) out.emplace_back(data.cFileName);
	} while (FindNextFileW(f, &data));
	FindClose(f);
	return out;
}

static bool has(const std::string& text, const std::string& needle) { return text.find(needle) != std::string::npos; }

// A fresh, empty configuration folder; returns its path.
static std::wstring fresh(const wchar_t* name) {
	dir = root + L"\\" + name;
	CreateDirectoryW(dir.c_str(), nullptr);
	for (const auto& n: names(dir)) DeleteFileW((dir + L"\\" + n).c_str());
	SetEnvironmentVariableW(L"II_CONFIG_DIR", dir.c_str());
	SetEnvironmentVariableW(L"II_CONFIG_TEST_FAULT", nullptr);
	return dir;
}

static const char* GOOD = R"({
    "configVersion": 1,
    "bar": {"workspaces": {"shown": 10, "monochromeIcons": true}, "screenList": ["\\\\.\\DISPLAY1"]},
    "policies": {"ai": 1, "weeb": 1},
    "background": {"wallpaperPath": ""}
})";

static void testJson() {
	using namespace jsonlite;
	auto ok = [](const std::string& text) { return parse(text).ok; };
	check(ok("{}") && ok("[]") && ok("  {\"a\": [1, 2.5, -3e2, true, false, null, \"x\"]}  "), "json: ordinary documents parse");
	check(!ok("") && !ok("{") && !ok("{\"a\":") && !ok("{\"a\": 1,}") && !ok("[1,]") && !ok("{\"a\": 1} x"), "json: truncated documents, trailing commas and trailing data are errors");
	check(!ok("{\"a\": 01}") && !ok("{\"a\": .5}") && !ok("{\"a\": NaN}") && !ok("{\"a\": 1.}") && !ok("{'a': 1}"), "json: bad numbers, NaN and single quotes are errors");
	check(!ok("// c\n{}") && !ok("{ /* c */ }"), "json: comments are errors (as in Qt's parser)");
	check(!ok("\"\xC0\x80\"") && !ok("\"\xED\xA0\x80\"") && !ok("\"\xFF\""), "json: overlong, surrogate and invalid UTF-8 are errors");
	check(!ok("\"\\ud800\"") && !ok("\"\\udc00\"") && !ok("\"\\x\""), "json: lone surrogates and bad escapes are errors");
	check(!ok(std::string(200, '[') + std::string(200, ']')), "json: 200 levels of nesting are refused");
	auto r = parse("\xEF\xBB\xBF{\"a\":\"\\u00e9\\ud83d\\ude00\"}");
	check(r.ok && r.value.find("a") && r.value.find("a")->text == "\xC3\xA9\xF0\x9F\x98\x80", "json: BOM skipped, \\u escapes (with a surrogate pair) become UTF-8");
	auto n = parse("{\"x\": 0.18, \"y\": 1e3, \"z\": 10}");
	auto text = stringify(n.value);
	check(has(text, "0.18") && has(text, "1e3") && has(text, "10") && !has(text, "1000"), "json: numbers are written back exactly as they were");
	auto again = parse(text);
	check(again.ok && equal(again.value, n.value), "json: write then read gives the same tree");
	auto dup = parse("{\"a\": 1, \"a\": 2}");
	check(dup.ok && dup.value.members.size() == 1 && dup.value.find("a")->number == "2", "json: a repeated key keeps the last value, once");
	Value odd = Value::makeObject();
	odd.set("s", Value::makeString("q\"\\\n\t\x01"));
	auto back = parse(stringify(odd, false));
	check(back.ok && back.value.find("s")->text == "q\"\\\n\t\x01", "json: quotes, backslashes and control characters survive");
	check(parse("{\"a\": 3.0}").value.find("a")->isInteger() && !parse("{\"a\": 3.5}").value.find("a")->isInteger(), "json: 3.0 counts as an integer, 3.5 does not");
}

static std::vector<Problem> problemsOf(const char* json) {
	auto parsed = jsonlite::parse(json);
	return validate(parsed.value);
}

static bool hasProblem(const std::vector<Problem>& ps, const std::string& path, const std::string& kind) {
	for (const auto& p: ps) if (p.path == path && p.kind == kind) return true;
	return false;
}

static void testValidate() {
	check(problemsOf(GOOD).empty(), "validate: a good file has no problems");
	check(problemsOf("{\"somethingNew\": {\"x\": [1,2]}, \"bar\": {\"futureOption\": 3}}").empty(), "validate: options this build does not know are not problems");
	auto p = problemsOf("{\"bar\": {\"workspaces\": {\"shown\": \"ten\"}}}");
	check(hasProblem(p, "bar.workspaces.shown", "type") && p[0].severity == Severity::Error, "validate: a string where an integer belongs is an error");
	check(hasProblem(problemsOf("{\"bar\": {\"workspaces\": {\"shown\": 7.5}}}"), "bar.workspaces.shown", "type"), "validate: 7.5 is not an integer");
	check(hasProblem(problemsOf("{\"bar\": {\"workspaces\": {\"monochromeIcons\": 1}}}"), "bar.workspaces.monochromeIcons", "type"), "validate: 1 is not a boolean");
	check(hasProblem(problemsOf("{\"bar\": 3}"), "bar", "type"), "validate: a number where an object belongs is an error");
	check(hasProblem(problemsOf("{\"bar\": {\"workspaces\": []}}"), "bar.workspaces", "type"), "validate: a list where an object belongs is an error");
	check(hasProblem(problemsOf("{\"bar\": {\"screenList\": [1, 2]}}"), "bar.screenList", "type"), "validate: a list of numbers where strings belong is an error");
	check(hasProblem(problemsOf("{\"bar\": {\"workspaces\": {\"shown\": null}}}"), "bar.workspaces.shown", "type"), "validate: null is not a value");
	auto w = problemsOf("{\"bar\": {\"workspaces\": {\"shown\": 99}}, \"policies\": {\"ai\": 7}}");
	check(hasProblem(w, "bar.workspaces.shown", "range") && hasProblem(w, "policies.ai", "enum"), "validate: out-of-range and out-of-enumeration values are reported");
	check(w.size() == 2 && w[0].severity == Severity::Warning && w[1].severity == Severity::Warning, "validate: and they are warnings, not errors (a hand-edited value may be deliberate)");
	check(validate(jsonlite::parse("[1]").value).size() == 1, "validate: a top level that is not an object is a problem");
	check(problemsOf("{\"configVersion\": \"one\"}").size() == 1, "validate: configVersion must be an integer");
}

static void testGuard() {
	// missing
	fresh(L"guard-missing");
	check(guard().action == Outcome::Action::Missing, "guard: no file yet is not a problem");

	// valid, unversioned: untouched, one copy kept of the unversioned state
	fresh(L"guard-valid");
	std::string unversioned = "{\"bar\": {\"workspaces\": {\"shown\": 12}}}\n";
	put(dir + L"\\config.json", unversioned);
	auto o = guard();
	check(o.action == Outcome::Action::Nothing && slurp(dir + L"\\config.json") == unversioned, "guard: a valid file is not touched");
	check(slurp(dir + L"\\config.pre-v1.json") == unversioned, "guard: the first sight of an unversioned file keeps a copy as it was");
	put(dir + L"\\config.json", "{\"configVersion\": 1}");
	guard();
	check(slurp(dir + L"\\config.pre-v1.json") == unversioned, "guard: that copy is not overwritten later");

	// truncated file with a last good
	fresh(L"guard-restore");
	put(dir + L"\\config.last-good.json", GOOD);
	std::string truncated = std::string(GOOD).substr(0, 60);
	put(dir + L"\\config.json", truncated);
	o = guard();
	check(o.action == Outcome::Action::RestoredLastGood && o.userShouldKnow(), "guard: a truncated file is replaced by the last good one, and the user is told");
	check(slurp(dir + L"\\config.json") == GOOD, "guard: config.json is the last good one, byte for byte");
	auto aside = names(dir, L"config.json.invalid-*");
	check(aside.size() == 1 && slurp(dir + L"\\" + aside[0]) == truncated, "guard: the damaged file is kept aside, unchanged");

	// damaged, nothing to restore
	fresh(L"guard-defaults");
	put(dir + L"\\config.json", "not json at all");
	o = guard();
	check(o.action == Outcome::Action::StartedFromDefaults && slurp(dir + L"\\config.json") == "<missing>", "guard: damaged with no last good: kept aside, ii starts from its defaults");
	check(names(dir, L"config.json.invalid-*").size() == 1, "guard: and the damaged file is kept");

	// a last good that is itself damaged is not used
	fresh(L"guard-bad-lastgood");
	put(dir + L"\\config.last-good.json", "{ broken");
	put(dir + L"\\config.json", "{ also broken");
	check(guard().action == Outcome::Action::StartedFromDefaults, "guard: a damaged last good copy is not put back");

	// a last good with wrong-typed options is not used either
	fresh(L"guard-typed-lastgood");
	put(dir + L"\\config.last-good.json", "{\"bar\": {\"workspaces\": {\"shown\": \"x\"}}}");
	put(dir + L"\\config.json", "{ broken");
	check(guard().action == Outcome::Action::StartedFromDefaults, "guard: neither is a last good copy with wrong-typed options");

	// wrong-typed options are reset, the rest untouched
	fresh(L"guard-repair");
	std::string typed = "{\n    \"configVersion\": 1,\n    \"bar\": {\"workspaces\": {\"shown\": \"ten\", \"monochromeIcons\": true}},\n    \"policies\": {\"ai\": 2},\n    \"myOwnThing\": [1, 2]\n}\n";
	put(dir + L"\\config.json", typed);
	o = guard();
	check(o.action == Outcome::Action::Repaired && o.userShouldKnow() && o.details.size() == 1, "guard: one wrong-typed option is repaired and reported");
	auto fixed = jsonlite::parse(slurp(dir + L"\\config.json"));
	check(fixed.ok && !fixed.value.find("bar")->find("workspaces")->find("shown") && fixed.value.find("bar")->find("workspaces")->find("monochromeIcons")->boolean, "guard: only that option is gone, its neighbour stays");
	check(fixed.value.find("policies")->find("ai")->number == "2" && fixed.value.find("myOwnThing") != nullptr, "guard: other options, known or not, are as they were");
	auto backups = names(dir, L"config.before-repair-*.json");
	check(backups.size() == 1 && slurp(dir + L"\\" + backups[0]) == typed, "guard: the original is kept as a backup before the repair");
	check(validate(fixed.value).empty(), "guard: the repaired file validates");

	// out-of-range values are left alone
	fresh(L"guard-range");
	std::string range = "{\"configVersion\": 1, \"bar\": {\"workspaces\": {\"shown\": 99}}}";
	put(dir + L"\\config.json", range);
	check(guard().action == Outcome::Action::Nothing && slurp(dir + L"\\config.json") == range, "guard: an out-of-range number is not changed (it may be deliberate)");

	// a newer format
	fresh(L"guard-newer");
	std::string newer = "{\"configVersion\": 99, \"bar\": \"???\"}";
	put(dir + L"\\config.json", newer);
	o = guard();
	check(o.action == Outcome::Action::NewerVersion && slurp(dir + L"\\config.json") == newer && names(dir, L"config.before-repair-*").empty(), "guard: a file from a newer ii is left exactly as it is");

	// failing to write never leaves a partial config
	fresh(L"guard-diskfull");
	put(dir + L"\\config.json", typed);
	SetEnvironmentVariableW(L"II_CONFIG_TEST_FAULT", L"disk-full");
	o = guard();
	check(o.action == Outcome::Action::Unreadable && slurp(dir + L"\\config.json") == typed, "guard: when the disk fills up, the active file stays as it was");
	check(names(dir, L"*.tmp-*").empty() && names(dir, L"config.before-repair-*").empty(), "guard: and no partial temporary file or half-made backup is left");

	// another writer changes the file while it is being repaired
	fresh(L"guard-race");
	put(dir + L"\\config.json", typed);
	SetEnvironmentVariableW(L"II_CONFIG_TEST_FAULT", L"race");
	o = guard();
	check(o.action == Outcome::Action::Unreadable, "guard: a change by someone else in between cancels the repair");
	check(slurp(dir + L"\\config.json") == typed + "\n", "guard: and their change is the file that remains");

	// the quarantine does not grow forever
	fresh(L"guard-prune");
	for (int i = 0; i < 13; ++i) {
		put(dir + L"\\config.json", "{ broken " + std::to_string(i));
		guard();
		Sleep(5);
	}
	check(names(dir, L"config.json.invalid-*").size() <= 10, "guard: at most 10 damaged copies are kept");
}

static void testKeepGood() {
	fresh(L"keep-good");
	put(dir + L"\\config.json", GOOD);
	auto o = keepGood();
	check(o.action == Outcome::Action::Saved && slurp(dir + L"\\config.last-good.json") == GOOD, "keep-good: a valid file is remembered");
	check(keepGood().action == Outcome::Action::Nothing, "keep-good: the same file again writes nothing");
	put(dir + L"\\config.json", "{ broken");
	o = keepGood();
	check(o.action == Outcome::Action::NotSaved && slurp(dir + L"\\config.last-good.json") == GOOD, "keep-good: a damaged file never replaces the last good one");
	put(dir + L"\\config.json", "{\"bar\": {\"workspaces\": {\"shown\": \"x\"}}}");
	check(keepGood().action == Outcome::Action::NotSaved && slurp(dir + L"\\config.last-good.json") == GOOD, "keep-good: nor does one with wrong-typed options");
	put(dir + L"\\config.json", "{\"configVersion\": 5}");
	check(keepGood().action == Outcome::Action::NotSaved && slurp(dir + L"\\config.last-good.json") == GOOD, "keep-good: nor one from a newer ii");
	put(dir + L"\\config.json", "{\"configVersion\": 1, \"bar\": {\"workspaces\": {\"shown\": 11}}}");
	SetEnvironmentVariableW(L"II_CONFIG_TEST_FAULT", L"disk-full");
	check(keepGood().action == Outcome::Action::NotSaved && slurp(dir + L"\\config.last-good.json") == GOOD, "keep-good: a failed write leaves the previous last good copy intact");
	SetEnvironmentVariableW(L"II_CONFIG_TEST_FAULT", nullptr);
	check(keepGood().action == Outcome::Action::Saved, "keep-good: and it works again once the disk allows");
	// it does not run per change: one call = at most one write, and nothing when unchanged
	auto before = slurp(dir + L"\\config.last-good.json");
	keepGood();
	keepGood();
	check(slurp(dir + L"\\config.last-good.json") == before, "keep-good: repeated calls with an unchanged file change nothing");
}

static std::string cli(const std::vector<std::wstring>& args, int* code = nullptr) {
	std::string out;
	auto c = run(args, out);
	if (code) *code = c;
	return out;
}

static void testExport() {
	fresh(L"export");
	put(dir + L"\\config.json", R"({
        "configVersion": 1,
        "appearance": {"transparency": {"enable": true}},
        "bar": {"workspaces": {"shown": 9}, "screenList": ["\\\\.\\DISPLAY2"]},
        "sidebar": {"booru": {"gelbooru": {"apiKey": "SENTINEL-API-KEY", "userId": "SENTINEL-USER"}}},
        "ai": {"extraModels": [{"name": "m", "model": "x", "apiKey": "SENTINEL-MODEL-KEY", "key_id": "openrouter"}]},
        "background": {"widgets": {"clock": {"cookie": {"sides": 14}}}},
        "mySecretPlace": {"password": "SENTINEL-PASSWORD"},
        "unknownTop": 5
    })");
	int code = -1;
	auto out = cli({L"export", dir + L"\\pack.json"}, &code);
	auto pack = slurp(dir + L"\\pack.json");
	check(code == 0 && pack != "<missing>", "export: writes a pack");
	check(!has(pack, "SENTINEL"), "export: no credential-like value is in the pack");
	check(has(out, "gelbooru.apiKey") && has(out, "gelbooru.userId") && has(out, "mySecretPlace"), "export: it says what it left out");
	check(has(pack, "\"shown\": 9") && has(pack, "\"transparency\"") && has(pack, "\"sides\": 14"), "export: portable options stay (including the clock's own 'cookie' style)");
	check(has(pack, "\"key_id\": \"openrouter\"") && !has(pack, "SENTINEL-MODEL-KEY"), "export: inside a custom model only the credential goes");
	check(!has(pack, "unknownTop") && !has(pack, "mySecretPlace"), "export: unknown sections are not exported");
	out = cli({L"export", dir + L"\\pack.json"}, &code);
	check(code == 1, "export: an existing output is not overwritten without --force");
	out = cli({L"export", dir + L"\\pack.json", L"--force"}, &code);
	check(code == 0, "export: --force replaces it");
}

static void testImport() {
	fresh(L"import");
	std::string mine = R"({
        "configVersion": 1,
        "bar": {"workspaces": {"shown": 5, "monochromeIcons": false}},
        "policies": {"ai": 0}
    })";
	put(dir + L"\\config.json", mine);
	SetEnvironmentVariableW(L"II_CONFIG_TEST_MONITORS", L"\\\\.\\DISPLAY1;\\\\.\\DISPLAY3");
	std::wstring existing = dir + L"\\wall.png";
	put(existing, "x");
	auto escaped = [](std::wstring p) { std::string s; for (auto c: p) { if (c == L'\\') s += "\\\\"; else s += static_cast<char>(c); } return s; };
	std::string pack = R"({"ii-config-pack": 1, "configVersion": 1, "options": {
        "bar": {"workspaces": {"shown": 8, "monochromeIcons": true}, "screenList": ["\\\\.\\DISPLAY2", "\\\\.\\DISPLAY1"], "futureThing": 1},
        "policies": {"ai": 2, "weeb": 1},
        "appearance": {"transparency": {"enable": true}},
        "sidebar": {"booru": {"gelbooru": {"apiKey": "SENTINEL-IN-PACK"}}},
        "background": {"wallpaperPath": ")" + escaped(existing) + R"(", "thumbnailPath": "C:\\definitely\\not\\here.png"},
        "notifications": {"monitor": {"name": "\\\\.\\DISPLAY9"}},
        "overview": {"rows": 400},
        "battery": {"low": "high"},
        "../../escape": {"x": 1},
        "ai": {"extraModels": [{"name": "m", "apiKey": "SENTINEL-IN-LIST"}]}
    }})";
	put(dir + L"\\pack.json", pack);

	// preview changes nothing, creates nothing
	int code = -1;
	auto before = names(dir);
	auto out = cli({L"import", dir + L"\\pack.json"}, &code);
	check(code == 0 && slurp(dir + L"\\config.json") == mine && names(dir) == before, "import: the preview changes nothing and leaves no file behind");
	check(has(out, "preview only"), "import: and says it is only a preview");
	check(has(out, "skip bar.futureThing") && has(out, "skip ../../escape") , "import: unknown options (and odd names) are skipped, not written anywhere");
	check(has(out, "skip sidebar.booru.gelbooru.apiKey") && !has(out, "SENTINEL"), "import: a credential in the pack is skipped and never echoed");
	check(has(out, "skip background.thumbnailPath") && has(out, "does not exist on this PC"), "import: a path that does not exist here is skipped");
	check(has(out, "set background.wallpaperPath"), "import: a path that exists is accepted");
	check(has(out, "skip notifications.monitor.name") && has(out, "--map-monitor"), "import: a monitor that is not here is skipped, with the way to map it");
	check(has(out, "skip overview.rows") && has(out, "out of range"), "import: a value outside the settings' range is skipped");
	check(has(out, "skip battery.low") && has(out, "wrong type"), "import: a value of the wrong type is skipped");
	check(has(out, "keep bar.workspaces.shown") && has(out, "keep policies.ai"), "import: by default your own values win over the pack's");
	check(has(out, "set appearance.transparency.enable"), "import: and options you never set are filled in");
	check(has(out, "set bar.screenList"), "import: the monitor list keeps only the monitors that exist here");

	// apply, prefer mine
	out = cli({L"import", dir + L"\\pack.json", L"--apply"}, &code);
	auto merged = jsonlite::parse(slurp(dir + L"\\config.json"));
	check(code == 0 && merged.ok, "import: --apply writes a valid config");
	check(merged.value.find("bar")->find("workspaces")->find("shown")->number == "5" && merged.value.find("policies")->find("ai")->number == "0", "import: your values stayed");
	check(merged.value.find("appearance")->find("transparency")->find("enable")->boolean, "import: the new option arrived");
	auto list = merged.value.find("bar")->find("screenList");
	check(list && list->items.size() == 1 && list->items[0].text == "\\\\.\\DISPLAY1", "import: DISPLAY2 was dropped, DISPLAY1 kept");
	check(!has(slurp(dir + L"\\config.json"), "SENTINEL") && !has(slurp(dir + L"\\config.json"), "escape"), "import: nothing from a credential or an unknown name reached the file");
	auto backups = names(dir, L"config.before-import-*.json");
	check(backups.size() == 1 && slurp(dir + L"\\" + backups[0]) == mine, "import: the previous file was kept as a backup first");
	check(validate(merged.value).empty(), "import: the result validates");

	// prefer pack, with a monitor map
	fresh(L"import-pack");
	put(dir + L"\\config.json", mine);
	put(dir + L"\\pack.json", pack);
	out = cli({L"import", dir + L"\\pack.json", L"--apply", L"--prefer", L"pack", L"--map-monitor", L"\\\\.\\DISPLAY9=\\\\.\\DISPLAY3", L"--map-monitor", L"\\\\.\\DISPLAY2=\\\\.\\DISPLAY1"}, &code);
	merged = jsonlite::parse(slurp(dir + L"\\config.json"));
	check(code == 0 && merged.value.find("bar")->find("workspaces")->find("shown")->number == "8" && merged.value.find("policies")->find("ai")->number == "2", "import: --prefer pack takes the pack's values");
	check(merged.value.find("notifications")->find("monitor")->find("name")->text == "\\\\.\\DISPLAY3", "import: --map-monitor maps a name to one that exists here");

	// disk full during apply: nothing changes
	fresh(L"import-diskfull");
	put(dir + L"\\config.json", mine);
	put(dir + L"\\pack.json", pack);
	SetEnvironmentVariableW(L"II_CONFIG_TEST_FAULT", L"disk-full");
	out = cli({L"import", dir + L"\\pack.json", L"--apply"}, &code);
	check(code == 3 && slurp(dir + L"\\config.json") == mine && names(dir, L"config.before-import-*").empty() && names(dir, L"*.tmp-*").empty(), "import: a full disk leaves the config, and the folder, as they were");

	// someone else writes meanwhile
	fresh(L"import-race");
	put(dir + L"\\config.json", mine);
	put(dir + L"\\pack.json", pack);
	SetEnvironmentVariableW(L"II_CONFIG_TEST_FAULT", L"race");
	out = cli({L"import", dir + L"\\pack.json", L"--apply"}, &code);
	check(code == 3 && slurp(dir + L"\\config.json") == mine + "\n" && has(out, "nothing changed"), "import: if the file changed meanwhile nothing is replaced, and their change stays");
	SetEnvironmentVariableW(L"II_CONFIG_TEST_FAULT", nullptr);

	// refusals
	fresh(L"import-refuse");
	put(dir + L"\\config.json", mine);
	put(dir + L"\\pack.json", "{\"ii-config-pack\": 1, \"configVersion\": 7, \"options\": {}}");
	cli({L"import", dir + L"\\pack.json", L"--apply"}, &code);
	check(code == 1, "import: a pack from a newer ii is refused");
	put(dir + L"\\pack.json", "{\"hello\": 1}");
	cli({L"import", dir + L"\\pack.json"}, &code);
	check(code == 2, "import: something that is not a pack is refused");
	put(dir + L"\\pack.json", std::string(1100000, ' ') + "{}");
	cli({L"import", dir + L"\\pack.json"}, &code);
	check(code == 2, "import: a pack over 1 MiB is refused");
	std::string deep = "{\"ii-config-pack\": 1, \"options\": " + std::string(40, '[') + std::string(40, ']') + "}";
	put(dir + L"\\pack.json", deep);
	cli({L"import", dir + L"\\pack.json"}, &code);
	check(code == 2, "import: a pack nested deeper than 32 levels is refused");
	put(dir + L"\\config.json", "{ broken");
	put(dir + L"\\pack.json", "{\"ii-config-pack\": 1, \"options\": {}}");
	out = cli({L"import", dir + L"\\pack.json", L"--apply"}, &code);
	check(code == 2 && slurp(dir + L"\\config.json") == "{ broken", "import: onto a damaged config it stops and writes nothing");
	SetEnvironmentVariableW(L"II_CONFIG_TEST_MONITORS", nullptr);

	// a round trip: export then import into an empty config
	fresh(L"roundtrip");
	put(dir + L"\\config.json", GOOD);
	cli({L"export", dir + L"\\pack.json"}, &code);
	std::string backup = slurp(dir + L"\\config.json");
	DeleteFileW((dir + L"\\config.json").c_str());
	SetEnvironmentVariableW(L"II_CONFIG_TEST_MONITORS", L"\\\\.\\DISPLAY1");
	out = cli({L"import", dir + L"\\pack.json", L"--apply"}, &code);
	auto again = jsonlite::parse(slurp(dir + L"\\config.json"));
	check(code == 0 && again.ok && again.value.find("bar")->find("workspaces")->find("shown")->number == "10", "import: export then import into an empty config brings the options back");
	SetEnvironmentVariableW(L"II_CONFIG_TEST_MONITORS", nullptr);
	(void)backup;
}

static void testCheckCli() {
	fresh(L"check");
	int code = -1;
	put(dir + L"\\config.json", GOOD);
	auto out = cli({L"check"}, &code);
	check(code == 0 && has(out, "\nok\n"), "check: a good file passes");
	put(dir + L"\\config.json", "{\"bar\": {\"workspaces\": {\"shown\": \"x\"}}}");
	out = cli({L"check"}, &code);
	check(code == 1 && has(out, "error bar.workspaces.shown type"), "check: a wrong type fails with the option's name");
	put(dir + L"\\config.json", "{\"bar\": {\"workspaces\": {\"shown\": 99}}}");
	out = cli({L"check"}, &code);
	check(code == 0 && has(out, "warning bar.workspaces.shown range"), "check: a range warning does not fail it");
	put(dir + L"\\config.json", "{ x");
	out = cli({L"check"}, &code);
	check(code == 2 && has(out, "invalid"), "check: not JSON is reported as invalid (exit 2)");
	check(cli({L"frobnicate"}, &code).find("unknown") != std::string::npos && code == 64, "cli: an unknown command is a usage error");
}

int main() {
	wchar_t temp[MAX_PATH];
	GetTempPathW(MAX_PATH, temp);
	root = std::wstring(temp) + L"ii-config-test-" + std::to_wstring(GetCurrentProcessId());
	CreateDirectoryW(root.c_str(), nullptr);

	testJson();
	testValidate();
	testGuard();
	testKeepGood();
	testExport();
	testImport();
	testCheckCli();

	// remove the throwaway folders
	WIN32_FIND_DATAW data;
	HANDLE f = FindFirstFileW((root + L"\\*").c_str(), &data);
	std::vector<std::wstring> sub;
	if (f != INVALID_HANDLE_VALUE) {
		do {
			if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && wcscmp(data.cFileName, L".") && wcscmp(data.cFileName, L"..")) sub.emplace_back(data.cFileName);
		} while (FindNextFileW(f, &data));
		FindClose(f);
	}
	for (const auto& s: sub) {
		for (const auto& n: names(root + L"\\" + s)) DeleteFileW((root + L"\\" + s + L"\\" + n).c_str());
		RemoveDirectoryW((root + L"\\" + s).c_str());
	}
	RemoveDirectoryW(root.c_str());

	std::printf("%d checks, %d failed\n", total, failed);
	return failed == 0 ? 0 : 1;
}
