#include "common.h"

#include <windows.h>
// clang-format off
#include <mmdeviceapi.h>
#include <endpointvolume.h>
// clang-format on

namespace ii::volume {

namespace {

// The default output changes (headphones plugged in, Bluetooth): ask for it each time, it is cheap.
// COM is initialised here and undone at the end, whatever the host thread already did.
struct Endpoint {
	IMMDeviceEnumerator* enumerator = nullptr;
	IMMDevice* device = nullptr;
	IAudioEndpointVolume* volume = nullptr;
	bool uninit = false;

	Endpoint() {
		auto hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
		uninit = SUCCEEDED(hr); // RPC_E_CHANGED_MODE: COM is there already in another mode, do not undo it
		if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))
		    && SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device)))
			device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&volume));
	}
	~Endpoint() {
		if (volume) volume->Release();
		if (device) device->Release();
		if (enumerator) enumerator->Release();
		if (uninit) CoUninitialize();
	}
	Endpoint(const Endpoint&) = delete;
	Endpoint& operator=(const Endpoint&) = delete;
};

} // namespace

void handleKey(unsigned vk) {
	Endpoint endpoint;
	if (!endpoint.volume) {
		log(L"volume: no default output device, key %u ignored", vk);
		return;
	}
	BOOL muted = FALSE;
	endpoint.volume->GetMute(&muted);
	if (vk == VK_VOLUME_MUTE) {
		endpoint.volume->SetMute(!muted, nullptr);
		return;
	}
	// Like Windows: turning the volume up while muted unmutes first.
	if (muted && vk == VK_VOLUME_UP) endpoint.volume->SetMute(FALSE, nullptr);
	if (vk == VK_VOLUME_UP) endpoint.volume->VolumeStepUp(nullptr);
	else if (vk == VK_VOLUME_DOWN) endpoint.volume->VolumeStepDown(nullptr);
}

} // namespace ii::volume
