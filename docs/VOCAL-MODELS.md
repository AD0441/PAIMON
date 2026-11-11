# Modelos vocales y embeddings · PAIMON 0.13.0

En **Ajustes → Modelos → Emociones de voz**, descarga y selecciona un modelo. Puedes activar el análisis o borrar cada paquete desde el mismo lugar. Las descargas son explícitas. Solo se carga el elegido durante la solicitud; la aplicación no requiere Python, PyTorch ni una clave de API.

| Modelo | Descarga instalada aproximada | Salidas | Embeddings |
| --- | --- | --- | --- |
| emotion2vec+ Base | 94 MB | Nueve puntuaciones | La conversión existente no expone el vector |
| emotion2vec+ Large | 195 MB | Nueve puntuaciones | 1 × 1024 |
| Wav2Vec2 Base SUPERB ER | 122 MB | Cuatro puntuaciones | 1 × 256 |

Large no reemplaza Base. Los nombres indican las variantes de sus respectivos proyectos; no son una clasificación de precisión para reuniones en español.

## Procedencia e interfaz comprobada

- Base: [happyface-studio/emotion2vec-plus-base-coreml](https://huggingface.co/happyface-studio/emotion2vec-plus-base-coreml), revisión 704a2cac36227869e3296996f2c4d3a06fc68683. Su MLModelDescription expone probs y logits. El archivo MIL muestra un promedio interno de 768 componentes antes del clasificador, pero no es una salida pública del modelo compilado. PAIMON no intenta tratar probabilidades como embeddings ni modifica este paquete.
- Large: [emotion2vec/emotion2vec_plus_large](https://huggingface.co/emotion2vec/emotion2vec_plus_large), revisión 6c303ba987b86b93193de93e34bb2b077a6bedc4. Arquitectura original de FunASR 2b4a0623613013b2b59ae289b189768426006cfa; autores Ziyang Ma y colaboradores. Se omite el decodificador de preentrenamiento, ausente del checkpoint y ajeno a la ruta de inferencia. Todos los pesos restantes se cargan con validación estricta.
- SUPERB ER: [superb/wav2vec2-base-superb-er](https://huggingface.co/superb/wav2vec2-base-superb-er), revisión 441a7599c3b22107314dcbd9166621c5c83f2cc5. Autores SUPERB/S3PRL y Wav2Vec2 de Meta. Se conserva la suma ponderada de capas indicada por el checkpoint, la proyección, el promedio temporal y el clasificador.

Los dos paquetes nuevos reciben audio Float32 de forma 1 × N, mono a 16 kHz, de 8.000 a 48.000 muestras, sin relleno. Exponen logits, probs y embedding Float32 en una única inferencia. La normalización original está dentro del modelo. Large conserva el orden de nueve clases; SUPERB conserva neutral, happy, angry, sad. Las categorías indeterminadas y las salidas ambiguas no se fuerzan a una emoción.

La cuantización afecta a pesos lineales; las convoluciones conservan Float32. Cuantizar también estas últimas alteraba demasiado algunas respuestas de SUPERB y se descartó. Los modelos usan Core ML con CPU exclusivamente en esta versión. No se atribuye su ejecución al Neural Engine. Cada archivo descargado tiene tamaño y SHA-256 fijados en el código; la instalación se hace en una carpeta temporal y se reemplaza únicamente tras verificar el paquete. Se incluyen las licencias y la atribución originales. [Paquetes y manifiesto](https://github.com/AD0441/PAIMON/releases/tag/vocal-models-v1).

## Cómo explorar los embeddings

Activa **Explorar similitud vocal con embeddings** con Large o SUPERB ER. En **Sentimientos → Mixto**, analiza la pista y selecciona un intervalo.

La similitud coseno compara el vector con los demás intervalos analizados. Un valor de 1 significa vectores iguales; no es una probabilidad de emoción. La sección muestra hasta cinco coincidencias y permite ir a sus tiempos.

Los cambios usan distancia coseno 1 − similitud. El umbral se configura entre 0,05 y 1; es exploratorio y no está calibrado con reuniones reales. Cuando la diarización permite atribuir ambos intervalos, se diferencia un cambio de hablante de uno dentro del mismo hablante. Los silencios sin vector interrumpen la comparación. Un cambio también puede reflejar ruido o micrófono. No se estiman valencia ni activación.

El análisis conserva un máximo de 120 ventanas de hasta tres segundos. En sesiones largas se toman muestras separadas: los cambios se refieren a esas muestras, no a una observación continua. Los vectores son opcionales, quedan solo en memoria durante la vista y se liberan con ella. No se crea una base de embeddings ni se guardan grabaciones adicionales.

## Validación y límites

Se compararon seis entradas sintéticas por modelo: dos fragmentos hablados, voz baja, silencio, ruido y audio de medio segundo. Coincidió la primera categoría en los doce casos. La diferencia máxima entre las probabilidades originales y Core ML fue 0,020 de Large y 0,086 de SUPERB; este último extremo corresponde a silencio, que la app descarta antes de inferir. En los fragmentos hablados de tres segundos, las diferencias fueron como máximo 0,0049 y 0,021 respectivamente. Todos los vectores fueron finitos.

La similitud con el embedding de referencia superó 0,9996 en los dos fragmentos hablados de Large y en los de SUPERB. Estos ensayos comprueban la conversión con entradas concretas; no validan precisión emocional ni generalización a voces chilenas. SUPERB se entrenó con audio en inglés.

En un M1 de 8 GB, un pase separado sobre tres segundos de voz en CPU midió 1,59 s de inferencia y pico RSS de 700,5 MiB para Large, y 0,94 s y 425,9 MiB para SUPERB. Otra ejecución menos cargada midió 0,36 s y 0,21 s. Son observaciones puntuales con variación por carga y cachés, no una garantía de velocidad sostenida. El footprint físico y el RSS son métricas diferentes. [Medidas](evidence/vocal-EmotionLarge-metrics.txt) · [SUPERB](evidence/vocal-Wav2VecSuperb-metrics.txt) · [Comparación Large](evidence/vocal-large-validation.json) · [Comparación SUPERB](evidence/vocal-superb-validation.json).

## Conversión reproducible para desarrollo

Esta preparación corresponde al desarrollo de modelos; el usuario instala los paquetes desde la app. Usa Python 3.11 y GitHub CLI para obtener el código de arquitectura fijado.

~~~bash
python3.11 -m venv /tmp/paimon-conversion
/tmp/paimon-conversion/bin/pip install torch==2.7.0 coremltools==9.0 transformers==4.52.4 numpy==1.26.4 omegaconf==2.3.0 safetensors
/tmp/paimon-conversion/bin/python script/models/prepare_sources.py --output /tmp/paimon-models --model large
/tmp/paimon-conversion/bin/python script/models/convert_emotion_large.py /tmp/paimon-models
/tmp/paimon-conversion/bin/python script/models/prepare_sources.py --output /tmp/paimon-models --model superb
/tmp/paimon-conversion/bin/python script/models/convert_superb.py /tmp/paimon-models
PAIMON_TEST_EXTENDED_VOICE_MODELS=/tmp/paimon-models ./script/test.sh --filter additionalVocalModels
~~~

Los scripts comparan salidas con el modelo original y conservan el grafo del clasificador. Los binarios compilados pueden variar entre versiones de Core ML/Xcode; una nueva conversión exige regenerar los manifiestos antes de distribuirla.
