import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from edit import edit

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'quickshell'))

edit('src/window/proxywindow.hpp', [
  ('''	[[nodiscard]] PendingRegion* mask() const;
	virtual void setMask(PendingRegion* mask);''', '''	[[nodiscard]] PendingRegion* mask() const;
	virtual void setMask(PendingRegion* mask);

	// Lets a platform backend apply input masks itself instead of QWindow::setMask
	// (which clips rendering on some platforms). hasMask is false when no mask is set.
	using InputMaskHandler = void (*)(QWindow* window, const QRegion& mask, bool hasMask);
	static void setInputMaskHandler(InputMaskHandler handler);'''),
])

edit('src/window/proxywindow.cpp', [
  ('''void ProxyWindowBase::onPolished() {
	if (this->pendingPolish.inputMask) {
		QRegion mask;
		if (this->mMask != nullptr) {
			mask = this->mMask->applyTo(QRect(0, 0, this->width(), this->height()));
		}

		this->window->setFlag(Qt::WindowTransparentForInput, this->mMask != nullptr && mask.isEmpty());
		this->window->setMask(mask);
''', '''namespace {
ProxyWindowBase::InputMaskHandler INPUT_MASK_HANDLER = nullptr; // NOLINT
}

void ProxyWindowBase::setInputMaskHandler(InputMaskHandler handler) {
	INPUT_MASK_HANDLER = handler;
}

void ProxyWindowBase::onPolished() {
	if (this->pendingPolish.inputMask) {
		QRegion mask;
		if (this->mMask != nullptr) {
			mask = this->mMask->applyTo(QRect(0, 0, this->width(), this->height()));
		}

		if (INPUT_MASK_HANDLER) {
			INPUT_MASK_HANDLER(this->window, mask, this->mMask != nullptr);
		} else {
			this->window->setFlag(Qt::WindowTransparentForInput, this->mMask != nullptr && mask.isEmpty());
			this->window->setMask(mask);
		}
'''),
])

edit('CMakeLists.txt', [
  ('boption(X11 "X11" ON)', 'boption(WIN32_BACKEND "Windows" ${WIN32})\nboption(X11 "X11" ON)'),
])

edit('src/CMakeLists.txt', [
  ('''if (X11)
	add_subdirectory(x11)
endif()''', '''if (X11)
	add_subdirectory(x11)
endif()

if (WIN32_BACKEND)
	add_subdirectory(win32)
endif()'''),
])
