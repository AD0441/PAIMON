# Dependencias y modelos · PAIMON 0.6.0

## Producto principal

Swift/SwiftUI, AppKit, Core Audio, AVFoundation, Speech, FoundationModels, CoreText, CoreGraphics, CryptoKit, Security, URLSession y SQLite del sistema. Sin dependencias externas. Toolchain verificado: Xcode 27.1, SDK macOS 27 y Swift 6.4; destino de ejecución macOS 26.0+, arm64. Se necesita un SDK que declare las APIs nuevas, aunque se compruebe su disponibilidad en ejecución. No se requieren cuentas de pago ni claves API para ejecutar la aplicación localmente.

El modo predeterminado mantiene captura, transcripción y resumen en el Mac una vez preparados sus recursos. La opción de Google AI añade únicamente un cliente HTTPS nativo para resúmenes; no incorpora un SDK ni requiere instalar otro modelo local.

Documentación oficial verificada al implementar:

- [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)
- [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)

También se comprobaron los headers CATapDescription/AudioHardwareTapping y las interfaces Swift de los SDK instalados. `bundleIDs` e `isProcessRestoreEnabled` requieren macOS 26. `tokenCount(for:)` requiere 26.4 y tiene comprobación de disponibilidad; se consulta `contextSize` y se estiman tokens conservadoramente en 26.0–26.3. CryptoKit calcula identificadores estables de hallazgos y de configuración/contexto, sin cargar modelos ni comunicarse por red.

## FluidAudio opcional

[FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio), versión exacta **0.17.3**, commit **a6b826ce9a09028fc685a4b32a8927ec920c3188**, licencia Apache 2.0 según repositorio. El wrapper tiene su propio Package.swift. El instalador obtiene ese commit y aplica únicamente un manifiesto de compilación reducido; conserva el código de implementación y LICENSE originales. Preparación explícita:

```bash
./script/prepare_fluid.sh
```

En la app empaquetada, **Ajustes → Modelos → FluidAudio · Parakeet Redux** permite descargar, activar y borrar el modelo. La descarga de [Parakeet Redux Core ML](https://huggingface.co/FluidInference/parakeet-redux-coreml/tree/8c5ef97a29cd120dc76b354b3f22b7fec3b486f9) verifica los archivos y utiliza el ejecutable FluidWorker incluido. Para usar una carpeta propia, selecciona la ruta desde **Usar modelos propios**. Debe contener Preprocessor.mlmodelc, Encoder.mlmodelc, Decoder.mlmodelc, JointDecisionv3.mlmodelc y parakeet_vocab.json.

`AsrModels.loadLocal(from:version:.redux)` es la ruta de ejecución y no descarga archivos. El preprocesador usa CPU; la configuración de encoder/decoder/joint permite CPU+ANE. Core ML determina qué operaciones ejecuta realmente cada unidad. Redux es un modelo multilingüe de pesos ternarios, descrito por el proveedor con una descarga aproximada de 220 MB; no equivale a memoria residente total.

El manifiesto de preparación excluye el artefacto NeMo de normalización de texto, que no aporta al ASR. Se comprobó que desactivar solamente su trait no evita que SwiftPM intente descargar ese binario de 87 MB; la descarga agotó su tiempo. Por ello se elimina ese target del manifiesto reducido. El código de FluidAudio conserva sus rutas condicionales sin NeMo. PAIMON no utiliza TTS de FluidAudio.

### Diarización local opcional

En la app instalada, abre **Ajustes → Modelos → Diarización** y pulsa **Descargar modelos**. PAIMON obtiene unos 14 MB desde Hugging Face, verifica tamaño y digest por archivo, instala ambos modelos y selecciona la carpeta. Activa **Separar voces** y pulsa un hablante en la transcripción para cambiarle el nombre. **Borrar modelos** elimina la descarga de PAIMON y desactiva la opción. Las carpetas seleccionadas manualmente se gestionan desde **Usar modelos propios**.

La compilación empaquetada incluye FluidWorker y su licencia Apache 2.0. Para empaquetar desde un checkout limpio, compila primero con `./script/prepare_fluid.sh` y ejecuta `PAIMON_FLUID_WORKER=/ruta/al/FluidWorker ./script/build_and_run.sh --install`. El mismo ejecutable admite transcripción y diarización.

Los pesos son conversiones a Core ML de pyannote y WeSpeaker por Fluid Inference. La app descarga también los avisos de atribución desde la misma revisión fijada. [Procedencia y licencias](https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/7eab74f3463c736418d0eb10296261ae581146c9/NOTICE.md) · [Archivos de los modelos](https://huggingface.co/FluidInference/speaker-diarization-coreml/tree/7eab74f3463c736418d0eb10296261ae581146c9).

La app carga los archivos locales mediante `DiarizerModels.load(localSegmentationModel:localEmbeddingModel:)` durante las sesiones. La descarga solo se inicia al pulsar el botón. La configuración permite CPU y Neural Engine. Core ML decide dónde se ejecuta cada operación. La cola de captura admite 32 búferes y se conservan ventanas PCM de hasta diez segundos por fuente, más el bloque entrante. En vivo, los turnos pueden aparecer después del texto. Una pausa o un bloque perdido separan ventanas sin desplazar la transcripción. Los turnos ambiguos quedan sin etiqueta. Micrófono y sistema mantienen identificadores independientes.

## MLX opcional

En **Ajustes → Modelos → MLX · Qwen 1.5B**, el botón **Descargar modelos** prepara [Qwen2.5-1.5B-Instruct-4bit](https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit/tree/8b403126fc14f14cfc99bb4cfa72ecbc129ea677) junto a [Python portátil para Apple Silicon](https://github.com/astral-sh/python-build-standalone/releases/tag/20260127). Verifica los archivos antes de usar PyPI para instalar `mlx-lm` 0.31.3, MLX 0.32.4 y Transformers 5.22.2. El entorno queda aislado dentro de la carpeta del modelo. **Borrar modelos** retira esa carpeta y vuelve a seleccionar Apple para nuevas sesiones. Las carpetas y entornos externos elegidos manualmente se conservan.

El puente `mlx_summary.py` viene en el bundle Xcode. Ejecuta MLX mediante GPU Metal y CPU con contexto acotado, generación determinista y JSON validado. La inferencia usa archivos locales y el proceso se termina al cerrar cada resumen. La casilla de MLX se aplica a nuevas sesiones; las sesiones anteriores conservan su selección de motor.

Para desarrollo o para un modelo compatible propio, `LAI_PYTHON=/ruta/a/python3.11 ./script/prepare_mlx.sh` prepara el entorno manual y **Usar modelos propios** permite elegir las tres rutas. La aplicación requiere Internet al pulsar **Descargar modelos**, que consulta Hugging Face, GitHub y PyPI. Ninguna de esas solicitudes contiene audio ni texto de las sesiones.

## Google AI opcional · sin SDK externo

El backend Gemini usa directamente la API REST oficial con URLSession. El modo local no requiere claves. Gemini requiere una clave propia, Internet y cuota del proyecto de Google; su disponibilidad y facturación pertenecen a Google. El modelo inicial es `gemini-3.8-flash`, editable. La clave se conserva en el Llavero de macOS, no en este repositorio.

Se configura en Configuración → Google AI: habilitar el proveedor, guardar la clave en el Llavero, comprobar el modelo y seleccionar la sesión que puede enviar texto. Probar conexión consulta metadatos; Actualizar resumen procesa la transcripción. Para desactivarlo, desmarca la opción global; para retirar la credencial del Mac, usa Eliminar clave. Una actualización o un ZIP no transportan la clave de otro equipo.

Su objetivo es evitar la inferencia local del resumen cuando la RAM limita el motor local. La captura y la transcripción siguen necesitando recursos del Mac. El control actual de presión de memoria aplaza todos los proveedores, incluido Google; no hay cambio automático por saturación ni una garantía de ahorro medido. El modo local sigue disponible sin cuenta de Google.

Documentación oficial consultada el 21 de octubre de 2026: [modelos](https://ai.google.dev/gemini-api/docs/models), [claves](https://ai.google.dev/gemini-api/docs/api-key), [generateContent y responseFormat](https://ai.google.dev/api/generate-content), [salidas estructuradas](https://ai.google.dev/gemini-api/docs/structured-output). Se utiliza `generationConfig.responseFormat.text` con `mimeType: APPLICATION_JSON` y schema. No se integra ningún cliente de audio remoto ni servicio de traducción.

## Recursos visuales e idioma · 0.6.0

Sin nuevas dependencias externas: catálogo nativo `Resources/Localizable.xcstrings`, SwiftUI, AppKit y Core Graphics. `script/render_brand.swift` genera las fuentes SVG, PNG y portada; `script/rebuild_icon.sh` usa `sips` e `iconutil` de macOS. [Procedencia del sello y marca](BRAND.md). Ko-fi es un enlace que abre el navegador al pulsarlo; la app no descarga su badge.
