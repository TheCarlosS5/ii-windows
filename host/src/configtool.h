// D01: ii's config.json as something that can be checked, recovered and moved between PCs.
//
//   ii-shim config where                      the files involved
//   ii-shim config check [--file F]           types, enumerations and ranges against the schema
//   ii-shim config guard                      before the shell starts: a damaged file is kept aside and
//                                             the last good one put back; wrong-typed options are reset
//   ii-shim config keep-good                  when the shell runs fine: remember this file as last good
//   ii-shim config export <out> [--force]     a portable pack (no secrets, no machine-only state)
//   ii-shim config import <pack> [--apply] [--prefer pack|mine] [--map-monitor old=new]
//                                             preview by default; --apply writes, after a backup
//
// The schema (host/src/config_schema.inc, shared/config-schema.json) is generated from the staged
// Config.qml, so it includes ii-windows' own options. Unknown keys are never an error. See
// docs/seguimiento/D01.md for what is and is not guaranteed.
#pragma once

#include <string>
#include <vector>

#include "jsonlite.h"

namespace configtool {

// The config format this build writes and understands (`configVersion` in config.json).
constexpr int SUPPORTED_VERSION = 1;

enum class Severity { Error, Warning };

struct Problem {
	std::string path;
	Severity severity = Severity::Error;
	std::string kind;   // type | enum | range
	std::string detail;
};

// Errors: the option has the wrong JSON kind (it would break the loader's expectations).
// Warnings: an integer outside its documented values, or a number outside what the settings page allows.
std::vector<Problem> validate(const jsonlite::Value& root);

struct Paths {
	std::wstring dir;
	std::wstring file;
	std::wstring lastGood;
};
// %LOCALAPPDATA%\quickshell\illogical-impulse, or II_CONFIG_DIR (tests, other profiles).
Paths paths();

struct Outcome {
	enum class Action {
		Nothing,           // fine as it is
		Missing,           // no file yet (ii writes the defaults)
		Unreadable,        // could not be read (locked, permissions): untouched
		RestoredLastGood,  // damaged: kept aside, last good put back
		StartedFromDefaults, // damaged and no last good: kept aside, ii starts from defaults
		Repaired,          // wrong-typed options removed (backup kept), the rest untouched
		NewerVersion,      // written by a newer ii: untouched
		Saved,             // keep-good: stored
		NotSaved,          // keep-good: not stored (reason in message)
	};
	Action action = Action::Nothing;
	std::string message;               // one line, fit for a log or a dialog
	std::vector<std::string> details;  // one per affected option / file
	[[nodiscard]] bool userShouldKnow() const {
		return action == Action::RestoredLastGood || action == Action::StartedFromDefaults || action == Action::Repaired || action == Action::NewerVersion;
	}
};

Outcome guard();
Outcome keepGood();

// The pack written by export; `excluded` receives the paths left out and why.
jsonlite::Value makePack(const jsonlite::Value& config, std::vector<std::string>* excluded);

// Runs a command line; output goes to `out`. Returns the exit code
// (0 ok; 1 problems found / refused; 2 unreadable or not JSON; 3 changed meanwhile or could not write; 64 usage).
int run(const std::vector<std::wstring>& args, std::string& out);
int command(const std::vector<std::wstring>& args); // run() + print

} // namespace configtool
