// cava's raw ASCII stream, driven by the default Windows output's WASAPI loopback.
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
// clang-format off
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <ksmedia.h>
#include <wrl/client.h>
// clang-format on

namespace {

using Microsoft::WRL::ComPtr;
using Clock = std::chrono::steady_clock;
constexpr size_t fftSize = 4096;
constexpr double pi = 3.14159265358979323846;

struct Config {
	int bars = 50, framerate = 60, maxRange = 1000;
	bool autosens = true;
	double noiseReduction = 20, low = 50, high = 10000;
};

std::string trim(const std::string& text) {
	auto first = text.find_first_not_of(" \t\r\n");
	return first == std::string::npos ? "" : text.substr(first, text.find_last_not_of(" \t\r\n") - first + 1);
}

Config readConfig(const std::vector<std::wstring>& args) {
	Config config;
	std::wstring path;
	for (size_t i = 0; i < args.size(); ++i) {
		if (args[i] != L"-p" || i + 1 == args.size()) throw std::runtime_error("usage: cava [-p config]");
		path = args[++i];
	}
	if (path.empty()) return config;
	std::ifstream file {std::filesystem::path(path)};
	// Missing Linux/default config paths are normal for this stand-in.
	if (!file) return config;
	std::string line, section;
	while (std::getline(file, line)) {
		line = trim(line.substr(0, line.find_first_of("#;")));
		if (line.empty()) continue;
		if (line.front() == '[' && line.back() == ']') { section = trim(line.substr(1, line.size() - 2)); continue; }
		auto equals = line.find('=');
		if (equals == std::string::npos) continue;
		auto key = trim(line.substr(0, equals)), value = trim(line.substr(equals + 1));
		auto number = [&] {
			size_t used = 0;
			double result = std::stod(value, &used);
			if (used != value.size() || !std::isfinite(result)) throw std::runtime_error("invalid config value");
			return result;
		};
		if (section == "general") {
			if (key == "bars") config.bars = static_cast<int>(std::clamp(number(), 1.0, 512.0));
			else if (key == "framerate") config.framerate = static_cast<int>(std::clamp(number(), 1.0, 240.0));
			else if (key == "autosens") config.autosens = number() != 0;
			else if (key == "lower_cutoff_freq") config.low = std::clamp(number(), 1.0, 20000.0);
			else if (key == "higher_cutoff_freq") config.high = std::clamp(number(), 2.0, 96000.0);
		} else if (section == "output") {
			if (key == "ascii_max_range") config.maxRange = static_cast<int>(std::clamp(number(), 1.0, 1000000.0));
			else if ((key == "method" && value != "raw") || (key == "data_format" && value != "ascii")
			         || (key == "channels" && value != "mono") || (key == "mono_option" && value != "average"))
				throw std::runtime_error("only raw ASCII with averaged mono is supported");
		} else if (section == "smoothing" && key == "noise_reduction") {
			config.noiseReduction = std::clamp(number(), 0.0, 100.0);
		}
	}
	if (config.high <= config.low) throw std::runtime_error("invalid frequency range");
	return config;
}

struct Apartment {
	Apartment() {
		if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED))) throw std::runtime_error("COM initialization failed");
	}
	~Apartment() { CoUninitialize(); }
};

// COM and handle cleanup stay on the worker. The lock protects handler handle lifetimes.
SRWLOCK consoleLock = SRWLOCK_INIT;
HANDLE stopEvent = nullptr;
HANDLE workerThread = nullptr;
HANDLE workerDone = nullptr;
BOOL WINAPI onConsoleEvent(DWORD event) {
	if (event != CTRL_C_EVENT && event != CTRL_BREAK_EVENT) return FALSE;
	AcquireSRWLockShared(&consoleLock);
	if (stopEvent && workerThread && workerDone) {
		SetEvent(stopEvent);
		// Repeat until shutdown is acknowledged, covering Ctrl+C just before WriteFile.
		do { CancelSynchronousIo(workerThread); }
		while (WaitForSingleObject(workerDone, 10) == WAIT_TIMEOUT);
	}
	ReleaseSRWLockShared(&consoleLock);
	return TRUE;
}

struct Wakeup {
	HANDLE stop = CreateEventW(nullptr, TRUE, FALSE, nullptr);
	HANDLE timer = nullptr;
	HANDLE worker = nullptr;
	HANDLE done = CreateEventW(nullptr, TRUE, FALSE, nullptr);
	bool handler = false;
	Wakeup() {
		// High-resolution, per-process waits avoid changing the system's timer resolution.
		timer = CreateWaitableTimerExW(nullptr, nullptr, 0x00000002, TIMER_ALL_ACCESS);
		if (!timer) timer = CreateWaitableTimerW(nullptr, FALSE, nullptr);
		DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &worker,
		                0, FALSE, DUPLICATE_SAME_ACCESS);
		if (stop && timer && worker && done) {
			stopEvent = stop; workerThread = worker; workerDone = done;
			handler = SetConsoleCtrlHandler(onConsoleEvent, TRUE) != FALSE;
		}
	}
	~Wakeup() {
		if (handler) SetConsoleCtrlHandler(onConsoleEvent, FALSE);
		if (done) SetEvent(done);
		// Active handlers observe 'done' and release their shared lock before closing.
		AcquireSRWLockExclusive(&consoleLock);
		stopEvent = workerThread = workerDone = nullptr;
		if (worker) CloseHandle(worker);
		if (timer) CloseHandle(timer);
		if (stop) CloseHandle(stop);
		if (done) CloseHandle(done);
		ReleaseSRWLockExclusive(&consoleLock);
	}
	bool waitUntil(Clock::time_point deadline) {
		auto ticks = std::chrono::duration_cast<std::chrono::nanoseconds>(deadline - Clock::now()).count() / 100;
		LARGE_INTEGER due {};
		due.QuadPart = -std::max<long long>(1, ticks);
		if (!SetWaitableTimer(timer, &due, 0, nullptr, nullptr, FALSE)) throw std::runtime_error("timer failed");
		HANDLE handles[] = {stop, timer};
		auto result = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
		if (result == WAIT_FAILED) throw std::runtime_error("wait failed");
		return result == WAIT_OBJECT_0 + 1;
	}
};

struct Spectrum {
	std::array<float, fftSize> samples {}, window {};
	std::array<size_t, fftSize> reversed {};
	std::array<std::complex<float>, fftSize> work {};
	std::array<std::complex<float>, fftSize / 2> roots {};
	size_t cursor = 0, nonzero = 0;
	bool dirty = false;
	Spectrum() {
		for (size_t i = 0; i < fftSize; ++i) {
			window[i] = static_cast<float>(0.5 - 0.5 * std::cos(2 * pi * i / (fftSize - 1)));
			for (size_t bits = i, bit = fftSize / 2; bit; bit >>= 1, bits >>= 1) reversed[i] |= (bits & 1) ? bit : 0;
		}
		for (size_t i = 0; i < roots.size(); ++i) {
			auto angle = -2 * pi * i / fftSize;
			roots[i] = {static_cast<float>(std::cos(angle)), static_cast<float>(std::sin(angle))};
		}
	}
	void clear() { samples.fill(0); cursor = nonzero = 0; dirty = true; }
	void push(float sample) {
		if (!std::isfinite(sample) || std::abs(sample) < 1e-7f) sample = 0;
		nonzero -= samples[cursor] != 0;
		nonzero += sample != 0;
		samples[cursor] = sample;
		cursor = (cursor + 1) % fftSize;
		dirty = true;
	}
	void analyze(std::vector<float>& levels, const Config& config, unsigned sampleRate) {
		dirty = false;
		std::fill(levels.begin(), levels.end(), 0);
		if (!nonzero) return;
		for (size_t i = 0; i < fftSize; ++i) work[reversed[i]] = samples[(cursor + i) % fftSize] * window[i];
		for (size_t size = 2; size <= fftSize; size *= 2) {
			for (size_t start = 0; start < fftSize; start += size) {
				for (size_t j = 0; j < size / 2; ++j) {
					auto even = work[start + j], odd = work[start + j + size / 2] * roots[j * (fftSize / size)];
					work[start + j] = even + odd;
					work[start + j + size / 2] = even - odd;
				}
			}
		}
		auto high = std::min(config.high, sampleRate * 0.49);
		auto low = std::min(config.low, high * 0.5);
		auto ratio = high / low;
		for (size_t bar = 0; bar < levels.size(); ++bar) {
			double begin = low * std::pow(ratio, static_cast<double>(bar) / levels.size()) * fftSize / sampleRate;
			double end = low * std::pow(ratio, static_cast<double>(bar + 1) / levels.size()) * fftSize / sampleRate;
			double energy = 0, weight = 0;
			// Fractional bin overlap keeps the narrow bass bands from being empty.
			for (size_t bin = std::max<size_t>(1, static_cast<size_t>(begin)); bin <= static_cast<size_t>(end) && bin < fftSize / 2; ++bin) {
				auto overlap = std::max(0.0, std::min(end, bin + 1.0) - std::max(begin, static_cast<double>(bin)));
				energy += std::norm(work[bin]) * overlap;
				weight += overlap;
			}
			levels[bar] = static_cast<float>(std::sqrt(energy / std::max(weight, 1e-12)) * (4.0 / fftSize));
		}
	}
};

struct Loopback {
	ComPtr<IMMDeviceEnumerator> enumerator;
	ComPtr<IAudioClient> client;
	ComPtr<IAudioCaptureClient> capture;
	std::wstring deviceId;
	unsigned sampleRate = 48000, channels = 0, sampleBytes = 0, blockAlign = 0;
	bool floating = false;
	Loopback() {
		if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator))))
			throw std::runtime_error("audio enumerator failed");
	}
	~Loopback() { close(); }
	void close() {
		if (client) client->Stop();
		capture.Reset(); client.Reset(); deviceId.clear();
	}
	bool refresh() {
		ComPtr<IMMDevice> device;
		if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) { close(); return false; }
		LPWSTR id = nullptr;
		if (FAILED(device->GetId(&id))) { close(); return false; }
		std::wstring nextId(id);
		CoTaskMemFree(id);
		if (capture && nextId == deviceId) return false;
		close();
		if (FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(client.GetAddressOf())))) return false;
		WAVEFORMATEX* format = nullptr;
		if (FAILED(client->GetMixFormat(&format))) { close(); return false; }
		auto tag = format->wFormatTag;
		if (tag == WAVE_FORMAT_EXTENSIBLE && format->cbSize >= sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)) {
			auto* extended = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format);
			if (IsEqualGUID(extended->SubFormat, KSDATAFORMAT_SUBTYPE_IEEE_FLOAT)) tag = WAVE_FORMAT_IEEE_FLOAT;
			else if (IsEqualGUID(extended->SubFormat, KSDATAFORMAT_SUBTYPE_PCM)) tag = WAVE_FORMAT_PCM;
		}
		floating = tag == WAVE_FORMAT_IEEE_FLOAT;
		channels = format->nChannels; sampleRate = format->nSamplesPerSec;
		sampleBytes = format->wBitsPerSample / 8; blockAlign = format->nBlockAlign;
		bool supported = channels && sampleRate && blockAlign >= channels * sampleBytes
		              && ((floating && sampleBytes == 4) || (tag == WAVE_FORMAT_PCM && sampleBytes == 2));
		auto result = supported ? client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
		                                          1000000, 0, format, nullptr) : AUDCLNT_E_UNSUPPORTED_FORMAT;
		CoTaskMemFree(format);
		if (FAILED(result) || FAILED(client->GetService(IID_PPV_ARGS(&capture))) || FAILED(client->Start())) {
			close(); return false;
		}
		deviceId = std::move(nextId);
		return true;
	}
	bool drain(Spectrum& spectrum) {
		if (!capture) return false;
		bool received = false;
		UINT32 packet = 0;
		auto result = capture->GetNextPacketSize(&packet);
		while (SUCCEEDED(result) && packet) {
			BYTE* data = nullptr;
			UINT32 frames = 0;
			DWORD flags = 0;
			result = capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
			if (FAILED(result)) break;
			if (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) spectrum.clear();
			for (UINT32 frame = 0; frame < frames; ++frame) {
				float mono = 0;
				if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT)) {
					for (unsigned channel = 0; channel < channels; ++channel) {
						auto* source = data + frame * blockAlign + channel * sampleBytes;
						if (floating) {
							float sample;
							std::memcpy(&sample, source, sizeof(sample));
							if (std::isfinite(sample)) mono += sample;
						} else {
							short sample;
							std::memcpy(&sample, source, sizeof(sample));
							mono += sample / 32768.0f;
						}
					}
				}
				spectrum.push(mono / channels);
			}
			received = received || frames != 0;
			result = capture->ReleaseBuffer(frames);
			if (SUCCEEDED(result)) result = capture->GetNextPacketSize(&packet);
		}
		// Includes AUDCLNT_E_DEVICE_INVALIDATED: reopen on the next endpoint check.
		if (FAILED(result)) close();
		return received;
	}
};

bool writeFrame(const std::vector<float>& bars, int maxRange, std::string& line, HANDLE output, HANDLE stop) {
	line.clear();
	for (auto value: bars) {
		line += std::to_string(static_cast<int>(std::lround(std::clamp(value, 0.0f, 1.0f) * maxRange)));
		line += ';';
	}
	line += '\n';
	// WriteFile bypasses CRT buffering and CRLF translation: each frame is flushed as LF.
	size_t offset = 0;
	while (offset < line.size()) {
		if (WaitForSingleObject(stop, 0) == WAIT_OBJECT_0) return false;
		DWORD written = 0;
		if (!WriteFile(output, line.data() + offset, static_cast<DWORD>(line.size() - offset), &written, nullptr)
		    || !written) return false;
		offset += written;
	}
	return true;
}

} // namespace

int cava(const std::vector<std::wstring>& args) {
	try {
		auto config = readConfig(args);
		auto output = GetStdHandle(STD_OUTPUT_HANDLE);
		if (!output || output == INVALID_HANDLE_VALUE) return 0;
		Apartment apartment;
		Wakeup wakeup;
		if (!wakeup.stop || !wakeup.timer || !wakeup.worker || !wakeup.done || !wakeup.handler)
			throw std::runtime_error("cannot create wait handles");
		Loopback audio;
		Spectrum spectrum;
		std::vector<float> levels(config.bars), bars(config.bars), falling(config.bars);
		std::string line;
		line.reserve(config.bars * 8 + 1);
		auto period = std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(1.0 / config.framerate));
		auto now = Clock::now(), nextFrame = now, nextPoll = now, nextDevice = now, lastAudio = now, lastFrame = now - period;
		double gain = 8;
		bool gainReady = false;
		while (WaitForSingleObject(wakeup.stop, 0) != WAIT_OBJECT_0) {
			now = Clock::now();
			if (now >= nextDevice) {
				if (audio.refresh()) { spectrum.clear(); std::fill(levels.begin(), levels.end(), 0); }
				nextDevice = now + std::chrono::milliseconds(audio.capture ? 500 : 1000);
			}
			if (now >= nextPoll) {
				// A resumed stream must not retain the FFT window from before the silence.
				if (now - lastAudio > std::chrono::milliseconds(100) && spectrum.nonzero) spectrum.clear();
				if (audio.drain(spectrum)) lastAudio = now;
				nextPoll = now + std::chrono::milliseconds(10);
			}
			if (now >= nextFrame) {
				auto dt = std::clamp(std::chrono::duration<double>(now - lastFrame).count(), 0.001, 0.25);
				lastFrame = now;
				if (!audio.capture || now - lastAudio > std::chrono::milliseconds(30)) std::fill(levels.begin(), levels.end(), 0);
				else if (spectrum.dirty) spectrum.analyze(levels, config, audio.sampleRate);
				auto peak = *std::max_element(levels.begin(), levels.end());
				if (config.autosens && peak > 1e-5f) {
					auto desired = std::clamp(0.92 / peak, 0.05, 10000.0);
					if (!gainReady) { gain = desired; gainReady = true; }
					else gain += (desired - gain) * (1 - std::exp(-dt / (desired < gain ? 0.06 : 2.5)));
				}
				for (size_t i = 0; i < bars.size(); ++i) {
					auto target = static_cast<float>(std::clamp(levels[i] * gain, 0.0, 1.0));
					if (target >= bars[i]) {
						bars[i] += (target - bars[i]) * static_cast<float>(1 - std::exp(-dt / (0.015 + config.noiseReduction * 0.0005)));
						falling[i] = 0;
					} else {
						// A leaky integral plus accelerating gravity gives a soft, finite tail.
						falling[i] += static_cast<float>(dt * 5 / (1 + config.noiseReduction / 30));
						bars[i] = std::max(target, bars[i] * static_cast<float>(std::exp(-dt / (0.10 + config.noiseReduction * 0.002)))
						                         - falling[i] * static_cast<float>(dt));
					}
				}
				if (!writeFrame(bars, config.maxRange, line, output, wakeup.stop)) return 0;
				nextFrame += period;
				if (nextFrame <= now) nextFrame = now + period;
			}
			if (!wakeup.waitUntil(std::min(nextFrame, nextPoll))) break;
		}
		return 0;
	} catch (const std::exception& error) {
		std::fprintf(stderr, "cava: %s\n", error.what());
		return 1;
	}
}
