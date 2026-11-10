# PAIMON — Requisitos y estado del producto

- **Versión del documento:** 1.2 · **Fecha:** 10 de noviembre de 2026.
- **Base revisada:** PAIMON 0.9.0 (24).
- **Producto:** PAIMON · Local Audio Intelligence · Transformando sonido en conocimiento.
- **Autor:** Sebastián Pastén F.

Este documento consolida lo solicitado, lo mejorado y el trabajo pendiente. Sigue la organización por códigos, prioridades y aceptación de NABERIUS, adaptada al estado real de PAIMON. La versión publicada sigue siendo **preliminar**: una función implementada o una batería aprobada no certifican por sí solas una reunión de varias horas.

## 1. Cómo usar esta lista

- **P0:** necesario para cerrar una versión estable del funcionamiento principal. **P1:** siguiente mejora de calidad o capacidad. **P2:** evolución opcional.
- **V — Verificado:** existe evidencia para el alcance indicado; no implica verificación en todos los equipos, versiones ni situaciones.
- **I — Implementado:** existe código funcional; falta la comprobación indicada en la versión actual.
- **P — Parcial:** hay una solución, pero no cubre todo el requisito original.
- **N — Pendiente:** falta implementar o ejecutar la validación correspondiente.
- Los códigos son estables. Al modificar una función, actualizar su estado, criterio y evidencia, sin borrar resultados históricos ni presentar pruebas anteriores como nuevas.
- Cada evidencia conserva su versión y entorno. La compilación 24 incluye 111 pruebas y una revisión aislada de Asistente y Sentimientos con audio sintético. [Validación por versión](VALIDATION.md).
- Esta lista no ordena implementar todos los pendientes ahora. Las propuestas nuevas se distinguen de los acuerdos del producto.

## 2. Decisiones confirmadas

| Código | Decisión |
| --- | --- |
| D-01 | App nativa macOS, Swift/SwiftUI, servicios desacoplados y protocolos intercambiables. Conservar la arquitectura actual. |
| D-02 | Prioridad Apple M1 con 8 GB; deployment macOS 26.0+, arm64. No prometer ejecución íntegra en ANE. |
| D-03 | Captura, reconocimiento y resumen locales por defecto; sin cuenta, suscripción, clave obligatoria ni telemetría. |
| D-04 | Google AI es una excepción posteriormente autorizada: resumen externo voluntario con clave propia, consentimiento global y por sesión, sin enviar audio. Sustituye el requisito inicial de ausencia absoluta de servicios remotos únicamente para ese modo. |
| D-05 | Conservar la transcripción original independientemente del resumen; guardar audio solo por activación expresa. |
| D-06 | La barra de menús es prioritaria. Cerrar la ventana no debe interrumpir la captura. |
| D-07 | Resúmenes incrementales y acumulativos; intervalo inicial de cinco minutos, configurable, y síntesis al detener. |
| D-08 | Informe copiable con títulos en negrita, secciones claras y evidencia mediante iconos al final de los puntos. Mantener formato en las salidas que lo admiten. |
| D-09 | Identidad geométrica de Paimon en la familia visual de METATRON; cuatro paletas, interfaz español/inglés y pie «Creado por Sebastián Pastén F.». |
| D-10 | Mantener únicamente las versiones local actual y anterior, junto con código, Git y evidencias necesarias. Ko-fi es voluntario y abre solo por acción del usuario. |

## 3. Objetivo y límites

El recorrido principal es reproducir una reunión, clase, video o podcast en el Mac, pulsar **Iniciar**, leer texto real con tiempos y obtener un informe actualizado sin bloquear la captura. El usuario puede revisar cada afirmación contra su fuente y exportar su sesión.

No se consideran funciones actuales: cancelación acústica completa, transcripción garantizada de contenido protegido, extracción de pistas de video/URLs, sincronización en nube ni colaboración. No se incorporan como bloqueos de la primera versión estable salvo que se acuerde ampliar el alcance.

## 4. Plataforma, arquitectura y privacidad

| Código | Prioridad | Requisito y criterio de aceptación | Estado / alcance actual |
| --- | --- | --- | --- |
| BAS-01 | P0 | Compilar una app arm64 para macOS 26.0+ y abrirla sin Xcode. | **V:** Release 0.7.0 arm64 con firma ad hoc. Ejecución en M1 de 8 GB y macOS 27.3. Validación en macOS 26 pendiente. |
| BAS-02 | P0 | MVVM, actores, async/await y protocolos de captura, transcripción y resumen; ningún cambio de motor exige rehacer la interfaz. | **V:** servicios existentes y dobles inyectables en pruebas de AppModel. [E1, E2] |
| PRV-01 | P0 | Con Google desactivado y recursos preparados, capturar, transcribir y resumir sin Internet. Nunca activar red como recuperación automática. | **I:** rutas locales implementadas; falta ensayo completo sin conexión con la firma actual. [E1, E3] |
| PRV-02 | P0 | No guardar audio por defecto; conservar texto y resúmenes localmente. Audio opcional por fuente, escrito a disco. | **I:** preferencias y persistencia cubiertas; la captura histórica no guardó audio. Falta comprobar grabación opcional y sus índices con ambas fuentes en build 13. [E1, E2] |
| PRV-03 | P0 | Pedir permisos reales de sistema/micrófono, con descripciones de uso, estado visible y errores comprensibles. | **I:** permisos implementados; falta repetir denegación, revocación y renovación con build 13. [E1, E3] |
| PRV-04 | P0 | Sin telemetría ni carga de recursos remotos al iniciar; claves fuera de Git, SQLite, preferencias y exportaciones. | **V:** revisión de rutas y pruebas del cliente/credenciales. El enlace Ko-fi requiere pulsación. No es una auditoría independiente de tráfico. [E1, E2] |

## 5. Captura real de audio

| Código | Prioridad | Requisito y criterio de aceptación | Estado / alcance actual |
| --- | --- | --- | --- |
| AUD-01 | P0 | Capturar audio reproducido con Core Audio Process Taps, sin driver virtual y sin silenciar la reproducción. | **I:** tap privado `.unmuted` verificado con muestra sintética en Release aislada y macOS 27.3. Falta repetir con el binario distribuido. [E1, E2] |
| AUD-02 | P0 | Elegir todo el sistema o una aplicación compatible y la salida capturada; mantener actualizada la lista de apps. | **I:** fuente específica y global comprobadas en Release aislada. En global se detuvo cerca del final y quedó una palabra pendiente en la transcripción. Faltan repetición con margen, cambio de salida y matriz de reproductores. |
| AUD-03 | P0 | Micrófono opcional mediante AVAudioEngine y selección del dispositivo de entrada. | **I:** captura implementada; comprobación física y permisos de build 13 pendientes. |
| AUD-04 | P0 | Sistema y micrófono simultáneos conservan fuente y reloj común; las pausas mantienen sus huecos. | **I:** fuentes separadas y sincronización implementadas; falta prueba acústica actual con ambas entradas. [E1, E3] |
| AUD-05 | P0 | Iniciar, pausar, reanudar y detener liberan tap, agregado, IOProc, engine y tareas; el resumen final espera los últimos textos. | **I:** inicio, pausa, reanudación y detención comprobados en la ventana de Release aislada, con marcas válidas y síntesis final. Falta repetir con la firma del binario distribuido. |
| AUD-06 | P0 | Indicador permanente de captura y actividad por fuente, también con la ventana cerrada. | **I:** indicador y MenuBarExtra presentes. El ensayo manual asistido de Release aislada guardó texto completo y síntesis. Falta comprobar de forma directa la pausa y reanudación desde la barra. |
| AUD-07 | P0 | Anillos preasignados y colas acotadas; callbacks sin disco, inferencia ni tareas Swift. Conversión PCM continua sin solapamientos artificiales. | **V:** anillo C, conversión/downmix/continuidad y desbordamiento cubiertos por pruebas. Esto no prueba cero pérdidas bajo cualquier carga. [E1, E2] |
| AUD-08 | P0 | Detectar silencios y evitar bucles o doble contenido entre fuentes. | **P:** VAD energético con histéresis, sin monitorización del micrófono y detección conservadora de texto idéntico solapado. No hay VAD neuronal ni cancelador acústico; usar audífonos. |
| AUD-09 | P1 | Detectar desconexiones/cambios de dispositivo y recuperar o indicar cómo reiniciar, conservando texto confirmado. | **P:** errores visibles; no se garantiza reconfiguración automática. Falta ensayo reproducible de cambios físicos. [E3] |

## 6. Reconocimiento de voz

| Código | Prioridad | Requisito y criterio de aceptación | Estado / alcance actual |
| --- | --- | --- | --- |
| ASR-01 | P0 | Priorizar SpeechAnalyzer/SpeechTranscriber y consultar motor, locale, recursos y formato mediante APIs oficiales. Descargas solo explícitas. | **V:** `isAvailable`, `supportedLocale`, `installedLocales`, AssetInventory y mejor formato; importación española real registrada. [E2, E4] |
| ASR-02 | P0 | Español prioritario e inglés; distinguir selección de motor de detección automática de idioma. | **P:** español predeterminado e inglés seleccionable; Apple usa un locale elegido. «Automático» selecciona motor, no alterna idiomas. Parakeet multilingüe aún no validado con pesos. |
| ASR-03 | P0 | Producir parciales cuando el motor los ofrezca y definitivos con tiempos y fuente, persistiendo solo definitivos. | **V:** Apple real y pruebas de persistencia/tiempos; falta repetir inglés y conversación prolongada. [E2, E3] |
| ASR-04 | P0 | Consolidar sin repeticiones, conservar interrupciones y paginar sesiones extensas sin mantener PCM completo en RAM. | **V:** deduplicación, conversión y cargas sintéticas cubiertas; ensayo de varias horas con audio real pendiente. |
| ASR-05 | P1 | FluidAudio/Parakeet multilingüe local intercambiable desde Configuración; identificar backend real y consumo. | **P:** worker y protocolo implementados, wrapper compilado y ausencia de modelos diagnosticada. Faltan pesos, transcripción real y perfil Core ML. [E4] |
| ASR-06 | P0 | Preparación cancelable y estado de error recuperable ante fallos del servicio de voz. | **P:** cancelación y caché de metadatos de 60 s; se observó una espera nativa y posteriores importaciones pasaron. Falta probar bloqueo sostenido; no hay garantía de plazo máximo. |
| ASR-07 | P0 | Importar audio local compatible con AVAudioFile por bloques; no guardar otra copia del audio ni capturar a la vez. | **V:** importación española real, búfer de 4.096 frames y contrapresión; cancelación conserva definitivos. No reanuda exactamente un archivo cancelado. [E2] |

## 7. Resumen e inteligencia

| Código | Prioridad | Requisito y criterio de aceptación | Estado / alcance actual |
| --- | --- | --- | --- |
| RES-01 | P0 | Consultar disponibilidad de SystemLanguageModel, soporte del idioma y motivos de indisponibilidad, incluidos Apple Intelligence y recursos. | **V:** ruta Foundation Models real y estados del framework; no se presenta como disponible si el sistema lo niega. [E2, E4] |
| RES-02 | P0 | Generar tema, resumen general, ideas, acuerdos, tareas, conceptos, preguntas y conclusiones cuando haya contenido que los respalde. | **V:** modelo estructurado e informe compartido; no se exige inventar secciones vacías. Seis hallazgos y tres temas en la muestra real de 0.6.0. |
| RES-03 | P0 | Nunca inventar nombres, fechas, responsables ni acuerdos. Cada hallazgo debe conservar citas y tiempos originales. | **P:** se rechazan IDs/citas inexistentes y campos sin respaldo literal; guardas léxicas para acuerdos/relevancia. Una cita válida no demuestra interpretación correcta; puede haber omisiones. Revisión humana necesaria. |
| RES-04 | P0 | Exigir síntesis general antes de marcar final la ruta Apple; no aceptar solo un título como resumen terminado. | **V:** procesamiento Apple v4, regresiones del fallo reportado y síntesis real. No atribuir esta misma cobertura al worker MLX. [E2, E5] |
| RES-05 | P0 | Resumir contenido nuevo cada cinco minutos por defecto; permitir 1, 3, 5 o 10 minutos. Evitar inferencia sin texto nuevo. | **V:** planificación incremental; puede adelantarse con 6.000 bytes nuevos tras un minuto. No promete cadencia exacta cuando faltan recursos. |
| RES-06 | P0 | Memoria jerárquica, contexto acotado y registro duradero; no reenviar siempre toda la transcripción. | **V:** cursores, condensación, hechos persistidos y paginación. Memoria narrativa hasta 80 elementos; no significa que la síntesis breve contenga todos los detalles. [E1, E2] |
| RES-07 | P0 | Al detener, terminar reconocimiento, conservar el trabajo final y recuperar aplazamientos tras reinicio o presión de memoria. | **V:** transcripción disponible antes de finalizar la síntesis. Cola persistente tras detener o pulsar Actualizar en una sesión cerrada. Recuperación automática con espera de 15 a 120 s al normalizarse la memoria. Regresiones de interrupción y persistencia. Importación y síntesis reales verificadas en la instancia aislada. [E2] |
| RES-08 | P0 | Gestionar ventana de contexto oficial, JSON incompleto, errores y reintentos acotados sin perder el resumen anterior ni avanzar un cursor fallido. | **V:** `contextSize`, conteo de tokens cuando está disponible y estimación conservadora en macOS 26.0–26.3; reducción de lotes y regresiones. [E2, E4] |
| RES-09 | P0 | Rehacer desde el original tras cambio de motor, contexto, plantilla o versión de procesamiento; una respuesta tardía no modifica otra sesión. | **V:** identidad de configuración y tokens de selección; pruebas AppModel de éxito, fallo e indisponibilidad tardíos. |
| RES-10 | P1 | MLX local cuantizado de aproximadamente 1,5–1,7B como alternativa opcional, sin instalación automática ni modelos pesados simultáneos innecesarios. | **P:** script, worker y ruta offline presentes; no ejecutado con pesos. Falta igualar esquema/validación a Apple v4 y medir carga, latencia y memoria. [E3, E4] |
| RES-11 | P1 | Revisar compromisos o preguntas cuando intervenciones posteriores los cambien o resuelvan, sin borrar su evidencia histórica. | **P:** acumulación y deduplicación existentes; falta conciliación semántica completa de estados. La síntesis recibe un contexto acotado. |
| RES-12 | P1 | Hacer preguntas sobre la sesión seleccionada en una tercera pestaña, con IA local y citas que abren la transcripción. | **V:** dos respuestas y navegación verificadas en la app aislada. Las pruebas cubren búsqueda acotada, separación entre sesiones y abstención ante un dato ausente. Requiere Apple Intelligence. [E2] |

## 8. Google AI externo y voluntario

| Código | Prioridad | Requisito y criterio de aceptación | Estado / alcance actual |
| --- | --- | --- | --- |
| GOO-01 | P0 | Desactivado por defecto, habilitación global y por sesión; nunca seleccionar nube automáticamente por falta de RAM. | **V:** pruebas de consentimiento y compatibilidad de sesiones anteriores. Captura y voz permanecen locales. |
| GOO-02 | P0 | Clave propia en Llavero, modelo configurable, borrado de clave y prueba de conexión sin transcripción. | **V:** implementación y contratos con claves sintéticas; la revisión actual no usó una clave real. |
| GOO-03 | P0 | Enviar solo texto, contexto y resúmenes necesarios al endpoint HTTPS fijo; nunca audio; cancelar al desactivar o revocar. | **V:** cliente efímero, redirecciones rechazadas, límites de solicitud/respuesta y cancelación cubiertos. [E1, E2] |
| GOO-04 | P0 | Manejar HTTP 503 y otros fallos temporales sin perder texto; reintentos limitados y respeto de Retry-After. | **V:** hasta dos reintentos para 500/502/503/504, sin repetir errores de clave/cuota ni resultado de red incierto; transporte controlado en pruebas. Finalización remota observada históricamente, no repetida en 0.6.0. |
| GOO-05 | P0 | Explicar Internet, cuota/facturación y alcance real frente a RAM; no prometer ahorro medido. | **V:** README y opciones describen el modo. **Todos los proveedores se aplazan bajo presión de memoria**, incluido Google; no es un mecanismo de liberación de RAM. |

## 9. Sesiones, datos y herramientas

| Código | Prioridad | Requisito y criterio de aceptación | Estado / alcance actual |
| --- | --- | --- | --- |
| DAT-01 | P0 | SQLite incremental con WAL, transcripción independiente, resúmenes versionados y recuperación de sesiones interrumpidas. | **V:** reapertura, compatibilidad, migraciones y persistencia cubiertas. Una caída solo recupera definitivos confirmados. [E1, E2] |
| DAT-02 | P0 | Historial con nombre, fecha y duración; renombrar, buscar y abrir sesiones sin cargar todo el historial. | **V:** páginas de 50 sesiones y revisión aislada de renombrado/búsqueda. |
| DAT-03 | P0 | Borrar una sesión elimina texto, resúmenes, hallazgos, marcadores, trabajos, índice y audio asociado. | **V:** prueba con dos sesiones, vínculos, búsqueda, métricas y grabaciones por fuente. WAL se trunca y la base se compacta al borrar la última sesión. Los originales y las exportaciones son archivos independientes. |
| HER-01 | P0 | Buscar palabras en la sesión y el historial, con acentos/mayúsculas tolerados y salto al fragmento; cancelar consultas obsoletas. | **V:** FTS5, máximo 50 resultados globales y búsqueda agrupada; la primera indexación puede quedar parcial mientras se captura. |
| HER-02 | P1 | Marcadores y notas persistentes con tiempos, edición y exportación; no usar notas como evidencia de la transcripción. | **V:** pruebas y recorrido histórico; búsqueda/cambio de sesión conservan marcadores. |
| HER-03 | P1 | Contexto de objetivo, temario y glosario separado de las fuentes; plantillas Reunión, Clase y Video/podcast. | **V:** editor en sheet, límites de caracteres, identidad y reconstrucción. El contexto orienta, no demuestra hechos. |
| HER-04 | P1 | Vistas Ejecutiva/Completa, progreso de texto/resumen y términos frecuentes sin inferencias adicionales. | **V:** usan hallazgos guardados y muestra de hasta 300 fragmentos/100.000 caracteres; no son un índice semántico de toda la sesión. |
| HER-05 | P0 | Seleccionar y copiar texto reconocido o un fragmento completo, con su hora desde el menú contextual. | **I:** selección nativa y copia implementadas en TranscriptView; falta recorrido completo de selección/copia por teclado y VoiceOver. |
| HER-06 | P1 | Vincular un archivo de audio importado y escuchar el intervalo exacto desde el fragmento o su cita en el informe. | **V:** reproducción comprobada en Debug aislado. SQLite guarda la referencia local. Se necesita conservar el archivo original. |
| HER-07 | P1 | Corregir un fragmento final, conservar y restaurar el texto reconocido, y regenerar el resumen cuando haya cambios. | **V:** corrección y regeneración con Foundation Models en Debug aislado. Pruebas de búsqueda, exportación y restauración. |

## 10. Informe, copia y exportación

| Código | Prioridad | Requisito y criterio de aceptación | Estado / alcance actual |
| --- | --- | --- | --- |
| EXP-01 | P0 | Informe con título/metadatos, resumen general, puntos clave, acuerdos, compromisos, preguntas y conclusiones; encabezados y conceptos en negrita. | **V:** formateador compartido y pruebas; secciones sin contenido omitidas, campos ausentes «No especificado». |
| EXP-02 | P0 | Copiar informe con texto plano y formatos enriquecidos compatibles con Word/Pages, manteniendo negritas y tabla de tareas. | **V:** salida TXT/HTML/RTF y pruebas de ida/vuelta; portapapeles se construye solo a petición. |
| EXP-03 | P0 | Icono de evidencia al final del punto, popover con todas las citas y navegación al original; anexo de evidencias opcional. | **V:** salto comprobado en Review y pruebas de varias fuentes/enlaces. La transcripción paginada carga el destino solicitado. |
| EXP-04 | P0 | Exportar TXT, Markdown, PDF y JSON con selección de contenidos, citas y notas; conservar formato donde el formato lo permita. | **V:** pruebas de paginación, acentos, PDF, tablas y referencias. TXT es plano; no debe prometer negritas. Archivos únicamente en la ubicación elegida. |

## 11. Interfaz y familia visual

| Código | Prioridad | Requisito y criterio de aceptación | Estado / alcance actual |
| --- | --- | --- | --- |
| UI-01 | P0 | Ventana con título único, fuente, estado, duración, controles y paneles de texto/resumen; no quedar vacía ni desplazar cabecera/pie fuera de pantalla. | **V:** límites explícitos de NavigationSplitView y revisión aislada a 1240×800 y aprox. 1000×702 puntos; conservar la corrección de geometría. |
| UI-02 | P0 | Divisor ajustable, seguimiento automático opcional y contexto que abre/cierra sin deformar el diseño. | **V:** proporción en SceneStorage, sheet y navegación a evidencia comprobadas; búsqueda no recarga resumen ni notas. |
| UI-03 | P0 | Control real desde barra de menús: iniciar, pausar/reanudar, detener/resumir, marcar y abrir ventana. | **I:** MenuBarExtra y comandos implementados; comprobar captura con ventana cerrada en build 13. |
| UI-04 | P1 | Icono geométrico simple reconocible a tamaños pequeños; SVG/PNG/ICNS reproducibles, coherentes con METATRON. | **V:** marca de 0.6.0, recursos y capturas públicas sintéticas; interpretación geométrica, no facsímil del sello histórico. [E6] |
| UI-05 | P1 | Pie inferior izquierdo con marca, «Audio en tu Mac», Ajustes y autor; Ko-fi discreto en opciones. | **V:** revisión aislada, enlace verificado y sin carga remota al iniciar. |
| UI-06 | P1 | Petróleo, Salvia, Cobre y Grafito, modo claro/oscuro e interfaz español/inglés independiente del idioma de voz. | **V:** persistencia, compatibilidad y catálogo; no traduce transcripciones/informes. Mensajes del sistema pueden conservar su idioma. |
| UI-07 | P0 | Teclado, foco, VoiceOver y contraste suficientes para controles esenciales; no depender solo del color. | **P:** controles nativos, etiquetas y divisor accesible presentes; falta auditoría completa de teclado/VoiceOver/contraste. No declarar accesibilidad certificada. |

## 12. Rendimiento y mantenimiento

| Código | Prioridad | Requisito y criterio de aceptación | Estado / alcance actual |
| --- | --- | --- | --- |
| RND-01 | P0 | PCM acotado, paginación, carga diferida y una inferencia pesada a la vez; generación fuera de UI/callbacks. | **V:** límites y compuerta existentes con cancelación; Apple administra sus propios modelos. No equivale a limitar toda la memoria del sistema. [E1, E2] |
| RND-02 | P0 | Presión de memoria/estado térmico reducen trabajo; finales pendientes recuperables y métricas locales sin texto privado. | **V:** mecanismos y regresiones existentes; falta presión sostenida real con versión actual. |
| RND-03 | P0 | Medir CPU, memoria total relevante, latencia, pérdidas y respuesta de UI durante una reunión real prolongada en M1/8 GB. | **N:** importaciones de 35:37 y de cargas repetidas de 1:02:07 y 2:04:15 verificadas. Faltan captura en vivo prolongada y consumo global de modelos. [E7] |
| RND-04 | P1 | Identificar CPU/GPU/ANE de los modelos opcionales mediante perfil, sin inferirlo del nombre Core ML. | **N:** configuraciones documentadas, perfil con pesos pendiente. Speech/Foundation Models no garantizan públicamente acelerador por operación. |
| RND-05 | P1 | Evitar trabajo recurrente innecesario: búsquedas cancelables, indicadores agrupados y lista de apps por notificaciones. | **V:** mejoras 0.6.0; métricas cada 5 s con ventana abierta, sin afirmar consumo cero en reposo. |
| ENT-01 | P0 | Proyecto Xcode compilable, scripts, dependencias documentadas, pruebas reproducibles y resultados con versión/entorno. | **V:** 111 pruebas registradas en 0.9.0 y muestra sintética local. Los scripts permiten reproducir la validación. |
| ENT-02 | P0 | Validar macOS 26, permisos y recorrido completo con el binario distribuido antes de llamar estable a la entrega. | **N:** build 13 probó importación/síntesis e interfaz aislada, no Core Audio/micrófono actual ni macOS 26. |
| ENT-03 | P0 | Mantener proyecto limpio: Git, fuentes, evidencias, dos ZIP y acceso a app instalada; sin acumular builds y copias completas. | **V:** actual 0.9.0 (24), anterior 0.8.1 (23). La copia del proyecto enlaza a `/Applications/PAIMON.app`. |
| ENT-04 | P1 | Distribución verificable con versión, SHA-256, recursos GitHub y firma adecuada para otros Mac. | **P:** release/ZIP/hash y firma ad hoc existentes; Developer ID, notarización y comprobación en otro Mac pendientes. No sustituir tags publicados. |

## 13. Mejoras realizadas desde los problemas reportados

| Problema o petición | Mejora que ya existe | Qué falta cerrar |
| --- | --- | --- |
| «The data couldn’t be read because it is missing» y síntesis vacía/incompleta | Decodificación tolerante, respuestas incompletas explícitas, reintento acotado, síntesis obligatoria Apple y reconstrucción desde el original. | Probar fallos prolongados; igualar MLX al contrato actual y revisar calidad semántica. |
| Resumen demasiado parecido a una lista de evidencia | Resumen general, jerarquía editorial, compromisos en tabla e iconos con citas desplegables. | Corpus mayor para evaluar cobertura y omisiones, sin inventar secciones. |
| Cambios de contexto desconfiguraban dimensiones; título duplicado/ventana vacía | Editor separado, columnas acotadas, título único y divisor persistente. | Ampliar pruebas de tamaños, escalado de pantalla y accesibilidad. |
| Resumen tardío reemplazaba la sesión visible | Identidad de selección, resultados obsoletos descartados y disponibilidad separada del informe. | Mantener las regresiones al cambiar concurrencia o navegación. |
| HTTP 503 de Google AI | Reintentos limitados, esperas cancelables y mensajes sin perder transcripción. | Ensayo controlado actual con clave de prueba, si se autoriza, sin conversaciones privadas. |
| RAM limitada y procesamiento continuo | Anillos, paginación, inferencia serial, memoria jerárquica, finales recuperables y Google voluntario. | Medir toda la carga de una reunión prolongada; Google no implica ahorro demostrado. |
| Exceso de archivos y copias; icono no visible en GitHub | Dos ZIP fijos, enlace a app instalada, recursos de marca vigentes y capturas/portada públicas sintéticas. | Conservar esta política en próximas versiones, sin crear otra app/ZIP por cambio documental. |
| Unificar con METATRON | Sello geométrico, pie lateral, autor, paletas e idioma de interfaz. | Auditoría integral de accesibilidad y consistencia de mensajes dinámicos. |

## 14. Orden de trabajo recomendado

Los lotes siguientes son una **propuesta de ejecución**, no funciones nuevas ya aprobadas ni trabajo iniciado por este documento.

| Orden | Lote | Condición para cerrarlo |
| --- | --- | --- |
| **1 · P0** | Captura y permisos del binario actual | Sistema global, app concreta, micrófono, ambas fuentes y barra de menús; iniciar/pausar/reanudar/detener; muestra autorizada, salida audible y recursos liberados. Registrar firma y versión. |
| **2 · P0** | Estabilidad prolongada y recuperación | Audio real 2 h o más, presión controlada, errores de dispositivo/voz y reinicio; medir cliente y servicios, pérdidas y latencia. Conservar texto confirmado y finales pendientes. |
| **3 · P0** | Calidad de síntesis y acceso esencial | Corpus español/inglés con acuerdos explícitos, negaciones, responsables ausentes y preguntas resueltas; revisión humana de evidencia. Auditoría de teclado y VoiceOver del recorrido principal. |
| **4 · P0** | Compatibilidad y candidato estable | Repetir casos críticos en macOS 26 con el paquete final; evidencia y limitaciones actualizadas. No etiquetar estable si queda un bloqueo de captura, pérdida silenciosa o privacidad. |
| **5 · P1** | Alternativas y distribución | Pesos FluidAudio/MLX instalados explícitamente, esquema/evidencia equivalentes, perfil real; Google con entorno de prueba autorizado; Developer ID/notarización y otro Mac. |
| **6 · P1** | Pulido posterior | Reconfiguración de dispositivos, conciliación de compromisos/preguntas, importación interrumpida y mensajes de idioma; conservar arquitectura, formato y límites de memoria. |

La detección automática multilingüe de **ASR-02 sigue siendo un P0 parcial del encargo original**: antes de declarar cumplida esa línea base hay que demostrar un backend compatible o acordar expresamente un alcance con idioma elegido. Su validación puede adelantarse al lote de motores opcionales. No se resolverá presentando la selección automática de motor como reconocimiento automático de idioma.

## 15. Casos de aceptación reproducibles

| Caso | Procedimiento y resultado esperado | Estado de la evidencia |
| --- | --- | --- |
| AC-01 · Captura sin interrupción | Reproducir fixture local audible; elegir su app y luego sistema global; iniciar y detener. Obtener búferes con señal, texto definitivo y tiempos dentro de la sesión, sin silenciar la salida. | Fuente específica y global comprobadas en Release aislada. En global falta repetir la cobertura del final. Sigue pendiente el binario distribuido. |
| AC-02 · Micrófono y doble fuente | Con audífonos y material autorizado, capturar cada entrada y ambas; comprobar fuente/reloj, pausa y ausencia de monitorización. | Pendiente actual. La identidad de fuente no es identidad de hablante. |
| AC-03 · Barra de menús | Cerrar ventana durante captura; pausar, reanudar, marcar y detener desde el menú; reabrir sin perder datos. | La sesión manual asistida de Release aislada se guardó y se reabrió con texto completo y resumen. Falta comprobación directa de pausa, reanudación y marcador desde la barra. |
| AC-04 · Permisos y dispositivos | Negar/revocar permiso propio, volver a autorizar por el usuario, desconectar entrada/salida. Ningún bloqueo silencioso ni alteración de permisos de otras apps. | Pendiente de matriz actual. |
| AC-05 · Voz/importación | Importar fixture español y equivalente inglés, cancelar otra importación y reabrir SQLite. Conservar definitivos, fuente y tiempos; no duplicar audio. | Español real aprobado; ampliar inglés/cancelaciones físicas. |
| AC-06 · Resumen fundamentado | Corpus de tres temas con un acuerdo, una propuesta no acordada, tarea con y sin responsable y pregunta abierta. Exigir síntesis y citas originales; ningún campo ausente se completa por suposición. | Regresiones y muestra Apple aprobadas; ampliar evaluación semántica humana. |
| AC-07 · Finales y errores | Detener durante resumen, provocar respuesta incompleta/fallo controlado y reabrir. No perder transcripción ni síntesis válida anterior; finalizar trabajo pendiente al recuperar recursos. | Pruebas e historia de recuperación; repetir recorrido real actual. |
| AC-08 · Navegación y formato | Cambiar A→B→A con resumen en curso, buscar y saltar a cita, abrir/cancelar contexto, reducir ventana. Copiar y exportar cuatro formatos con negritas/tablas/citas donde proceda. | AppModel, formatos e interfaz aislada aprobados dentro del alcance registrado. |
| AC-09 · Privacidad y Google | Sin conexión y Google apagado, ejecutar cadena local con recursos preparados. Con transporte controlado comprobar consentimiento, 503, revocación y ausencia de audio/clave en export. | Contratos Google aprobados; ensayo completo offline y remoto actual pendientes. |
| AC-10 · Rendimiento y compatibilidad | Reunión autorizada de al menos 2 h en M1/8 GB y repetición del recorrido en macOS 26. Registrar versiones, cola/pérdidas, CPU, memoria de procesos relevantes, latencias y respuesta de UI. | Pendiente. Las cargas aceleradas no sustituyen este caso. |

**Umbrales propuestos para acordar antes de medir:** cero pérdida silenciosa de definitivos; cero emisión remota con Google desactivado; cero pendientes finales abandonados tras recuperación; controles sin bloqueo sostenido durante captura. No se fija un techo de RAM ni latencia de modelo sin medir primero todos los procesos implicados. Cualquier saturación debe notificarse y conservar el texto confirmado.

## 16. Evidencias y mantenimiento

| Referencia | Fuente para comprobar o ampliar el estado |
| --- | --- |
| E1 | [Arquitectura y privacidad](ARCHITECTURE.md), protocolos y servicios en `Sources/LAICore`; `ViewModels/AppModel.swift`. |
| E2 | [Validación por versión](VALIDATION.md), [registro de 84 pruebas](evidence/performance-tests.log) y [verificación de instalación e interfaz](evidence/performance-install-verification.json). |
| E3 | [Limitaciones vigentes](LIMITATIONS.md); capturas históricas identificadas expresamente en VALIDATION. |
| E4 | [Dependencias, recursos y APIs](DEPENDENCIES.md); wrappers opcionales en `Integrations`. Las referencias técnicas son las comprobadas al implementar, no una nueva revisión web realizada hoy. |
| E5 | `FoundationSummaryEngine.swift`, `GroundedSummary.swift`, `SummaryCoordinator.swift` y pruebas de calidad/rendimiento en `Tests/LAICoreTests`. |
| E6 | [Marca y generación reproducible](BRAND.md), recursos actuales en `Resources/Brand` y capturas sintéticas en `docs/images`. |
| E7 | [Mediciones y sus límites](PERFORMANCE.md), [entorno](evidence/performance-environment.json) e [índice de evidencias](evidence/README.md). |

Antes de publicar otra versión: revisar los P0 pendientes, ejecutar los casos afectados, actualizar evidencia y limitaciones, y mantener sincronizados este documento y el README. No se crea una versión binaria nueva por editar esta lista. No registrar conversaciones, claves ni pantallas privadas como material público.
