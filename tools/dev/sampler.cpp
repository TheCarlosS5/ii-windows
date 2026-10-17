// A small sampling profiler: samples stacks every few ms, then prints the functions where the time went (inclusive
// and self), symbolized from PDBs / exports.
//   sampler.exe <seconds> <intervalMs> <outFile> <program> [args...]   start a program, sample its main thread
//   sampler.exe <seconds> <intervalMs> <outFile> --pid <pid>           every thread of a running process; samples
//                                                                      whose top frame is a wait are left out
// Build (MSVC, from a vsenv shell):  cl /nologo /O2 /EHsc /std:c++20 sampler.cpp dbghelp.lib winmm.lib
// Nothing is changed in the target; a thread is suspended for the microseconds its stack read takes.
#include <windows.h>
#include <dbghelp.h>
#include <tlhelp32.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

std::vector<DWORD64> walk(HANDLE process, HANDLE thread) {
	std::vector<DWORD64> frames;
	if (SuspendThread(thread) == DWORD(-1)) return frames;
	CONTEXT ctx {};
	ctx.ContextFlags = CONTEXT_FULL;
	if (GetThreadContext(thread, &ctx)) {
		STACKFRAME64 frame {};
		frame.AddrPC.Offset = ctx.Rip;
		frame.AddrPC.Mode = AddrModeFlat;
		frame.AddrFrame.Offset = ctx.Rbp;
		frame.AddrFrame.Mode = AddrModeFlat;
		frame.AddrStack.Offset = ctx.Rsp;
		frame.AddrStack.Mode = AddrModeFlat;
		for (int i = 0; i < 96; ++i) {
			if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, thread, &frame, &ctx, nullptr, SymFunctionTableAccess64,
			                 SymGetModuleBase64, nullptr))
				break;
			if (frame.AddrPC.Offset == 0) break;
			frames.push_back(frame.AddrPC.Offset);
		}
	}
	ResumeThread(thread);
	return frames;
}

bool isWait(const std::string& top) {
	for (auto* w: {"WaitFor", "MsgWaitForMultipleObjects", "RemoveIoCompletion", "DelayExecution", "NtUserGetMessage",
	               "AlpcSendWaitReceivePort", "WaitForAlertByThreadId", "ZwWaitForWorkViaWorkerFactory",
	               "NtWaitForWorkViaWorkerFactory", "SignalAndWait"})
		if (top.find(w) != std::string::npos) return true;
	return false;
}

} // namespace

int wmain(int argc, wchar_t** argv) {
	if (argc < 5) {
		std::printf("usage: sampler <seconds> <intervalMs> <outFile> <program> [args...] | --pid <pid>\n");
		return 2;
	}
	const double seconds = _wtof(argv[1]);
	const int interval = _wtoi(argv[2]);
	const wchar_t* outPath = argv[3];
	const bool attach = wcscmp(argv[4], L"--pid") == 0 && argc > 5;

	HANDLE process = nullptr;
	DWORD pid = 0;
	std::vector<HANDLE> threads;
	if (attach) {
		pid = static_cast<DWORD>(_wtoi(argv[5]));
		process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
		if (!process) {
			std::printf("cannot open process %lu (%lu)\n", pid, GetLastError());
			return 1;
		}
	} else {
		std::wstring cmd = L"\"" + std::wstring(argv[4]) + L"\"";
		for (int i = 5; i < argc; ++i) cmd += L" \"" + std::wstring(argv[i]) + L"\"";
		STARTUPINFOW si {};
		si.cb = sizeof(si);
		PROCESS_INFORMATION pi {};
		if (!CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
			std::printf("CreateProcess failed (%lu)\n", GetLastError());
			return 1;
		}
		process = pi.hProcess;
		pid = pi.dwProcessId;
		threads.push_back(pi.hThread);
	}
	timeBeginPeriod(1);
	SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
	SymInitialize(process, nullptr, attach);

	std::vector<std::vector<DWORD64>> samples;
	std::vector<double> times;
	std::vector<DWORD> sampleThread;
	size_t total = 0;
	LARGE_INTEGER freq, start, now;
	QueryPerformanceFrequency(&freq);
	QueryPerformanceCounter(&start);
	std::unordered_map<DWORD, HANDLE> open;
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
		std::string modName = SymGetModuleInfo64(process, addr, &mod) ? mod.ModuleName : "?";
		DWORD64 disp = 0;
		std::string s = modName + "!" + (SymFromAddr(process, addr, &disp, sym) ? std::string(sym->Name) : "?");
		return names.emplace(addr, s).first->second;
	};
	for (;;) {
		QueryPerformanceCounter(&now);
		double t = double(now.QuadPart - start.QuadPart) / freq.QuadPart;
		if (t > seconds || WaitForSingleObject(process, 0) == WAIT_OBJECT_0) break;
		if (attach) {
			// every thread of the process, as it is now
			HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
			THREADENTRY32 te {};
			te.dwSize = sizeof(te);
			for (BOOL ok = Thread32First(snap, &te); ok; ok = Thread32Next(snap, &te)) {
				if (te.th32OwnerProcessID != pid) continue;
				auto& h = open[te.th32ThreadID];
				if (!h) h = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, te.th32ThreadID);
				if (!h) continue;
				auto frames = walk(process, h);
				++total;
				if (frames.empty() || isWait(name(frames[0]))) continue;
				samples.push_back(std::move(frames));
				times.push_back(t);
				sampleThread.push_back(te.th32ThreadID);
			}
			CloseHandle(snap);
			SymRefreshModuleList(process);
		} else {
			SymRefreshModuleList(process);
			samples.push_back(walk(process, threads[0]));
			times.push_back(t);
			sampleThread.push_back(0);
			++total;
		}
		Sleep(interval);
	}
	SymRefreshModuleList(process);
	std::map<std::string, int> incl, self;
	std::map<DWORD, int> perThread;
	FILE* out = _wfopen(outPath, L"w");
	for (size_t i = 0; i < samples.size(); ++i) {
		std::vector<std::string> seen;
		perThread[sampleThread[i]]++;
		for (size_t j = 0; j < samples[i].size(); ++j) {
			const auto& n = name(samples[i][j]);
			if (j == 0) self[n]++;
			if (std::find(seen.begin(), seen.end(), n) == seen.end()) {
				seen.push_back(n);
				incl[n]++;
			}
		}
		std::fprintf(out, "%.3f;%lu", times[i], sampleThread[i]);
		for (size_t j = 0; j < samples[i].size() && j < 40; ++j) std::fprintf(out, "|%s", name(samples[i][j]).c_str());
		std::fprintf(out, "\n");
	}
	std::fclose(out);
	if (!attach) TerminateProcess(process, 0);
	auto print = [&](const char* title, std::map<std::string, int>& m, size_t n) {
		std::vector<std::pair<int, std::string>> v;
		for (auto& [k, c]: m) v.emplace_back(c, k);
		std::sort(v.rbegin(), v.rend());
		std::printf("%s (%zu busy samples of %zu)\n", title, samples.size(), total);
		for (size_t i = 0; i < v.size() && i < n; ++i) std::printf("  %5d  %s\n", v[i].first, v[i].second.c_str());
	};
	if (attach) {
		std::printf("busy samples per thread:");
		for (auto& [tid, c]: perThread) std::printf(" %lu:%d", tid, c);
		std::printf("\n");
	}
	print("self", self, 30);
	print("inclusive", incl, 70);
	return 0;
}
