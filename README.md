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
- Dataset: `en_all`
- Started: `2026-02-16T03:13:52Z`

![iOS TTS Overall Score](docs/ios_tts_overall_score.svg)
![iOS TTS Tok/s](docs/ios_tts_tok_per_sec.svg)
![iOS TTS RTF](docs/ios_tts_rtf.svg)
![iOS TTS CPU Avg](docs/ios_tts_cpu_avg.svg)
![iOS TTS Mem Max](docs/ios_tts_mem_max.svg)

| Model | Engine | Prompts | Model Load (ms) | Overall | Speed | Tok/s Score | Resource | Median RTF | Median Tok/s | Median CPU | Median Mem (MB) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| AVSpeech (System) | `native.avspeech` | 12 | 0 | 100.00 | - | 100.00 | 100.00 | - | 151.34 | 69.40 | 21.28 |
| Matcha (en_US LJSpeech) + Vocos | `sherpa.offline` | 12 | 1421 | 87.77 | 94.39 | 100.00 | 52.85 | 0.084 | 25.68 | 394.77 | 211.24 |
| Kitten Nano EN (v0.2 fp16) | `sherpa.offline` | 12 | 925 | 59.72 | 75.45 | 20.02 | 79.97 | 0.368 | 5.14 | 255.54 | 193.31 |
| Kitten Nano (en v0.1 fp16) | `sherpa.offline` | 12 | 950 | 58.90 | 72.86 | 21.86 | 79.58 | 0.407 | 5.61 | 265.40 | 108.02 |
| Kokoro EN (v0.19) | `sherpa.offline` | 12 | 1090 | 43.59 | 58.60 | 15.63 | 47.98 | 0.621 | 4.01 | 374.87 | 832.54 |
| Kitten Mini EN (v0.1 fp16) | `sherpa.offline` | 12 | 1611 | 24.57 | 24.30 | 6.34 | 52.59 | 1.135 | 1.63 | 375.27 | 426.58 |
| VITS LJS (Int8) | `sherpa.offline` | 12 | 1099 | 21.41 | 0.00 | 4.69 | 100.00 | 2.023 | 1.20 | 205.85 | 139.63 |
| VITS VCTK (Int8) | `sherpa.offline` | 12 | 994 | 20.98 | 0.00 | 5.58 | 96.52 | 2.062 | 1.43 | 215.50 | 122.42 |
| VITS Melo (ZH+EN, Int8) | `sherpa.offline` | 12 | 1840 | 20.07 | 0.00 | 3.21 | 95.54 | 2.874 | 0.83 | 208.99 | 210.78 |
| Kokoro Int8 (Multi-lang v1.0) | `sherpa.offline` | 12 | 1517 | 17.06 | 0.00 | 5.44 | 77.15 | 1.822 | 1.40 | 233.39 | 515.20 |
| Kokoro Multi-lang INT8 (v1.1) | `sherpa.offline` | 12 | 1373 | 16.91 | 0.00 | 6.66 | 74.55 | 1.569 | 1.71 | 236.05 | 587.88 |
<!-- BENCHMARK_RESULTS_END -->

## Notes

- Models are downloaded at runtime from Hugging Face and cached under Application Support.
- For device signing from CLI, `project.local.yml` is used if present. Copy `project.local.yml.example` to `project.local.yml` and set `DEVELOPMENT_TEAM` / `PRODUCT_BUNDLE_IDENTIFIER` as needed.
