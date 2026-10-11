// Decisions about removing a virtual desktop, kept apart from COM so they can be tested without
// Explorer (host/src/vdesk_test.cpp). Windows has no public transaction for "remove this desktop
// if it is still empty": the only honest rule is to compare what the caller saw with what is there
// right before the call, and to do nothing whenever anything differs or cannot be told.
#pragma once

#include <algorithm>
#include <cwctype>
#include <string>
#include <vector>

namespace vdeskpolicy {

enum class Verdict {
	Ok,
	InventoryChanged, // the ordered list of desktops is not the one the caller decided on
	NotInInventory,   // the target is not among them
	OnlyOne,          // the last desktop cannot be closed
	IsFirst,          // desktop 1 is never removed automatically
	IsCurrent,        // the user is on it (or came back to it)
	Occupied,         // a window is there, or could not be told (ambiguity favours not deleting)
};

inline const wchar_t* name(Verdict v) {
	switch (v) {
	case Verdict::Ok: return L"ok";
	case Verdict::InventoryChanged: return L"inventory-changed";
	case Verdict::NotInInventory: return L"not-in-inventory";
	case Verdict::OnlyOne: return L"only-one";
	case Verdict::IsFirst: return L"is-first";
	case Verdict::IsCurrent: return L"is-current";
	case Verdict::Occupied: return L"occupied";
	}
	return L"unknown";
}

// "{abcd...}" in any case, with or without braces, to one comparable spelling.
inline std::wstring normalize(std::wstring id) {
	id.erase(std::remove_if(id.begin(), id.end(), [](wchar_t c) { return c == L'{' || c == L'}' || iswspace(c); }), id.end());
	std::transform(id.begin(), id.end(), id.begin(), [](wchar_t c) { return static_cast<wchar_t>(towupper(c)); });
	return L"{" + id + L"}";
}

inline std::vector<std::wstring> splitIds(const std::wstring& list) {
	std::vector<std::wstring> out;
	size_t start = 0;
	while (start <= list.size()) {
		auto end = list.find(L',', start);
		if (end == std::wstring::npos) end = list.size();
		if (end > start) out.push_back(normalize(list.substr(start, end - start)));
		start = end + 1;
	}
	return out;
}

// `expected`: the desktops, in order, when the caller decided. `actual`/`actualCurrent`: now.
// `occupants`: windows found on the target now, -1 when that could not be established.
inline Verdict judgeRemoveEmpty(
    const std::vector<std::wstring>& expected,
    const std::vector<std::wstring>& actual,
    int actualCurrent,
    const std::wstring& target,
    int occupants
) {
	if (expected != actual) return Verdict::InventoryChanged;
	auto it = std::find(actual.begin(), actual.end(), normalize(target));
	if (it == actual.end()) return Verdict::NotInInventory;
	if (actual.size() <= 1) return Verdict::OnlyOne;
	auto index = static_cast<int>(it - actual.begin());
	if (index == 0) return Verdict::IsFirst;
	if (index == actualCurrent) return Verdict::IsCurrent;
	if (occupants != 0) return Verdict::Occupied;
	return Verdict::Ok;
}

} // namespace vdeskpolicy
