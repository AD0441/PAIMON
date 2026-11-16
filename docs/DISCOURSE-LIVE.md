# Discurso y voz durante la captura · PAIMON 0.15.2

## Uso

Antes de Iniciar puedes activar **Guardar audio**, **Vocal en vivo** y **Discurso automático** por separado. En **Ajustes → Modelos → Análisis durante la captura** elige los intervalos. Ninguna de estas dos funciones se activa automáticamente en instalaciones existentes.

**Discurso** usa solo la transcripción y Apple Foundation Models. En una sesión importada o terminada pulsa Analizar discurso; durante una captura, el modo automático procesa el texto nuevo cada cinco minutos por defecto. Las actualizaciones se marcan como provisionales. Tras detener se consolida el trabajo pendiente, después del resumen final y cuando hay recursos. La cola final queda en SQLite si la app se cierra antes de completarla. Un error conserva los resultados y el cursor; puedes volver a intentarlo con Analizar discurso.

## Las seis vistas

| Vista | Qué muestra | Alcance |
| --- | --- | --- |
| Mapa de temas | Tema, subtema, primer/último tiempo y referencias; clic para filtrar argumentos | Agrupa hallazgos, no cada mención literal |
| Mapa de argumentos | Propuestas, argumentos, objeciones y respuestas con vínculos y citas | No prueba la validez de un razonamiento |
| Evolución de posturas | Mantiene, modifica, acepta o descarta una propuesta | Requiere un cambio explícito y una propuesta identificada; silencio no significa abandono |
| Participación | Tiempo de habla, turnos y promedio, por hablante/fuente | Requiere Separar voces; los nombres los asigna el usuario |
| Recursos discursivos | Definiciones, analogías, ejemplos, generalizaciones, duda y certeza | Interpretaciones del texto, sin evaluación de la persona |
| Preguntas y respuestas | Preguntas y respuestas vinculadas | Una respuesta distante puede quedar fuera del contexto consultado |

Cada hallazgo conserva citas exactas y marcas temporales. Despliega una cita para ir a la transcripción; en importaciones puedes escuchar el original si sigue vinculado. Los cambios de postura se contrastan con expresiones explícitas en español/inglés; los condicionales, negaciones y estados contradictorios se omiten. Una cita literal no garantiza que toda la interpretación semántica sea correcta.

La participación une los solapes de una misma voz y fuente y agrupa intervalos separados hasta 0,25 s como un turno, sin sumar esa pausa al tiempo hablado. Los porcentajes son por fuente; las personas pueden hablar a la vez. Una identidad no se equipara automáticamente entre micrófono y sistema.

## Voz sin guardar la grabación

Vocal en vivo toma ventanas de **3 segundos a 16 kHz por fuente**, cada 30 segundos por defecto (15/30/60 configurables). En Sentimientos → Voz revisa el gráfico de intensidad y haz clic en una muestra para ver nivel dBFS, altura estimada, proporción de nivel bajo, sonidos y estimaciones vocales disponibles.

- Elige y activa un modelo ya instalado en Ajustes → Modelos → Emociones de voz. Sin ese modelo siguen disponibles las mediciones y Sound Analysis con las categorías seleccionadas.
- Los modelos Core ML se ejecutan en CPU, elegida por mediciones previas del M1; no se afirma ejecución en el Neural Engine.
- Con embeddings activos, Large o SUPERB comparan la muestra con la anterior de la misma fuente. Solo se conserva la distancia y el último vector en memoria. Base no expone embeddings en la conversión instalada.
- Sonidos requiere las categorías seleccionadas del catálogo de Apple; se conservan puntuaciones a partir de 0,65 y se fusionan ventanas contiguas del mismo sonido dentro de la muestra.
- Intensidad, altura y nivel bajo describen señal; las etiquetas emocionales son estimaciones experimentales, sin diagnóstico psicológico.

**Guardar audio** es independiente. Apagado: se descartan las muestras PCM y se guardan solo resultados derivados. Encendido: se guarda el audio por fuente en disco y se puede realizar el análisis completo al finalizar. El muestreo en vivo no rellena automáticamente el gráfico Mixto del análisis completo. Para escuchar o repetir un análisis después necesitas audio conservado o el original de una importación.

## Rendimiento y privacidad

La cola vocal está acotada y es independiente de la transcripción. Si la compuerta de inferencia está ocupada se omite esa inferencia sin añadir trabajo atrasado. Con Parakeet activo se difieren los modelos vocales y Discurso para priorizar reconocimiento; se conservan métricas de señal si hay recursos. Con presión de memoria, pausa o calor se suspenden tareas opcionales. Al detener se descarta la ventana incompleta o aún en proceso.

Discurso procesa hasta cuatro unidades de texto por lote y solicita hasta cuatro hallazgos breves. Si la respuesta queda incompleta, permite un solo reintento con la mitad de las fuentes y un máximo de dos hallazgos; el resto del texto sigue pendiente. Recupera hasta doce hallazgos anteriores relevantes, con control de contextSize y conteo de tokens en macOS 26.4+. Guarda el avance transaccionalmente y no repite toda la transcripción. Corregir el texto o cambiar el contexto invalida los resultados anteriores; deben actualizarse antes de exportar.

Exportar → **Discurso y participación** añade sus resultados a TXT, Markdown, PDF o JSON. Las tablas derivadas se eliminan junto con la sesión mediante claves foráneas y el mecanismo de limpieza de SQLite existente. Los originales externos y exportaciones que tú guardaste se administran aparte.

## Verificación reproducible

~~~bash
./script/test.sh
PAIMON_TEST_DISCOURSE=1 ./script/test.sh --filter discourseNativeModelProcessesProposalsAndKeepsItsCheckpoint
PAIMON_TEST_LIVE_VOCAL=1 ./script/test.sh --filter liveVocalNativeSoundStreamAndSelectedCoreMLModelProcessActualBuffers
~~~

La prueba vocal usa Tests/Fixtures/spanish-synthetic.aiff y los recursos ya instalados. La prueba nativa de discurso necesita Apple Intelligence disponible. No descargan modelos ni utilizan conversaciones del usuario. Consulta los resultados ejecutados y las limitaciones en [VALIDATION.md](VALIDATION.md) y [LIMITATIONS.md](LIMITATIONS.md).

Referencias oficiales: [Generación estructurada](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation), [Sonidos desde PCM en flujo](https://developer.apple.com/documentation/soundanalysis/classifying-sounds-in-an-audio-stream).

## Recuperación de respuestas incompletas · 0.15.2

Cada lote válido se confirma en SQLite antes de continuar. La RAM conserva una ventana pequeña y el modelo recibe fuentes nuevas y contexto relevante, sin cargar siempre toda la transcripción. El límite de respuesta sigue siendo de 900 tokens; se redujeron la cantidad de elementos y la extensión solicitada para disminuir el riesgo de resultados incompletos. Se comprueba el presupuesto de contexto también en el reintento.

Si ambos intentos fallan, aparece una explicación y el cursor permanece en el último bloque válido. Pulsa **Analizar discurso** para continuar. Los fragmentos divididos solo avanzan el cursor al confirmar su última parte. Los resultados de la misma versión se actualizan sin duplicar las citas.

**Análisis parcial guardado** significa que existe avance confirmado en una sesión terminada, pero no un análisis completo. Durante una captura sigue apareciendo **Análisis provisional**. El aviso de interpretaciones omitidas describe elementos sin citas verificables, no una pérdida de toda la transcripción ni un fallo de memoria.

La compactación adicional mediante otra llamada al modelo sigue siendo una opción por evaluar. Esta versión mantiene los hallazgos completos en SQLite y acota/selecciona el contexto; no sustituye los originales por una condensación que pueda perder vínculos o citas.

~~~bash
PAIMON_TEST_DISCOURSE=1 ./script/test.sh --filter discourseNativeDenseSourcesKeepGroundedResultsAndCompleteCheckpoint
~~~

[Opciones oficiales de generación y límites de respuesta](https://developer.apple.com/documentation/foundationmodels/generationoptions).
