# Dependencias y modelos

## Producto principal

Swift/SwiftUI, AppKit, Core Audio, AVFoundation, Speech, FoundationModels, CoreText, CoreGraphics, CryptoKit, Security, URLSession y SQLite del sistema. Sin dependencias externas. Toolchain verificado: Xcode 27.1, SDK macOS 27 y Swift 6.4; destino de ejecución macOS 26.0+, arm64. Se necesita un SDK que declare las APIs nuevas, aunque se compruebe su disponibilidad en ejecución. No se requieren cuentas de pago ni claves API para ejecutar la aplicación localmente.

Documentación oficial verificada al implementar:

- [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)
- [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)

También se comprobaron los headers CATapDescription/AudioHardwareTapping y las interfaces Swift de los SDK instalados. `bundleIDs` e `isProcessRestoreEnabled` requieren macOS 26. `tokenCount(for:)` requiere 26.4 y tiene comprobación de disponibilidad; se consulta `contextSize` y se estiman tokens conservadoramente en 26.0–26.3. CryptoKit solo calcula claves estables de los hallazgos, sin cargar modelos ni comunicarse por red.

## FluidAudio opcional

[FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio), versión exacta **0.17.3**, commit **a6b826ce9a09028fc685a4b32a8927ec920c3188**, licencia Apache 2.0 según repositorio. El wrapper tiene su propio Package.swift. El instalador obtiene ese commit y aplica únicamente un manifiesto de compilación reducido; conserva el código de implementación y LICENSE originales. Preparación explícita:

```bash
./script/prepare_fluid.sh
```

Selecciona el `FluidWorker` generado en Configuración → Modelos. Prepara por separado el modelo [Parakeet Redux Core ML](https://huggingface.co/FluidInference/parakeet-redux-coreml), revisa su licencia y sigue la [guía de archivos locales](https://github.com/FluidInference/FluidAudio/blob/v0.17.3/Documentation/ASR/ManualModelLoading.md). La carpeta debe contener Preprocessor.mlmodelc, Encoder.mlmodelc, Decoder.mlmodelc, JointDecision.mlmodelc y parakeet_vocab.json. Si el repositorio entrega tarballs, extráelos conservando los nombres. Copiar un modelo ya preparado desde otro equipo no requiere red.

`AsrModels.loadLocal(from:version:.redux)` es la ruta de ejecución y no descarga archivos. El preprocesador usa CPU; la configuración de encoder/decoder/joint permite CPU+ANE. Core ML determina qué operaciones ejecuta realmente cada unidad. Redux es un modelo multilingüe de pesos ternarios, descrito por el proveedor con una descarga aproximada de 220 MB; no equivale a memoria residente total.

El manifiesto de preparación excluye el artefacto NeMo de normalización de texto, que no aporta al ASR. Se comprobó que desactivar solamente su trait no evita que SwiftPM intente descargar ese binario de 87 MB; la descarga agotó su tiempo. Por ello se elimina ese target del manifiesto reducido. El código de FluidAudio conserva sus rutas condicionales sin NeMo. No se usa TTS ni diarización en producción.

## MLX opcional

[mlx-lm](https://github.com/ml-explore/mlx-lm), versión fijada **0.31.3**, MIT; versión publicada en [PyPI](https://pypi.org/project/mlx-lm/0.31.3/). Usa Python 3.11+ preferiblemente en un entorno dedicado. No se instala automáticamente:

```bash
LAI_PYTHON=/ruta/a/python3.11 ./script/prepare_mlx.sh
```

Prepara, con autorización explícita, una carpeta del modelo [Qwen2.5-1.5B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit). Revisa su licencia. Por ejemplo, con el CLI de Hugging Face instalado, `hf download mlx-community/Qwen2.5-1.5B-Instruct-4bit --local-dir Models/Qwen2.5-1.5B-Instruct-4bit` es una descarga manual; no la ejecuta la aplicación.

Configura Python de `Integrations/.venv/bin/python`, `Integrations/mlx_summary.py` y la carpeta del modelo. El proceso usa Metal/CPU a través de MLX, **no** ANE, contexto acotado, generación greedy y JSON validado. Se termina tras cada resumen para liberar pesos y caché. La compatibilidad de la versión y los pesos debe probarse antes de usar este backend en una reunión importante.

## Google AI opcional · sin SDK externo

El backend Gemini usa directamente la API REST oficial con URLSession. El modo local no requiere claves. Gemini requiere una clave propia, Internet y cuota del proyecto de Google; su disponibilidad y facturación pertenecen a Google. El modelo inicial es `gemini-3.8-flash`, editable. La clave se conserva en el Llavero de macOS, no en este repositorio.

Documentación oficial consultada el 21 de octubre de 2026: [modelos](https://ai.google.dev/gemini-api/docs/models), [claves](https://ai.google.dev/gemini-api/docs/api-key), [generateContent y responseFormat](https://ai.google.dev/api/generate-content), [salidas estructuradas](https://ai.google.dev/gemini-api/docs/structured-output). Se utiliza `generationConfig.responseFormat.text` con `mimeType: APPLICATION_JSON` y schema. No se integra ningún cliente de audio remoto ni servicio de traducción.
