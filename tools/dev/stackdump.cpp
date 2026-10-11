// Prints the call stack of every thread of a running process (a hung shell, for instance).
//   stackdump.exe <pid> [maxFrames]
// Build (MSVC, from a vsenv-portable shell):  cl /nologo /O2 /EHsc stackdump.cpp dbghelp.lib
// Names come from the modules' symbols: exports for Qt/Windows DLLs, and for quickshell.exe whatever
// its PDB or link map offers (link it with /MAP to get a function list to look offsets up in).
// Threads are suspended one at a time while their stack is read; nothing is changed in the process.
#include <windows.h>
#include <dbghelp.h>
#include <tlhelp32.h>

#include <cstdio>
#include <cstdlib>
#include <vector>

int main(int argc, char** argv) {
	if (argc < 2) {
		std::printf("usage: stackdump <pid> [maxFrames]\n");
		return 2;
	}
	DWORD pid = static_cast<DWORD>(std::atoi(argv[1]));
	int maxFrames = argc > 2 ? std::atoi(argv[2]) : 40;
	HANDLE process = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
	if (!process) {
		std::printf("cannot open process %lu (error %lu)\n", pid, GetLastError());
		return 1;
	}
	SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);
	if (!SymInitialize(process, nullptr, TRUE)) {
		std::printf("SymInitialize failed (%lu)\n", GetLastError());
		return 1;
	}

	std::vector<DWORD> threads;
	HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
	THREADENTRY32 te {};
	te.dwSize = sizeof(te);
	for (BOOL ok = Thread32First(snap, &te); ok; ok = Thread32Next(snap, &te)) {
		if (te.th32OwnerProcessID == pid) threads.push_back(te.th32ThreadID);
	}
	CloseHandle(snap);

	for (auto tid: threads) {
		HANDLE thread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, tid);
		if (!thread) continue;
		std::printf("--- thread %lu\n", tid);
		if (SuspendThread(thread) == static_cast<DWORD>(-1)) {
			CloseHandle(thread);
			continue;
		}
		CONTEXT context {};
		context.ContextFlags = CONTEXT_FULL;
		if (GetThreadContext(thread, &context)) {
			STACKFRAME64 frame {};
			frame.AddrPC.Offset = context.Rip;
			frame.AddrPC.Mode = AddrModeFlat;
			frame.AddrFrame.Offset = context.Rbp;
			frame.AddrFrame.Mode = AddrModeFlat;
			frame.AddrStack.Offset = context.Rsp;
			frame.AddrStack.Mode = AddrModeFlat;
			for (int i = 0; i < maxFrames; ++i) {
				if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, thread, &frame, &context, nullptr, SymFunctionTableAccess64, SymGetModuleBase64, nullptr)) break;
				if (frame.AddrPC.Offset == 0) break;
				char buffer[sizeof(SYMBOL_INFO) + 256] {};
				auto* symbol = reinterpret_cast<SYMBOL_INFO*>(buffer);
				symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
				symbol->MaxNameLen = 255;
				DWORD64 displacement = 0;
				IMAGEHLP_MODULE64 module {};
				module.SizeOfStruct = sizeof(module);
				bool haveModule = SymGetModuleInfo64(process, frame.AddrPC.Offset, &module) != 0;
				if (SymFromAddr(process, frame.AddrPC.Offset, &displacement, symbol)) {
					std::printf("  %-22s %s+0x%llx\n", haveModule ? module.ModuleName : "?", symbol->Name, displacement);
				} else {
					std::printf("  %-22s +0x%llx\n", haveModule ? module.ModuleName : "?", haveModule ? frame.AddrPC.Offset - module.BaseOfImage : frame.AddrPC.Offset);
				}
			}
		}
		ResumeThread(thread);
		CloseHandle(thread);
	}
	SymCleanup(process);
	CloseHandle(process);
	return 0;
}
