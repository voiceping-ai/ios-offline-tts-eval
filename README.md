# ios-offline-tts-eval

SwiftUI app for evaluating on-device TTS engines/models on iOS (physical devices only).

Engines (v1.1):
- `AVSpeechSynthesizer` (system baseline)
- `SherpaOnnxKit` Offline TTS (ONNX Runtime, CPU) with curated presets (Kokoro, VITS, Matcha+Vocos, Kitten)
- `ONNX Runtime` (CPU) NeMo FastPitch + HiFiGAN (local bundle import; no weights redistributed)

No iOS Simulators are used or required.

## Setup

This repo expects to be cloned next to `ios-android-offline-speech-translation/` (it uses the shared `LocalPackages/SherpaOnnxKit` path dependency):

```
<parent>/
  ios-offline-tts-eval/
  ios-android-offline-speech-translation/
```

1. Prepare SherpaOnnxKit binary deps (shared from the translation repo):

```bash
./scripts/setup-ios-deps.sh
```

2. Generate Xcode project:

```bash
xcodegen generate
```

3. Build/install to a physical device:

```bash
IOS_COREDEVICE_ID=<CoreDevice ID> IOS_DEVICE_UDID=<UDID> ./scripts/install-device.sh
```

## NeMo (Local Bundle Import)

NeMo ONNX weights are **not** downloaded by the app (and are not redistributed by this repo). Instead, export/pick a local bundle directory containing:

- `fastpitch.onnx`
- `hifigan.onnx`
- `symbols.json`
- `config.json`

Then push it into the app container and import on-device:

```bash
IOS_COREDEVICE_ID=<CoreDevice ID> IOS_DEVICE_UDID=<UDID> \
  MODEL_ID=nemo-fastpitch-hifigan-en \
  BUNDLE_DIR=/path/to/your/nemo-bundle-dir \
  ./scripts/nemo/push_bundle_to_device.sh
```

Open the app and visit **Models** to import.

Find connected devices:

```bash
xcrun devicectl list devices
xcrun xctrace list devices
```

## Benchmark (Physical Device)

Run the full benchmark on the device and pull exported JSON/CSV into `device-exports/`:

```bash
IOS_COREDEVICE_ID=<CoreDevice ID> IOS_DEVICE_UDID=<UDID> \
  TTSEVAL_LANG=en TTSEVAL_DATASET=all TTSEVAL_PROMPT_LIMIT=0 \
  ./scripts/test-all-device.sh
```

Update README benchmark tables + regenerate SVG graphs from the latest `device-exports/**/results-*.json`:

```bash
python3 scripts/generate-benchmark-report.py --update-readme
```

<!-- BENCHMARK_RESULTS_START -->
### Latest Benchmark

- Device: `iPad8,7` (iPadOS 26.3)
- Dataset: `all`
- Started: `2026-02-15T13:36:15Z`

![iOS TTS Overall Score](docs/ios_tts_overall_score.svg)
![iOS TTS Tok/s](docs/ios_tts_tok_per_sec.svg)
![iOS TTS RTF](docs/ios_tts_rtf.svg)
![iOS TTS CPU Avg](docs/ios_tts_cpu_avg.svg)
![iOS TTS Mem Max](docs/ios_tts_mem_max.svg)

| Model | Engine | Prompts | Model Load (ms) | Overall | Speed | Tok/s Score | Resource | Median RTF | Median Tok/s | Median CPU | Median Mem (MB) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| AVSpeech (System) | `native.avspeech` | 12 | - | 100.00 | - | 100.00 | 100.00 | - | 147.48 | 64.00 | 20.52 |
| Matcha (en_US LJSpeech) + Vocos | `sherpa.offline` | 12 | - | 89.83 | 96.66 | 100.00 | 57.52 | 0.050 | 40.90 | 397.24 | 1151.48 |
| Kitten Nano (en v0.1 fp16) | `sherpa.offline` | 12 | - | 61.82 | 81.98 | 20.37 | 73.57 | 0.270 | 8.33 | 271.52 | 1291.28 |
| Kokoro Int8 (Multi-lang v1.0) | `sherpa.offline` | 12 | - | 25.66 | 8.78 | 4.54 | 99.56 | 1.368 | 1.86 | 239.57 | 564.79 |
| VITS LJS (Int8) | `sherpa.offline` | 12 | - | 21.14 | 0.00 | 3.81 | 100.00 | 1.572 | 1.56 | 211.41 | 833.34 |
<!-- BENCHMARK_RESULTS_END -->

## Notes

- Models are downloaded at runtime from Hugging Face and cached under Application Support.
- For device signing from CLI, `project.local.yml` is used if present. Copy `project.local.yml.example` to `project.local.yml` and set `DEVELOPMENT_TEAM` / `PRODUCT_BUNDLE_IDENTIFIER` as needed.
