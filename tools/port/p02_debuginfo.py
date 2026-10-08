import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from edit import edit

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'quickshell', 'src', 'core'))

edit('debuginfo.cpp', [
  ('''#include <fcntl.h>
#include <qconfig.h>''', '''#include <qconfig.h>'''),
  ('''#include <qtversion.h>
#include <unistd.h>
#include <xf86drm.h>

#include "build.hpp"

extern char** environ; // NOLINT
''', '''#include <qtversion.h>

#ifdef _WIN32
#include <cstdlib>

#include <dxgi.h>
#include <qsysinfo.h>
#else
#include <fcntl.h>
#include <unistd.h>
#include <xf86drm.h>

extern char** environ; // NOLINT
#endif

#include "build.hpp"
'''),
  ('''QString gpuInfo() {
	auto deviceCount''', r'''#ifdef _WIN32
QString gpuInfo() {
	QString info;
	auto stream = QTextStream(&info);

	IDXGIFactory1* factory = nullptr;
	// NOLINTNEXTLINE
	if (FAILED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory)))) {
		return "<CreateDXGIFactory1 failed>\n";
	}

	IDXGIAdapter1* adapter = nullptr;
	for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
		DXGI_ADAPTER_DESC1 desc {};
		adapter->GetDesc1(&desc);
		auto hex = [](uint num) { return QString::number(num, 16).rightJustified(4, '0'); };
		stream << "GPU " << i << "\n  Model: " << QString::fromWCharArray(desc.Description)
		       << "\n  Id: " << hex(desc.VendorId) << ':' << hex(desc.DeviceId)
		       << "\n  Dedicated VRAM: " << (desc.DedicatedVideoMemory / (1024 * 1024)) << " MiB\n";
		adapter->Release();
	}

	factory->Release();
	return info;
}
#else
QString gpuInfo() {
	auto deviceCount'''),
  (r'''	return info;
}

QString systemInfo() {
	QString info;
	auto stream = QTextStream(&info);

	stream << gpuInfo() << '\n';
''', r'''	return info;
}
#endif

QString systemInfo() {
	QString info;
	auto stream = QTextStream(&info);

	stream << gpuInfo() << '\n';

#ifdef _WIN32
	stream << "OS: " << QSysInfo::prettyProductName() << " (kernel " << QSysInfo::kernelVersion()
	       << ", " << QSysInfo::currentCpuArchitecture() << ")\n";
	return info;
#endif
'''),
  ('	for (auto** envp = environ; *envp != nullptr; ++envp) { // NOLINT', '''#ifdef _WIN32
	auto** environ = _environ; // NOLINT
#endif
	for (auto** envp = environ; *envp != nullptr; ++envp) { // NOLINT'''),
])

edit('CMakeLists.txt', [('''if (NOT WIN32)
	target_link_libraries(quickshell-core PRIVATE PkgConfig::libdrm)
endif()''', '''if (WIN32)
	target_link_libraries(quickshell-core PRIVATE dxgi)
else()
	target_link_libraries(quickshell-core PRIVATE PkgConfig::libdrm)
endif()''')])
