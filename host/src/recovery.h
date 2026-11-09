#pragma once
#include <windows.h>

namespace ii::recovery {
void showIfNeeded(HWND host);
bool pending();
bool dispatch(MSG& message);
void close();
}
