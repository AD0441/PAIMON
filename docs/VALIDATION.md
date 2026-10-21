# Validación — 21 de octubre de 2026

## Versión 0.5.1 (12) · ajuste de ventana

**Release: BUILD SUCCEEDED.** Firma estricta de la app instalada y de los dos ZIP extraídos: PASS. Actual: 0.5.1 (12); anterior: 0.5.0 (11). Las recompilaciones de la misma versión conservaron el archivo anterior intacto. [Verificación actual](evidence/performance-install-verification.json).

La regresión se reprodujo en la app instalada: el área útil tenía 748 puntos de alto, pero NavigationSplitView calculaba 1.593 y centraba el contenido fuera de la ventana. Se acotaron ambas columnas al espacio que reciben. Después, navegación y área útil coincidieron en 748 puntos; al reducir la ventana también coincidieron en 650. Se retiraron del código final las mediciones temporales, que solo registraban rectángulos.

**Revisión visual: PASS.** Sesión vacía y sesión guardada; cabecera, controles, título único, marca de PAIMON y firma visibles. Tamaños observados: 1.240 × 800, 1.440 × 870, 1.440 × 702 y 1.000 × 702 puntos, con barra de herramientas incluida. Se probaron el menú nativo de redimensionado, abrir/cancelar Contexto en tamaño pequeño y aumentar/reducir el divisor por accesibilidad. La proporción del divisor se conserva en SceneStorage. No se publicaron capturas de la conversación del usuario.

Esta corrección modifica únicamente la composición de la interfaz y su versión. La batería de 75 pruebas de los motores y la persistencia sigue siendo la referencia de 0.5.0; no se presenta como una nueva prueba de captura, reconocimiento o Gemini.

## Versión 0.5.0 (11)

**75 pruebas aprobadas**, con Swift 6 y el mismo M1 de referencia. Incluyen las 55 anteriores y cobertura de Google desactivado por defecto, consentimiento por sesión, compatibilidad de los valores locales anteriores, claves fuera de URL/cuerpo, consultas de conexión sin transcripción, JSON truncado y bloqueado, cuotas, tamaño máximo de respuesta, revocación en curso y durante lectura de la clave, referencias originales y rechazo de responsables o acuerdos no respaldados. También comprueban contexto acotado, identidad estable, reconstrucción al cambiar de motor/contexto, vista ejecutiva sin modificar hallazgos, términos con acentos, progreso persistido, importación con búferes de hasta 4.096 frames y conservación de finales al interrumpir. [Registro actual](evidence/performance-tests.log).

**Importación nativa real: PASS.** `PAIMON_TEST_NATIVE_IMPORT=1 ./script/test.sh` leyó `Tests/Fixtures/spanish-synthetic.aiff` mediante AVAudioFile y SpeechAnalyzer, sin alimentación artificial a ritmo real, produjo texto definitivo en español y lo guardó en SQLite. Se comprobaron micrófonos, cotización y viernes. La batería completa terminó en 1,051 s en esta ejecución; no es una medición general de velocidad para grabaciones largas. En el ejecutor restringido no se podían consultar los idiomas del sistema; la misma prueba fuera de esa restricción pasó. No se descargaron recursos.

**Google AI:** pruebas de contrato con transporte y clave sintéticos; estas pruebas automatizadas no envían conversaciones ni usan credenciales del usuario. Un fallo HTTP 503 informado por el usuario motivó la regresión de recuperación: 503/502 seguidos de éxito, mismos datos POST, máximo tres intentos, Retry-After largo sin repetición temprana, cancelación al revocar la clave durante la espera y ningún reintento para 400/401/403/404/429. En la app instalada se observó posteriormente «Síntesis final actualizada», con la casilla de Google AI seleccionada y sin error pendiente. La clave fue configurada por el usuario; no se incluye contenido de esa sesión en las evidencias. Esto confirma la finalización observada, sin medir cuotas, latencia remota ni auditar la calidad semántica. Los dobles de transporte solo están en las pruebas. La aplicación implementa HTTPS al endpoint oficial. [Estrategia oficial de reintentos](https://ai.google.dev/gemini-api/docs/troubleshooting).

**Release: BUILD SUCCEEDED.** Instalación y firma estricta verificadas, incluidos ambos ZIP extraídos. La recompilación de 0.5.0 (11) conservó intacto el ZIP anterior 0.4.0 (10). [Verificación de 0.5.0](https://github.com/AD0441/PAIMON/blob/6583215/docs/evidence/performance-install-verification.json).

**Interfaz de contexto: PASS.** En Release se comprobaron abrir, cancelar un borrador, guardar y volver a abrir. El contexto aparece en una sheet separada y los controles de captura y los paneles permanecen visibles. ⌘N limpia la selección sin abrir otra ventana. Se usó un borrador sintético sin modificar la transcripción del usuario. La captura en vivo de 0.4.0 sigue siendo evidencia histórica; la importación de un archivo no se presenta como una nueva prueba de Core Audio.

## Entorno comprobado

MacBook Pro con Apple M1 y 8 GB de memoria unificada. Sistema instalado: macOS 27.2, build 26B5101f. Xcode 27.1, build 27A9275, Swift 6.4. Deployment target del producto: macOS 26.0, arm64. No se afirma haber ejecutado la aplicación en macOS 26: esa validación sigue pendiente.

Xcode se instaló desde la App Store oficial y completó la configuración inicial con la licencia aceptada por el usuario. Los scripts seleccionan su toolchain con `DEVELOPER_DIR`; el selector global del equipo aún apunta a Command Line Tools. Cambiarlo globalmente requiere la contraseña de administrador: `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`. Esto no impide ejecutar los scripts del proyecto.

## Compilación

### Rendimiento y estabilidad · versión 0.4.0 (10)

Compilación Release con Xcode: **BUILD SUCCEEDED**. Instalación en Aplicaciones, acceso de la aplicación junto al proyecto y ZIP portátil. El acceso del proyecto sigue a la app instalada porque File Provider volvía a añadir FinderInfo e invalidaba el bundle copiado. El ZIP se extrae y verifica con `codesign --verify --deep --strict`. [Compilación e instalación](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-release-build.log), [verificación histórica](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-install-verification.json), [entorno anónimo](evidence/performance-environment.json).

**55/55 pruebas aprobadas**, con los 35 casos anteriores y cobertura nueva de finalización durante actualización manual, agrupación de solicitudes, cancelación, reducción de contexto, registro duradero, migración, cola final persistente, contrapresión de texto, paginación, reconstrucción sin resucitar hechos descartados, cancelación por memoria de sesiones activas y en cola, restauración de preferencias de diagnóstico y acuerdos frente a asuntos pendientes en español e inglés. [Registro histórico](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-tests.log).

**SpeechTranscriber real desde archivo: PASS.** La muestra sintética produjo el segmento definitivo completo. Tiempo total 10,50 s, CPU del cliente 0,22 s y RSS máximo 20,06 MB; excluye los servicios de modelos del sistema. [Medición](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-file-asr.json), [texto](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-file-asr.log).

**Foundation Models real: PASS.** Doce fragmentos sintéticos, tres temas cubiertos, síntesis general, seis hallazgos y citas tomadas del original. La última repetición, con procesamiento v3, tardó 18,49 s con footprint del cliente de 9,80 MB. El informe conserva negritas, puntos y un único anexo al final. [Medición](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-native-summary.json), [informe](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-native-summary.md).

**Cargas aceleradas de 10/30/60/120/240 minutos: PASS**, hasta 1.440 fragmentos y decisiones exportadas, sin pendientes ni crecimiento de las páginas visibles por encima de sus límites. Se usa un motor determinista de diagnóstico y texto sintético: no es una reunión real de cuatro horas. [Mediciones y alcance](PERFORMANCE.md), [JSON](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-long-sessions.json).

**Cadena completa real de captura: PASS en build 9.** Core Audio Process Tap → SpeechTranscriber → SQLite → Foundation Models → JSON: 1.052 búferes, 538.624 frames, 769 búferes con señal, un segmento definitivo completo y cinco hallazgos. Preparación 0,41 s y captura 11,33 s. Búsqueda, marcador y tiempos comprobados; audio sin guardar. Footprint final del cliente 64,19 MB, sin los servicios del modelo de Apple. Se revisaron en la interfaz texto parcial, texto definitivo, resumen, negritas e iconos de evidencia. [Resultado](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-capture-validation.json), [sesión sintética](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-capture-validation.session.json).

Las repeticiones anteriores fallaron sin búferes tras esperar en `AudioDeviceCreateIOProcIDWithBlock`. TCC registró que la firma ad hoc de la compilación no coincidía con la autorización almacenada, aunque el interruptor de PAIMON estaba activado. El usuario autorizó renovar el permiso y completó Touch ID; repetir el mismo binario pasó. No se reinició el servidor de audio ni se modificó la base de TCC. Se conservan [fallo inicial](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-capture-repeat.json), [fallo antes de renovar](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-capture-before-renewal.json) y [diagnóstico de firma](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-capture-permission-mismatch.json). Build 9 también excluye del reloj la espera de cierre de dispositivos: la muestra pasó de 101,21 s inflados a 11,33 s de captura.

La revisión del resumen detectó que «Falta decidir dónde instalar los equipos» había tomado el acuerdo de otra frase como justificación. **Build 10 / procesamiento Apple v3** valida la decisión contra la frase que contiene el acuerdo. Las dos regresiones cubren español, inglés y el decodificador alternativo. La repetición con Foundation Models real clasificó correctamente comprar micrófonos como decisión, enviar cotización como tarea e instalación como pregunta abierta. [Resultado nativo](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-pending-decision-native.log). Actualizar reconstruye los snapshots Apple anteriores al procesamiento v3 desde el original.

**Captura y controles de Release build 10: PASS.** Tras desbloquear macOS se reprodujo la muestra con la fuente global y el micrófono apagado. La app instalada mostró texto parcial y un único fragmento definitivo idéntico a la muestra, sin duplicados y con tiempos válidos. Pausar → Reanudar → Detener funcionaron desde la interfaz; la sesión terminó a los 25,07 s. Se exportó JSON mediante el diálogo real y se comprobó su contenido. Audio sin guardar y cero sesiones activas al finalizar. La primera tentativa bloqueada se conserva como sesión interrumpida; no se borró contenido del usuario. [Comprobaciones](evidence/performance-release-ui-validation.json), [exportación sintética](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/performance-release-ui.session.json).

**Resumen de esa sesión: aplazado y recuperado posteriormente.** En la comprobación inicial, macOS informó nivel 2 y la interfaz mostró «Síntesis en espera hasta que baje la presión de memoria». Se verificó el trabajo final persistido en SQLite; la primera exportación, conservada como evidencia histórica, contiene la transcripción y ningún hallazgo. Posteriormente se observó el resumen final v3 en la app: cinco hallazgos, citas comprobadas contra el original y cero trabajos pendientes. Se capturaron la vista principal y el popover de evidencia. No se forzó la inferencia ni se cerraron apps del usuario. El disparador exacto de esa recuperación y la transición de presión no se registraron de forma independiente; en la observación posterior el indicador global seguía en nivel 2. [Recuperación y alcance](evidence/performance-summary-recovery.json), [captura de la app](images/paimon-session.png), [citas](images/paimon-evidence.png).

Para repetir sin cambiar la firma de Release: `./script/open_audio_fixture.sh`, elegir **PAIMON Audio Fixture** en PAIMON instalada, **Iniciar**, **Reproducir muestra**, esperar a que termine y **Detener**. Mantener macOS desbloqueado y comprobar **Privacidad y seguridad → Grabación de audio del sistema y pantalla → Sólo grabación de audio del sistema**. No volver a compilar después de autorizar ese binario. El diagnóstico DEBUG completo sigue disponible con `./script/validate_local_audio.sh`, pero una firma ad hoc distinta puede necesitar renovación del permiso.

También faltan sesiones reales prolongadas y macOS 26. Las pruebas de Core Audio de versiones anteriores se conservan abajo como evidencia histórica.

### Corrección de síntesis · versión 0.3.2

El caso reportado conservaba 27 fragmentos y 6 minutos 20 segundos de transcripción, pero sus snapshots finales contenían solo un tema y un punto. El primer lote había aceptado únicamente un título. La validación anterior comprobaba que una cita existiera, sin exigir suficiente relación léxica con la afirmación ni un resumen general obligatorio. El cursor ya había avanzado, por lo que Actualizar volvía a condensar el resultado insuficiente.

La ruta Apple usa ahora un esquema compacto con resumen general obligatorio, puntos concretos y referencias a fuentes locales. Las citas y sus tiempos se resuelven desde SQLite; el texto del modelo no determina las citas. Una comprobación conservadora descarta afirmaciones y referencias sin vocabulario relevante compartido. No sustituye la revisión semántica humana. Se preservan los puntos anteriores y se integra la memoria de resúmenes parciales. La versión de procesamiento invalida resultados antiguos al actualizar y permite reconstrucción explícita desde el original. Un resultado sin síntesis no puede marcarse como final. Los informes admiten varios fragmentos de evidencia por afirmación.

`./script/test.sh`: **35 pruebas aprobadas**, incluidas nueve regresiones nuevas: cita introductoria irrelevante, resumen general obligatorio, referencias locales y exportación en cuatro formatos, cursor sin avance ante un título aislado, reconstrucción de la versión anterior, conservación de puntos previos y estado parcial ante final insuficiente, lectura de datos antiguos, varios puntos de una misma fuente sin duplicados por puntuación y exclusión de saludos/problemas de micrófono ajenos a la síntesis. [Registro](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/summary-quality-tests.log).

`LAICheck --validate-summary`: **PASS** con Foundation Models real y 12 fragmentos sintéticos, tres temas cubiertos, síntesis general obligatoria y referencias originales. Tiempo total 24,22 s y footprint propio del diagnóstico 10,13 MB; no incluyen CPU ni memoria de los servicios del modelo de Apple y no certifican consumo global ni una reunión prolongada. [Resultado](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/summary-quality-native.json), [registro](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/summary-quality-native.log), [informe sintético](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/summary-quality-synthetic.md).

El registro del usuario se reconstruyó en una base temporal y solo se publicó el snapshot completo al tener éxito. Se conservaron los 27 fragmentos originales y se obtuvieron tema, resumen general y siete puntos. El Markdown corregido contiene una transcripción idéntica a la del archivo original y todas las referencias se comprobaron contra los fragmentos guardados. El archivo original no se sobrescribió. El texto privado no se incorporó al repositorio ni a estas evidencias. Se verificaron en la app instalada la síntesis guardada y el popover con varias referencias. La selección local de motor quedó en Apple, disponible; MLX no estaba preparado.

La compilación final **0.3.2 (7)** terminó con BUILD SUCCEEDED y actualizó ambas copias de PAIMON. Se comprobó que sus ejecutables coinciden y que la firma estricta de Aplicaciones es válida. El único aviso de Xcode fue la omisión de metadatos App Intents, que este producto no utiliza. [Registro](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/summary-quality-build.log). La captura y el reconocimiento de audio no se modificaron ni se repitieron en esta corrección; las pruebas nativas de este cambio usan texto local.

### Identidad PAIMON · versión 0.3.1 (5)

El PNG original `Sinora_icono.png` se copió exactamente a `Resources/Brand` y se generó `Resources/Paimon.icns` con las resoluciones estándar mediante `sips` e `iconutil`. Se verificó por SHA-256 que la copia original coincide con el archivo entregado y que el icono incluido en el bundle coincide con el recurso del proyecto. El producto y el ejecutable ahora se llaman PAIMON; el identificador y las rutas de datos conservan su identidad anterior. [Verificación](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/paimon-branding-verification.json).

`./script/build_and_run.sh --install`: **BUILD SUCCEEDED**, instalada `/Applications/PAIMON.app` y copiada `PAIMON.app` junto al proyecto. Ambas contienen el mismo ejecutable. Firma estricta de la copia instalada: correcta. File Provider sigue incorporando FinderInfo a la copia del proyecto, afectando su verificación estricta; no bloquea la instalación de la copia verificada en Aplicaciones. Las copias con el nombre anterior se retiraron a un respaldo temporal indicado en el registro. [Registro de compilación e instalación](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/paimon-branding-build.log).

`./script/test.sh`: **26 pruebas aprobadas** tras la compilación final. [Registro](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/paimon-branding-tests.log). No se añadieron modelos ni se repitió la captura de audio por este cambio de identidad. Se comprobó visualmente el icono en la barra lateral y el panel nativo **About PAIMON**, la versión 0.3.1 (5), el nombre de la ventana y de los menús, y los textos **Local Audio Intelligence** y **Transformando sonido en conocimiento.**

### Validaciones anteriores

- `./script/build_and_run.sh --verify`: Xcode genera la `.app` y la abre. Resultado: **BUILD SUCCEEDED** y proceso verificado.
- `./script/build_and_run.sh --install`: genera una copia Release en la carpeta del proyecto y otra en `/Applications/Local Audio Intelligence.app`. Firma ad hoc comprobada con `codesign --verify --deep --strict`; ejecutable arm64 y dependencias enlazadas del sistema. Es una instalación local, sin notarización para distribución.
- `./script/test.sh`: **26 pruebas aprobadas** con Swift Testing. Véase [registro](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/swift-tests.log).
- FluidWorker con el código de FluidAudio 0.17.3 y el manifiesto reducido: **compilación correcta**. Se comprobó que una carpeta sin modelos devuelve un error local estructurado, sin intentar descargarlos. No se ejecutó Parakeet con pesos reales.
- `mlx_summary.py`: sintaxis validada. MLX y sus pesos no se instalaron ni se ejecutaron.

Las pruebas comprueban desbordamiento y recuperación del anillo, downmix, VAD con histéresis, conversión PCM y continuidad entre bloques, reapertura SQLite, parciales no persistidos, búsqueda literal, borrado en cascada y de audio, paginación/exportación de 240 fragmentos en los cuatro formatos, contenido y acentos del PDF mediante PDFKit, esquemas Foundation Models, rechazo de citas e identificadores inexistentes, responsables/fechas fuera de la cita, cursores de resúmenes acumulativos, deduplicación de tareas reformuladas y formato de informe copiable.

## Herramientas de sesión · versión 0.3.0

Se añadieron seis pruebas de marcadores y notas persistentes, paginación, borrado en cascada, búsqueda FTS5 con acentos/prefijos/correcciones y operadores tratados literalmente, migración reanudable desde una base anterior de 250 fragmentos, compatibilidad de preferencias antiguas, cambio de plantilla sin pasadas adicionales en la actualización normal y exportación de 101 notas completas en los cuatro formatos. Las pruebas de formato del informe anterior siguen aprobadas.

`LAICheck --summary lecture` ejecutó Foundation Models real con texto sintético sobre corriente, amperios y ley de Ohm. Produjo conceptos e ideas con citas validadas: **PASS**. No se instalaron modelos adicionales. [Registro](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/template-class-native.log).

`LAICheck --benchmark-tools /tmp/lai-tools-benchmark.json` midió SQLite aislado con 1.200 fragmentos sintéticos, 200 búsquedas y 200 escrituras concurrentes. Percentil 95: **3,145 ms por búsqueda**, **3,086 ms por escritura durante búsquedas**; máximos observados 29,051 y 28,781 ms respectivamente. El footprint del proceso de diagnóstico pasó de **3,44 a 4,52 MB**. [Datos](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/session-tools-benchmark.json), [registro](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/session-tools-benchmark.log). No se cargaron audio ni modelos: esta medición no certifica CPU total, batería o rendimiento de reuniones largas.

Se repitió la cadena de audio real con la versión 0.3.0: **PASS**, 1.049 búferes, 537.088 frames, 768 búferes con señal, transcripción definitiva, cuatro hallazgos, coincidencia en la búsqueda global y un marcador persistido. La preparación duró 2,11 s y la captura 12,88 s; las marcas de la transcripción quedaron dentro de la duración de la sesión. Se corrigió el reloj para excluir una espera prolongada de permisos/dispositivos y el tiempo de finalización del reconocimiento. Footprint propio al acabar: **59,84 MB**; no incluye servicios de modelos de Apple. Audio capturado sin guardar. [Resultado](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/tools-capture-validation.json), [sesión sintética](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/tools-capture-validation.session.json).

En Release instalada se verificaron ⌘⇧F, la búsqueda de «cotización», la apertura del fragmento de prueba, ⌘⇧M para crear otro marcador, la edición de una nota y su persistencia al volver a cargar la sesión, las tres opciones del selector Plantilla y la casilla Marcadores y notas de la exportación. Estas acciones se realizaron sobre la sesión sintética; no se modificó el texto de una sesión del usuario.

La compilación final Release 0.3.0 (4) terminó con **BUILD SUCCEEDED** y se abrió desde Aplicaciones, restaurando la selección del usuario. Las dos copias contienen el mismo ejecutable. La firma estricta de Aplicaciones pasa; el instalador verificó también la copia del proyecto, pero File Provider volvió a añadir FinderInfo después y la comprobación estricta posterior de esa copia falla incluso tras retirarlo. Es la limitación de la carpeta sincronizada descrita más abajo; para uso habitual se recomienda la copia instalada en Aplicaciones. El único aviso de compilación fue la omisión de metadatos App Intents, que este producto no usa.

## Informe copiable

La versión 0.2.0 usa una estructura compartida para la vista, el portapapeles y los documentos: título y metadatos, resumen general, puntos clave, acuerdos, tabla de compromisos, preguntas y conclusiones. Omite secciones vacías y conserva los campos desconocidos como «No especificado». Los conceptos destacados se toman literalmente del texto; el formateador no genera afirmaciones.

Se verificó el recorrido RTF de ida y vuelta: títulos y conceptos mantienen la fuente en negrita y los compromisos conservan celdas `NSTextTableBlock`. El HTML del portapapeles también usa una tabla real. Las pruebas del PDF comprueban fuentes en negrita, tablas que continúan entre páginas sin perder texto, siete iconos con destinos internos válidos y la exclusión del anexo cuando se desactiva. Se generaron y revisaron visualmente las páginas de un informe de prueba con contenido sintético local. La navegación a evidencia de una sesión de 640 fragmentos carga como máximo 300, incluyendo el fragmento antiguo solicitado.

En la aplicación Release 0.2.0 instalada se verificaron el diseño, la apertura del popover de evidencia, el botón **Ir al fragmento**, el cambio a **Copiado** y la opción **Anexo de evidencias** en la exportación. Ambas copias contienen el mismo ejecutable; se comprobó su firma durante la instalación. El instalador elimina únicamente FinderInfo y ResourceFork del bundle del proyecto y reintenta la verificación ante la incorporación asíncrona de metadatos por File Provider. Se observó que File Provider puede volver a añadir FinderInfo a la copia del proyecto después de instalarla: esto vuelve a afectar su verificación estricta y requiere limpiar ese atributo. La copia de Aplicaciones no presentó ese problema.

## Recuperación de respuestas incompletas

La lectura de una respuesta estructurada descarta los hallazgos sin campos obligatorios y conserva los demás para validar sus citas. Nunca completa un campo faltante con contenido inventado. Se comprueba `GeneratedContent.isComplete`; una respuesta incompleta o sin evidencia dispara un reintento acotado a tres hallazgos en una sesión nueva. Si vuelve a fallar, se muestra una explicación en español y la opción de reintentar mediante **Actualizar resumen**.

Las pruebas reproducen claves ausentes, tipos incorrectos, valores nulos, JSON truncado y recuperación del cursor después de un fallo. El resumen guardado y la transcripción permanecen disponibles durante el fallo. También se ejecutó `LAICheck --summary` con Foundation Models real y texto sintético local: **PASS**, con citas verificadas. [Registro](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/summary-recovery-native.log).

## Cierre por presión de memoria

Durante la instalación se identificó en un informe local un fallo de aislamiento (`_dispatch_assert_queue_fail`) dentro del callback de `AppModel.bootstrap`. Dispatch ejecutaba el callback en una cola global, mientras la clausura heredaba `MainActor`. Se marcó el callback explícitamente `@Sendable`; la actualización observable de la interfaz permanece dentro de `Task { @MainActor ... }`. Se recompiló Release, se abrió la copia instalada y se repitieron las 14 pruebas correctamente. No se indujo presión de memoria global para probar este cambio.

## Audio y modelos reales

La muestra incluida en `Tests/Fixtures` es voz sintética producida localmente por macOS. Es un archivo de prueba, no una transcripción predeterminada de la aplicación.

1. **Archivo → SpeechAnalyzer real:** la voz española produjo el texto completo del archivo, sin cierres prematuros. [Transcripción](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/file-transcription.log).
2. **Audio reproducido → Core Audio process tap → SpeechAnalyzer → SQLite → Foundation Models:** **PASS**. Se reprodujo la muestra desde la app y se capturó únicamente el audio de ese bundle mediante el mismo servicio utilizado para seleccionar aplicaciones. Se obtuvieron 1.049 búferes, 537.088 frames y 768 búferes con señal, una transcripción definitiva y tres hallazgos con citas verificadas. El modelo extrajo «Ana» y «viernes» de la cita correspondiente. No se guardó audio capturado. [Resultado medido](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/capture-validation.json), [sesión exportada](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/capture-validation.session.json).
3. **Foundation Models:** disponibilidad y español comprobados con APIs oficiales; generación estructurada real, validación de citas y ausencia de conexión a servicios remotos en el código de ejecución.

Una regresión detectada y corregida durante la prueba consistía en añadir el tail del resampler a cada bloque, creando solapamientos temporales. La versión final conserva el convertidor por fuente, usa un contador de frames monotónico, vacía el último bloque y mantiene el reloj común al reanudar.

Para repetir la cadena completa, sin grabar otras aplicaciones:

```bash
./script/validate_local_audio.sh
```

La validación es una opción explícita de compilaciones DEBUG, reproduce una muestra audible y requiere el permiso de audio del sistema. Los botones de la aplicación normal siempre capturan/transcriben audio real; no presentan resultados simulados.

## Recursos medidos

- Al finalizar la prueba completa: aproximadamente **55 MB de footprint propio** y 54 MB de RSS de la aplicación.
- Diagnóstico de archivo: pico de RSS **18.9 MB**, 12.49 s de tiempo total con alimentación a ritmo real y 0.12 s user + 0.09 s sys del proceso cliente. [Medición](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/file-transcription-resources.log).
- Instruments Time Profiler: captura real de **10 segundos**, posterior a la prueba. [Registro](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/instruments.log), [tabla de contenido saneada](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/idle-profile-toc.xml), [estadísticas](https://github.com/AD0441/PAIMON/blob/v0.4.0/docs/evidence/idle-profile-stats.json). La traza original permanece en `/tmp/lai-idle.trace`; se omitió del proyecto porque Instruments incluye metadatos del entorno del usuario.

Estas cifras **no incluyen la memoria ni el CPU de los procesos de modelos de Apple** y no certifican el consumo global, batería o latencia de una reunión prolongada. No se calcula un porcentaje de CPU a partir del número de filas del perfil.

## Comprobación manual que falta

Repetir en macOS 26; reuniones de varias horas; español e inglés con cambios de idioma; selección de distintos reproductores y aplicaciones de reunión; permisos denegados/revocados; conectar/desconectar dispositivos; eco acústico; presión de memoria sostenida; backend Parakeet con pesos instalados; backend MLX con su entorno y modelo opcionales. La captura global y la mezcla acústica sistema/micrófono requieren repetir esos escenarios con material autorizado.
