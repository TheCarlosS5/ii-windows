// cliphist for Windows (ii-shim): ii's clipboard history (Win+V, the launcher's ";" prefix,
// superpaste) on top of Windows' own clipboard history (Settings > System > Clipboard), the same
// one Windows' Win+V panel shows. Nothing is stored by ii.
//
//   cliphist list                 "<id>\t<preview>" newest first; images as cliphist prints them
//                                 ("[[ binary data 12 KiB png 800x600 ]]")
//   cliphist copy <id|line>       makes that entry the current clipboard (text or image)
//   cliphist decode-to <id|line> <file>   writes the entry's image as PNG (kept if it exists)
//   cliphist delete               entry line on stdin (as `echo line | cliphist delete`)
//   cliphist delete-id <id|line>
//   cliphist paste <id|line>      copy, then Ctrl+V into the app in front
//   cliphist superpaste <delay ms> <id> ...   pastes several entries in order
//   cliphist wipe                 clears Windows' clipboard history
//   cliphist enabled              exit 0 if Windows' clipboard history is on
//
// Ids are short hashes of Windows' item ids (cliphist's are numbers; ii parses them as such).

#include <cstdio>
#include <string>
#include <vector>

#include <windows.h>
#include <shlobj.h>

// clang-format off
#include <winrt/base.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
// clang-format on

using namespace winrt;
using namespace winrt::Windows::ApplicationModel::DataTransfer;
using namespace winrt::Windows::Graphics::Imaging;
using namespace winrt::Windows::Storage;
using namespace winrt::Windows::Storage::Streams;

namespace {

void writeUtf8(const std::wstring& text) {
	auto n = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
	std::string out(static_cast<size_t>(n), '\0');
	WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n, nullptr, nullptr);
	fwrite(out.data(), 1, out.size(), stdout);
}

// A number for Windows' item id (a GUID string): ii expects numeric cliphist ids.
unsigned int idOf(const ClipboardHistoryItem& item) {
	unsigned int hash = 2166136261u;
	for (auto ch: item.Id()) {
		hash ^= static_cast<unsigned int>(ch);
		hash *= 16777619u;
	}
	return hash % 1000000000u;
}

// "<id>\t..." or a bare id.
unsigned int idFromArg(const std::wstring& arg) {
	return static_cast<unsigned int>(wcstoul(arg.c_str(), nullptr, 10));
}

std::vector<ClipboardHistoryItem> history() {
	std::vector<ClipboardHistoryItem> items;
	if (!Clipboard::IsHistoryEnabled()) return items;
	auto result = Clipboard::GetHistoryItemsAsync().get();
	if (result.Status() != ClipboardHistoryItemsResultStatus::Success) return items;
	for (const auto& item: result.Items()) items.push_back(item);
	return items;
}

ClipboardHistoryItem find(unsigned int id) {
	for (const auto& item: history()) {
		if (idOf(item) == id) return item;
	}
	return nullptr;
}

std::wstring preview(const std::wstring& text) {
	std::wstring line;
	for (auto ch: text) {
		if (ch == L'\r') continue;
		line += (ch == L'\n' || ch == L'\t') ? L' ' : ch;
		if (line.size() >= 300) break;
	}
	return line;
}

std::wstring imageLine(const DataPackageView& content) {
	auto stream = content.GetBitmapAsync().get().OpenReadAsync().get();
	auto size = stream.Size();
	auto decoder = BitmapDecoder::CreateAsync(stream).get();
	auto kib = static_cast<unsigned long long>((size + 1023) / 1024);
	return L"[[ binary data " + std::to_wstring(kib) + L" KiB png " + std::to_wstring(decoder.PixelWidth()) + L"x"
	     + std::to_wstring(decoder.PixelHeight()) + L" ]]";
}

int list() {
	for (const auto& item: history()) {
		try {
			auto content = item.Content();
			std::wstring line;
			if (content.Contains(StandardDataFormats::Text())) line = preview(std::wstring(content.GetTextAsync().get()));
			else if (content.Contains(StandardDataFormats::Bitmap())) line = imageLine(content);
			else if (content.Contains(StandardDataFormats::StorageItems())) {
				for (const auto& file: content.GetStorageItemsAsync().get()) line += (line.empty() ? L"" : L", ") + std::wstring(file.Name());
			}
			if (line.empty()) continue;
			writeUtf8(std::to_wstring(idOf(item)) + L"\t" + line + L"\n");
		} catch (...) {
			// An item Windows can no longer render: skip it.
		}
	}
	fflush(stdout);
	return 0;
}

int decodeTo(unsigned int id, std::wstring path) {
	// ii writes "/C:/Users/..." (its Linux-style paths): make it a Windows one.
	if (path.size() > 2 && path[0] == L'/' && path[2] == L':') path.erase(0, 1);
	for (auto& ch: path) if (ch == L'/') ch = L'\\';
	if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) return 0;
	SHCreateDirectoryExW(nullptr, path.substr(0, path.find_last_of(L'\\')).c_str(), nullptr);
	auto item = find(id);
	if (!item || !item.Content().Contains(StandardDataFormats::Bitmap())) return 1;
	auto input = item.Content().GetBitmapAsync().get().OpenReadAsync().get();
	auto decoder = BitmapDecoder::CreateAsync(input).get();
	auto bitmap = decoder.GetSoftwareBitmapAsync(BitmapPixelFormat::Bgra8, BitmapAlphaMode::Premultiplied).get();
	auto slash = path.find_last_of(L"\\/");
	auto folder = StorageFolder::GetFolderFromPathAsync(path.substr(0, slash)).get();
	auto file = folder.CreateFileAsync(path.substr(slash + 1), CreationCollisionOption::ReplaceExisting).get();
	auto output = file.OpenAsync(FileAccessMode::ReadWrite).get();
	auto encoder = BitmapEncoder::CreateAsync(BitmapEncoder::PngEncoderId(), output).get();
	encoder.SetSoftwareBitmap(bitmap);
	encoder.FlushAsync().get();
	return 0;
}

void pressCtrlV() {
	INPUT in[4] {};
	WORD keys[2] = {VK_CONTROL, 'V'};
	for (int i = 0; i < 4; ++i) {
		in[i].type = INPUT_KEYBOARD;
		in[i].ki.wVk = keys[i < 2 ? i : 3 - i];
		in[i].ki.dwFlags = i < 2 ? 0 : KEYEVENTF_KEYUP;
	}
	SendInput(4, in, sizeof(INPUT));
}

bool copyEntry(unsigned int id) {
	auto item = find(id);
	return item && Clipboard::SetHistoryItemAsContent(item) == SetHistoryItemAsContentStatus::Success;
}

std::wstring readStdinLine() {
	std::string data;
	char buffer[4096];
	size_t n = 0;
	while ((n = fread(buffer, 1, sizeof(buffer), stdin)) > 0) data.append(buffer, n);
	auto w = MultiByteToWideChar(CP_UTF8, 0, data.data(), static_cast<int>(data.size()), nullptr, 0);
	std::wstring out(static_cast<size_t>(w), L'\0');
	MultiByteToWideChar(CP_UTF8, 0, data.data(), static_cast<int>(data.size()), out.data(), w);
	return out;
}

} // namespace

int cliphist(const std::vector<std::wstring>& args) {
	if (args.empty()) return 2;
	init_apartment(apartment_type::multi_threaded);
	try {
		const auto& command = args[0];
		if (command == L"enabled") return Clipboard::IsHistoryEnabled() ? 0 : 1;
		if (command == L"list") return list();
		if (command == L"wipe") return Clipboard::ClearHistory() ? 0 : 1;
		if (command == L"copy" && args.size() > 1) return copyEntry(idFromArg(args[1])) ? 0 : 1;
		if (command == L"paste" && args.size() > 1) {
			if (!copyEntry(idFromArg(args[1]))) return 1;
			Sleep(80); // let the clipboard settle, and ii's panel close
			pressCtrlV();
			return 0;
		}
		if (command == L"superpaste" && args.size() > 2) {
			auto delay = static_cast<DWORD>(_wtoi(args[1].c_str()));
			for (size_t i = 2; i < args.size(); ++i) {
				if (!copyEntry(idFromArg(args[i]))) continue;
				Sleep(delay + 30);
				pressCtrlV();
				Sleep(delay + 30);
			}
			return 0;
		}
		if (command == L"decode-to" && args.size() > 2) return decodeTo(idFromArg(args[1]), args[2]);
		if (command == L"delete" || command == L"delete-id") {
			auto line = command == L"delete" ? readStdinLine() : (args.size() > 1 ? args[1] : L"");
			auto item = find(idFromArg(line));
			return item && Clipboard::DeleteItemFromHistory(item) ? 0 : 1;
		}
	} catch (const hresult_error& e) {
		fwprintf(stderr, L"cliphist: %ls\n", e.message().c_str());
		return 1;
	}
	return 2;
}
