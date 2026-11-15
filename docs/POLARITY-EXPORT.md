# Polaridad, exportaciones y memoria · PAIMON 0.15.0

## Qué pasaba con −1

El código no rellenaba puntuaciones ausentes con −1, ni el gráfico desplazaba el eje. `NLTagger.sentimentScore` devolvió valores negativos para frases informativas en este Mac. En la muestra sintética, «La reunión empieza a las diez.» y «La propuesta tiene tres etapas.» recibieron −0,8; sus equivalentes ingleses recibieron −0,6. Esto muestra una limitación observada en esta muestra, no una medición general de precisión del framework.

Apple define el intervalo −1…+1 y el 0 como neutralidad, pero ese contrato no garantiza que cada clasificación sea correcta. [Documentación de sentimentScore](https://developer.apple.com/documentation/naturallanguage/nltagscheme/sentimentscore).

## Cómo se interpreta ahora

Apple Foundation Models revisa hasta **48 muestras distribuidas** de la transcripción, en lotes de hasta tres fragmentos. Una misma generación devuelve polaridad, emociones expresadas y contexto. Las muestras conservan el tiempo de su fragmento original; no se inventan tiempos dentro de un segmento largo.

| Clase | Índice | Significado |
| --- | --- | --- |
| Neutra | 0 | Lenguaje informativo sin valoración; incluye fechas, cifras y decisiones comunicadas como hechos |
| Positiva | +1/3, +2/3 o +1 | Valoración positiva de intensidad ordinal leve, marcada o intensa |
| Negativa | −1/3, −2/3 o −1 | Valoración negativa con la misma escala ordinal |
| Mixta | Sin índice | Valoraciones positivas y negativas sin inventar un balance |
| Sin conclusión / no analizada / error | Sin índice | Falta una clasificación respaldada; no se reemplaza por 0 ni −1 |

La intensidad **no es una probabilidad**, confianza calibrada ni diagnóstico de una persona. Un hecho desfavorable o un acuerdo no implican por sí mismos un tono negativo o positivo. Las valoraciones y emociones necesitan una cita literal del fragmento suministrado. La cita permite revisarlas, pero no garantiza toda interpretación semántica.

El valor original de NaturalLanguage se conserva como `rawAppleScore`, separado del índice revisado. Los resultados anteriores de versión 1 siguen exportándose con su motor y versión; para la gráfica revisada hay que pulsar **Actualizar análisis / Volver a analizar**. Tras recalcular, el nuevo registro reemplaza la caché anterior. Editar el texto o renombrar voces invalida y elimina esa caché, que debe calcularse de nuevo. La transcripción original se conserva aparte.

Apple Intelligence debe estar disponible. Si no lo está o hay un fallo, se conservan los valores originales para auditoría sin fingir una revisión local. Tras tres lotes fallidos consecutivos se detiene ese intento y se guarda un estado parcial; no se encadenan solicitudes inútiles por toda la sesión.

## Exportación por selección

**Exportar sesión** permite elegir transcripción, notas, secciones del resumen y estas opciones independientes:

- **Sentimientos y datos vocales:** puntos del texto, índice revisado y valor original, clase, intensidad, citas, etiquetas y tiempos; últimos análisis vocales calculados por fuente, sonidos seleccionados y muestras de captura conservadas.
- **Discurso y participación:** temas, argumentos, evolución explícita, recursos y participación con sus referencias.
- **Asistente:** todas las consultas y respuestas guardadas, incluidas abstenciones, citas, fecha y revisión de la transcripción utilizada.

TXT, Markdown y PDF presentan esos datos como un informe. **JSON, esquema 2**, conserva estructuras numéricas, unidades y categorías, con fechas ISO 8601. Un índice ausente se codifica como `null`. Los modelos vocales incluyen su identificador; se guardan distancias entre embeddings, **sin persistir ni exportar los vectores completos**. Los resultados de voz son experimentales.

Exportar **no vuelve a ejecutar modelos**. Si un análisis no se calculó, el informe lo indica. La exportación se escribe por páginas y comprueba cambios de transcripción, historial y análisis antes de reemplazar el archivo de destino. Los datos antiguos de sentimiento conservan su identificación; no se reescriben artificialmente como neutrales.

## Historial del Asistente

Las nuevas consultas se guardan en SQLite junto con la sesión. La vista mantiene solo las últimas doce en memoria; la exportación recorre todo el historial. Cada respuesta se guarda solo si su revisión y sus citas siguen coincidiendo con el texto. Las respuestas previas a una corrección permanecen identificadas como históricas y no se reutilizan como contexto actual.

**Las consultas de 0.14 y versiones anteriores que solo existían en memoria no son recuperables después de cerrar la app.** Conviene copiarlas antes de reiniciar para actualizar. Borrar una sesión elimina también sus consultas, análisis de texto y registros vocales. Los archivos originales y exportaciones externas siguen bajo el control del usuario.

## Memoria: qué se puede cambiar

Los niveles normal, advertencia y crítico son avisos del sistema; la API no ofrece un número de GB para elevar ese umbral. [Eventos oficiales de presión de memoria](https://developer.apple.com/documentation/dispatch/dispatchsource/memorypressureevent).

PAIMON ahora distingue advertencia de presión crítica, pero **no ignora ninguna de las dos** para forzar inferencias. Con M1 y 8 GB no hay mediciones de carga prolongada que justifiquen relajar esa protección: la memoria de servicios de IA, GPU, compresor y otras apps también cuenta, aunque no aparezca toda en la huella del proceso de PAIMON.

En **Ajustes → Audio y memoria → Rendimiento** se elige la espera después de que macOS vuelva a normal: **5, 15 o 30 segundos**, con 15 predeterminado. Los avisos repetidos amplían la espera hasta dos minutos. El cambio afecta los próximos ciclos de recuperación; no cambia el umbral del sistema. Las tareas opcionales respetan ese período para evitar recargar y cancelar modelos repetidamente. La captura conserva la prioridad.

## Limpieza y optimización realizadas

| Componente | Cambio |
| --- | --- |
| Transcripción sentimental | Un clasificador NaturalLanguage por tarea, con llamadas serializadas, recursos temporales liberados antes de la generación; no un objeto por fragmento |
| Inferencia textual | Un lote combina polaridad, emociones y contexto. En 48 fragmentos cortos son 16 solicitudes; los largos pueden formar lotes menores. No se prometen ahorros equivalentes de tiempo o RAM |
| Fallos de generación | Corte tras tres lotes fallidos, sin valores inventados ni repetición de todos los fragmentos |
| Memoria | Una única fuente de estado tipada, advertencia/crítica diferenciadas y recuperación coherente para tareas opcionales |
| Asistente | Historial duradero, lectura de las últimas doce y exportación paginada |
| Datos vocales | Actualización por fuente; reemplazar audio vinculado invalida sus resultados en una transacción |
| Discurso | Se consulta solo la sección visible: dos consultas menos por recarga de la vista principal; los vínculos abiertos se refrescan con la revisión y se limpia un destino retirado |
| Exportación | Evita indexar/recorrer el resumen si no se seleccionó; encabezados sin avisos de resumen ajenos a la selección, Markdown escapado y control de cambios durante la escritura |
| Interfaz | Exportación con contenido desplazable y botones fijos; aviso claro para análisis antiguos que requieren actualización |

No se ha efectuado una refactorización masiva de captura o almacenamiento. Las mediciones, los ensayos reproducibles y sus límites se detallan en [VALIDATION.md](VALIDATION.md).
