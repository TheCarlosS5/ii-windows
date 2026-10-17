// A small sampling profiler for start-up: starts a program and samples its main thread's stack every few ms,
// then prints the functions where the time went (inclusive and self), symbolized from PDBs / exports.
//   sampler.exe <seconds> <intervalMs> <outFile> <program> [args...]
// Build (MSVC, from a vsenv shell):  cl /nologo /O2 /EHsc /std:c++20 sampler.cpp dbghelp.lib
// The program gets the environment of the caller. Nothing is changed in it; its main thread is suspended for the
// microseconds each stack read takes.
#include <windows.h>
#include <dbghelp.h>

#include <algorithm>
#include <cstdio>
#include <map>
#include <string>
#include <unordered_map>
#include <vector>

int wmain(int argc, wchar_t** argv) {
	if (argc < 5) {
		std::printf("usage: sampler <seconds> <intervalMs> <outFile> <program> [args...]\n");
		return 2;
	}
	const double seconds = _wtof(argv[1]);
	const int interval = _wtoi(argv[2]);
	const wchar_t* outPath = argv[3];
	std::wstring cmd = L"\"" + std::wstring(argv[4]) + L"\"";
	for (int i = 5; i < argc; ++i) cmd += L" \"" + std::wstring(argv[i]) + L"\"";

	STARTUPINFOW si {};
	si.cb = sizeof(si);
	PROCESS_INFORMATION pi {};
	if (!CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
		std::printf("CreateProcess failed (%lu)\n", GetLastError());
		return 1;
	}
	timeBeginPeriod(1);
	std::vector<std::vector<DWORD64>> samples;
	std::vector<double> times;
	LARGE_INTEGER freq, start, now;
	QueryPerformanceFrequency(&freq);
	QueryPerformanceCounter(&start);
	SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
	SymInitialize(pi.hProcess, nullptr, FALSE);
	for (;;) {
		QueryPerformanceCounter(&now);
		double t = double(now.QuadPart - start.QuadPart) / freq.QuadPart;
		if (t > seconds || WaitForSingleObject(pi.hProcess, 0) == WAIT_OBJECT_0) break;
		if (SuspendThread(pi.hThread) != DWORD(-1)) {
			CONTEXT ctx {};
			ctx.ContextFlags = CONTEXT_FULL;
			std::vector<DWORD64> frames;
			if (GetThreadContext(pi.hThread, &ctx)) {
				STACKFRAME64 frame {};
				frame.AddrPC.Offset = ctx.Rip;
				frame.AddrPC.Mode = AddrModeFlat;
				frame.AddrFrame.Offset = ctx.Rbp;
				frame.AddrFrame.Mode = AddrModeFlat;
				frame.AddrStack.Offset = ctx.Rsp;
				frame.AddrStack.Mode = AddrModeFlat;
				SymRefreshModuleList(pi.hProcess);
				for (int i = 0; i < 96; ++i) {
					if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, pi.hProcess, pi.hThread, &frame, &ctx, nullptr,
					                 SymFunctionTableAccess64, SymGetModuleBase64, nullptr))
						break;
					if (frame.AddrPC.Offset == 0) break;
					frames.push_back(frame.AddrPC.Offset);
				}
			}
			ResumeThread(pi.hThread);
			samples.push_back(std::move(frames));
			times.push_back(t);
		}
		Sleep(interval);
	}
	// Symbolize while the process is still there (modules loaded).
	SymRefreshModuleList(pi.hProcess);
	std::unordered_map<DWORD64, std::string> names;
	auto name = [&](DWORD64 addr) -> const std::string& {
		auto it = names.find(addr);
		if (it != names.end()) return it->second;
		char buf[sizeof(SYMBOL_INFO) + 512] {};
		auto* sym = reinterpret_cast<SYMBOL_INFO*>(buf);
		sym->SizeOfStruct = sizeof(SYMBOL_INFO);
		sym->MaxNameLen = 500;
		IMAGEHLP_MODULE64 mod {};
		mod.SizeOfStruct = sizeof(mod);
		std::string modName = SymGetModuleInfo64(pi.hProcess, addr, &mod) ? mod.ModuleName : "?";
		DWORD64 disp = 0;
		std::string s = modName + "!" + (SymFromAddr(pi.hProcess, addr, &disp, sym) ? std::string(sym->Name) : "?");
		return names.emplace(addr, s).first->second;
	};
	std::map<std::string, int> incl, self;
	FILE* out = _wfopen(outPath, L"w");
	for (size_t i = 0; i < samples.size(); ++i) {
		std::vector<std::string> seen;
		for (size_t j = 0; j < samples[i].size(); ++j) {
			const auto& n = name(samples[i][j]);
			if (j == 0) self[n]++;
			if (std::find(seen.begin(), seen.end(), n) == seen.end()) {
				seen.push_back(n);
				incl[n]++;
			}
		}
		// The raw sample: time, then the frames from the top (useful for a timeline).
		std::fprintf(out, "%.3f", times[i]);
		for (size_t j = 0; j < samples[i].size() && j < 40; ++j) std::fprintf(out, "|%s", name(samples[i][j]).c_str());
		std::fprintf(out, "\n");
	}
	std::fclose(out);
	TerminateProcess(pi.hProcess, 0);
	auto print = [&](const char* title, std::map<std::string, int>& m, size_t n) {
		std::vector<std::pair<int, std::string>> v;
		for (auto& [k, c]: m) v.emplace_back(c, k);
		std::sort(v.rbegin(), v.rend());
		std::printf("%s (of %zu samples)\n", title, samples.size());
		for (size_t i = 0; i < v.size() && i < n; ++i) std::printf("  %5d  %s\n", v[i].first, v[i].second.c_str());
	};
	print("self", self, 30);
	print("inclusive", incl, 70);
	return 0;
}
