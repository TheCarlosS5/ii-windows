import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from edit import edit

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'quickshell', 'src', 'launch'))

edit('command.cpp', [
  ('#include <unistd.h>\n', '#ifndef _WIN32\n#include <unistd.h>\n#endif\n'),
  ('''	// Has to happen before extra threads are spawned.
	if (state.misc.daemonize) {''', '''	// Has to happen before extra threads are spawned.
#ifdef _WIN32
	// No fork() on Windows. The ii-windows launcher starts quickshell as a detached
	// GUI process instead, so daemonizing here is unnecessary.
	if (state.misc.daemonize) {
		qWarning() << "--daemonize is not supported on Windows; running in the foreground.";
	}
#else
	if (state.misc.daemonize) {'''),
  ('''			return ret;
		}
	}
''', '''			return ret;
		}
	}
#endif
'''),
])

edit('main.cpp', [
  ('#include <fcntl.h>\n', '#ifndef _WIN32\n#include <fcntl.h>\n'),
  ('#include <unistd.h>\n', '#include <unistd.h>\n#endif\n'),
  ('''void exitDaemon(int code) {
	if (DAEMON_PIPE == -1) return;
''', '''void exitDaemon(int code) {
	if (DAEMON_PIPE == -1) return;
#ifdef _WIN32
	(void) code;
}
#else
'''),
  ('''	close(fd);
}
''', '''	close(fd);
}
#endif
'''),
])

edit('launch.cpp', [
  ('#include <unistd.h>\n', ''),
  ('base36Encode(getpid())', 'base36Encode(qs::platform::currentPid())'),
  ('.pid = getpid(),', '.pid = qs::platform::currentPid(),'),
])
