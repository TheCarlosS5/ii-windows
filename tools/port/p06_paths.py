import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from edit import edit

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'quickshell', 'src'))

edit('core/platform.hpp', [
  ('''QString lastErrorString();''', '''QString lastErrorString();

// Shells often build paths by stripping "file://" from URLs, which on Windows leaves
// "/C:/dir". That form works as a URL path but not as a filesystem path, so file APIs
// normalize it to "C:/dir". Identity on other platforms and for other paths.
QString normalizeLocalPath(const QString& path);'''),
])

edit('core/platform.cpp', [
  ('''#else

pid_t currentPid() { return getpid(); }''', '''QString normalizeLocalPath(const QString& path) {
	if (path.size() >= 3 && (path[0] == '/' || path[0] == '\\\\') && path[1].isLetter() && path[2] == ':') {
		return path.sliced(1);
	}
	return path;
}

#else

QString normalizeLocalPath(const QString& path) { return path; }

pid_t currentPid() { return getpid(); }'''),
])

edit('io/fileview.cpp', [
  ('''	auto p = path.startsWith("file://") ? path.sliced(7) : path;
	if (p == this->targetPath) return;''', '''	auto p = qs::platform::normalizeLocalPath(path.startsWith("file://") ? path.sliced(7) : path);
	if (p == this->targetPath) return;'''),
])

edit('io/process.cpp', [
  ('''	    workingDirectory.isEmpty() ? workingDirectory : QDir(workingDirectory).absolutePath();''',
   '''	    workingDirectory.isEmpty()
	        ? workingDirectory
	        : QDir(qs::platform::normalizeLocalPath(workingDirectory)).absolutePath();'''),
])

for f in ('io/fileview.cpp', 'io/process.cpp'):
    s = open(f, encoding='utf-8').read()
    if '"../core/platform.hpp"' not in s:
        s = s.replace('#include "../core/generation.hpp"\n', '#include "../core/generation.hpp"\n#include "../core/platform.hpp"\n', 1)
        if '"../core/platform.hpp"' not in s:
            sys.exit(f'could not add include to {f}')
        open(f, 'w', encoding='utf-8', newline='').write(s)
        print('include added', f)
