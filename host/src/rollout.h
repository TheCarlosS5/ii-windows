#pragma once

// Versioned runtime selection (R07). The install folder holds
//   ii-launcher.exe        the one stable entry point (shortcuts, the logon task, the Run key)
//   current.txt            which version is active, which one to fall back to, and its state
//   versions\<id>\         one complete package per version, never edited after it is activated
// current.txt is replaced atomically (temp file + MoveFileEx), so it is always either the old or
// the new complete file. A version that has not yet proved itself is "pending": the launcher
// starts it and waits for the host to confirm it ("verified"); if it does not, the launcher goes
// back to the previous version and records why.
//
// The format is plain key=value lines (cmd.exe and PowerShell read it too).

#include <string>

namespace ii::rollout {

struct Current {
	bool present = false;
	std::wstring active;   // version id, or "legacy" for the flat pre-0.1.4 layout in the install folder
	std::wstring previous; // version id, "legacy", or "none"
	std::wstring state;    // "pending" | "verified" | "rolled-back"
	int attempts = 0;      // launches of a pending version
};

// A version id is a plain name: no separators, no "..", nothing that could leave versions\.
bool validId(const std::wstring& id);

bool read(const std::wstring& root, Current& out);
bool write(const std::wstring& root, const Current& value); // atomic

// <root>\versions\<id>  (or <root> itself for "legacy"). Empty if the id is not valid.
std::wstring versionDir(const std::wstring& root, const std::wstring& id);

// If exeDir is <root>\versions\<id>, fills root and id and returns true.
bool locate(const std::wstring& exeDir, std::wstring& root, std::wstring& id);

// Called by ii-host when its shell is up: if this host belongs to the pending version, mark it
// verified. Returns true if it changed the state.
bool markVerified(const std::wstring& exeDir);

} // namespace ii::rollout
