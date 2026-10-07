import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from edit import edit

os.chdir(r'C:\Users\Calos\Desktop\ii-windows\quickshell\src')

edit('core/debuginfo.cpp', [
  ('''#ifdef _WIN32
	auto** environ = _environ; // NOLINT
#endif
	for (auto** envp = environ; *envp != nullptr; ++envp) { // NOLINT''', '''#ifdef _WIN32
	auto** envBlock = _environ; // NOLINT
#else
	auto** envBlock = environ;
#endif
	for (auto** envp = envBlock; *envp != nullptr; ++envp) { // NOLINT'''),
])

edit('core/logging.cpp', [
  ('#ifdef _WIN32\n#include <io.h>\n#else', '''#ifdef _WIN32
#include <io.h>

namespace {
int read(int fd, void* buf, size_t count) { return _read(fd, buf, static_cast<unsigned>(count)); }
int write(int fd, const void* buf, size_t count) {
	return _write(fd, buf, static_cast<unsigned>(count));
}
} // namespace
#else'''),
])

# `typeof` is a GNU keyword that clang-cl does not enable; __typeof__ works in every mode.
edit('core/util.hpp', [('typeof(object)', '__typeof__(object)', 2)])

edit('io/process.cpp', [
  ('''	kill(static_cast<qint32>(this->process->processId()), signal); // NOLINT''', '''#ifdef _WIN32
	// Windows has no signals. SIGKILL maps to TerminateProcess, anything else asks
	// the program to close (WM_CLOSE to its windows).
	if (signal == 9) this->process->kill();
	else this->process->terminate();
#else
	kill(static_cast<qint32>(this->process->processId()), signal); // NOLINT
#endif'''),
])

edit('launch/launch_p.hpp', [('#include <CLI/App.hpp>\n', '#include <CLI/App.hpp>\n\n#include "../core/platform.hpp"\n')])
