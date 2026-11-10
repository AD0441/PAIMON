# Validación de PAIMON

## Desarrollo · Acuerdos y pendientes

Pasaron 94 pruebas y la compilación Release arm64 con firma verificada. La nueva vista consulta acuerdos, compromisos y preguntas abiertas directamente en el registro de hallazgos. La prueba de AppModel guardó 120 ideas antes del primer acuerdo y verificó que aparecieran dos páginas de resultados filtrados. También comprobó que dos tareas con el mismo texto y distintos responsables se mostraran por separado y conservaran sus citas.

## Desarrollo · síntesis compacta y audio difícil · 10 de noviembre de 2026

Foundation Models recibe pares de identificador y texto. Una medición previa con el tokenizador local dio 328 frente a 287 tokens para el bloque de 12 fuentes sintéticas. Se conserva el esquema de respuesta y la validación de citas. Si al agrupar los hallazgos para la síntesis queda un grupo de un solo elemento, este pasa a la siguiente etapa directamente. Se ahorra una solicitud por cada grupo de ese tipo.

Pasaron 93 pruebas, incluida la importación con Apple Speech en ambos modos. Los dos ensayos nativos de resumen se cancelaron cuando macOS notificó presión de memoria. El efecto sobre la latencia y la calidad de la generación local requiere completar esas pruebas. La [comparación de audio difícil](PERFORMANCE.md#normalización-con-audio-difícil--10-de-noviembre-de-2026) se completó con tres variantes sintéticas.

## Instalación local 0.7.0 (16) · nivel del audio importado y limpieza de sesiones

La compilación 16 quedó instalada en Aplicaciones. Se verificaron la firma, la copia portátil y el respaldo de la compilación 15.

Pasaron 93 pruebas en el M1 de 8 GB y compiló Release arm64 con firma verificada. En la instancia aislada se comprobó que el interruptor de nivel parte apagado y que se puede activar y desactivar en Configuración. SpeechTranscriber reconoció la muestra española en ambos modos. La prueba de señal verificó ganancia para audio bajo, compresión de picos, silencios, tiempos y conservación exacta del archivo original. Queda por medir la precisión con grabaciones ruidosas.

Se probó el borrado con dos sesiones sintéticas. Desaparecieron el texto original y revisado, la búsqueda, el resumen, las notas, el vínculo al audio, las métricas, el trabajo pendiente y las grabaciones con sus tiempos. Se conservó la otra sesión y los archivos externos. Al vaciar el historial, se recuperó espacio de SQLite y quedó vacío el archivo WAL antes de reabrir la base. También pasó la exportación de los cuatro formatos y el reemplazo de un JSON existente.

## Candidata publicada 0.7.0 (15) · 9 de noviembre de 2026

Pasaron 90 pruebas, con 79 del núcleo y 11 de AppModel. La batería incluyó importación real en español con el motor nativo. Xcode compiló Release arm64 en el M1 de 8 GB con macOS 27.3. El destino mínimo es macOS 26.0.

El instalador actualizó Aplicaciones y verificó la firma estricta del bundle y de los dos ZIP extraídos. El ejecutable y el Info.plist del ZIP actual coinciden con los de la copia instalada. El proyecto conserva el enlace a Aplicaciones, el ZIP actual 0.7.0 (15) y el anterior 0.6.0 (13). El ZIP de la candidata tiene SHA-256 `54df730893c6db224535a38ddaaf38a66a6eb9b37afd85c57163985f748595fb`. [Descarga y checksum](https://github.com/AD0441/PAIMON/releases/tag/v0.7.0-rc.1).

El recorrido de captura descrito abajo corresponde a la compilación 14 aislada. La repetición con el paquete distribuido y la prueba en macOS 26 quedan pendientes.

## Captura en Release aislada · 9 de noviembre de 2026

Xcode compiló Release arm64 con destino macOS 26.0. Se ejecutó en el M1 de 8 GB con macOS 27.3. La instancia PAIMON_REVIEW 0.7.0 (14) usó almacenamiento temporal y firma ad hoc verificada. Su identificador es local.audio.intelligence.review.releasecapture y su CDHash es 6b6e8dd4250037e54d07ea98c59320e21281cca1. El modo de revisión mantiene separado el historial y deja Google AI desactivado. La firma y el identificador pertenecen a la instancia aislada.

- **Aplicación específica.** Se seleccionó PAIMON Audio Fixture y se comprobó iniciar, pausar, reanudar y detener. Los dos pases de la muestra guardaron dos fragmentos definitivos completos de la fuente Sistema. Los tiempos quedaron dentro de la sesión de 35,20 s. Foundation Models guardó una síntesis final.
- **Audio global.** Se seleccionó Todo el sistema. La sesión de 13,31 s guardó un fragmento definitivo de Sistema y una síntesis final. La captura se detuvo cerca del final de la reproducción y el texto quedó una palabra más corto que la muestra. El ensayo verifica el tap global y la síntesis. Falta repetir con margen tras el final del audio para verificar la cobertura.
- **Barra de menús.** En la prueba manual asistida se observó la sesión activa en SQLite y luego terminada y visible al volver a la ventana. La sesión de 69,65 s guardó un fragmento completo de Sistema, una síntesis final y cinco citas cotejadas con el texto y sus intervalos. El control remoto no observó individualmente Pausar y Reanudar en el menú.

Las tres sesiones mantuvieron el micrófono apagado y el audio sin guardar. SQLite pasó la comprobación de integridad. Se cotejaron las 14 citas de los resúmenes finales y quedaron cero sesiones activas y cero síntesis en cola. Quedan por verificar el micrófono, ambas fuentes, cada control de pausa/reanudación en la barra y el paquete de distribución.

## Recuperación de resúmenes bajo presión de memoria · 9 de noviembre de 2026

Pasaron 90 pruebas en M1 de 8 GB con macOS 27.3. Son 79 pruebas del núcleo, incluida la importación española con el motor nativo, y 11 de AppModel. Las nuevas regresiones verifican que una advertencia cancela una espera programada, que el control de captura permanece habilitado durante la espera y que la acción Actualizar conserva la solicitud final después de un fallo del motor. Xcode compiló Release en arm64 con destino mínimo macOS 26.0 y la firma pasó la verificación estricta.

El diagnóstico de la grabación de 35:37 muestreó presión normal durante 15 s antes de llamar al motor local. macOS notificó nivel 2 después de 2,09 s de intento y se canceló la generación antes del primer bloque. SQLite pasó `PRAGMA quick_check`, con 166 segmentos, cero síntesis y un trabajo final pendiente. Este ensayo mide la reacción del motor en esas condiciones de memoria. La política nueva de reintentos se verificó por separado en las pruebas de AppModel.

## Revisión de transcripciones · 9 de noviembre de 2026

En M1 de 8 GB con macOS 27.3 pasaron las 88 pruebas (79 del núcleo y 9 de AppModel) y compiló el proyecto Xcode en Debug. La regresión comprueba que el texto revisado aparezca en búsqueda y exportación, que la restauración conserve el intervalo y que una exportación con resumen desactualizado se detenga.

La instancia aislada importó la muestra sintética española con SpeechTranscriber. Se comprobó el inicio de reproducción desde una cita y que el control de detener desapareciera al concluir. Se corrigió un fragmento desde la ventana, se vio el aviso de actualización y Foundation Models regeneró el acuerdo con el texto revisado. SQLite conservó el texto reconocido, el vínculo al archivo y la misma revisión en la transcripción y el resumen. Quedaron cero trabajos pendientes de la muestra sintética. Estos cambios se validaron en desarrollo.

En un reintento de la grabación de 35:37, la síntesis comenzó con presión normal. A los 2,03 s la presión subió a nivel 2 y el diagnóstico canceló la inferencia. La base pasó la comprobación de integridad, conservó los 166 segmentos y mantiene un trabajo final pendiente.

## Candidata local 0.7.0 (14) · 9 de noviembre de 2026

**Xcode Release:** compilación arm64 exitosa en macOS 27.3, con destino mínimo macOS 26.0. Se comprobó el identificador del bundle, la versión, las descripciones de permisos y la firma ad hoc. Tras extraer el ZIP, el ejecutable y el Info.plist coincidieron con el original y la firma estricta volvió a pasar. El paquete local es `PAIMON-0.7.0-candidata.zip`. SHA-256: `a44786ba4373bf88bf89cb86990ad08c09dcb6d23a98abf8e4c48afece265f59`. Durante esa comprobación, Aplicaciones conservaba la versión 0.6.0 (13).

**Grabación de 35:37:** el diagnóstico con el núcleo de la candidata importó el audio local en 22,02 s, guardó 166 segmentos definitivos y registró cero avisos. Al comenzar la fase de resumen, macOS estaba en presión de memoria de nivel 2. El diagnóstico aplazó la inferencia y verificó una base SQLite íntegra con un trabajo final pendiente. La síntesis larga queda por probar cuando el sistema vuelva a presión normal.

Pendientes del paquete Release: captura de una app, audio global, micrófono, ambas fuentes y barra de menús con la firma de la candidata. También quedan por validar captura continua prolongada y ejecución en macOS 26. Los resultados previos de la instancia Debug aislada conservan su alcance.

## Lote de transcripción y síntesis · 9 de noviembre de 2026

**87 pruebas aprobadas** en M1 de 8 GB y macOS 27.3, con 78 del núcleo y 9 de AppModel. La nueva regresión suspende el motor de resumen para comprobar que el texto ya está guardado y que la sesión queda libre para consulta. El trabajo final persiste mientras se genera el informe y se retira al completarse. El motor de voz nativo se ejecutó con la muestra española.

**Xcode Debug aislado:** se importó la muestra sintética y se observó «Transcripción lista», la acción de copiar la transcripción completa y Exportar habilitados. Foundation Models guardó una síntesis final. El resumen general separó la compra acordada del envío de la cotización. El informe clasificó ambos como decisión y tarea, respectivamente, y conservó a Ana y el viernes como datos de la fuente. Las citas de los hallazgos se cotejaron con SQLite. Quedaron cero trabajos pendientes.

La preparación de captura comunica la fase de voz, micrófono o audio del sistema y ofrece abrir Ajustes del Sistema durante la preparación de una fuente. El lote está en código de desarrollo. La comprobación de permisos con este binario y el recorrido de la versión instalada siguen pendientes.

## Desarrollo · 9 de noviembre de 2026

**85 pruebas aprobadas** en Apple M1 de 8 GB, macOS 27.3. Incluyen 77 del núcleo, con importación española real, y 8 de AppModel. La regresión de recuperación se ejecutó en dos estados, importando y finalizando. En ambos, el aviso de presión normal llegó mientras la app estaba ocupada. Al quedar libre, la síntesis se ejecutó, se guardó el resultado final, se retiró el trabajo de la cola y se conservó el fragmento original. La prueba usa un motor controlado para reproducir el orden de eventos sin forzar presión del sistema. El cambio pertenece al código de desarrollo.

**Captura sintética aislada:** en macOS 27.3, el build Debug de desarrollo `local.audio.intelligence.review.stage` obtuvo permiso de audio. El diagnóstico capturó su propia reproducción mediante Core Audio y guardó un definitivo en 11,46 s de sesión. Recibió 1.053 búferes, 769 con señal y 539.136 frames. Foundation Models guardó una síntesis final con cinco referencias cotejadas contra SQLite.

**Controles con fuente específica:** se seleccionó PAIMON Audio Fixture y se verificaron Iniciar, Pausar, Reanudar y Detener en la ventana. Se guardaron dos segmentos de sistema, de 30,05 a 34,54 s y de 47,23 a 57,79 s, dentro de la sesión de 76,78 s. La síntesis final tuvo ocho referencias cotejadas contra SQLite. En ambos recorridos se desactivó el micrófono, no se guardó audio y quedaron cero trabajos finales pendientes. La captura global, el micrófono, la barra de menús y la firma del binario instalado quedan por verificar en esta versión.

[Ensayos locales de rendimiento y duración](PERFORMANCE.md#grabación-real--9-de-noviembre-de-2026).

## Versión 0.6.0 (13)

**Release: BUILD SUCCEEDED.** Se instaló en `/Applications/PAIMON.app` y el proyecto quedó enlazado a esa copia. Firma estricta comprobada en la app y en los dos ZIP extraídos: actual 0.6.0 (13), anterior 0.5.1 (12). Solo se conservan esos dos archivos. [Resultado y SHA-256](evidence/performance-install-verification.json).

**84 pruebas aprobadas:** 77 del núcleo y 7 de AppModel, estas últimas con 13 casos. Incluyen regresiones de respuestas tardías entre sesiones, disponibilidad separada del documento, búsqueda cancelable, conservación de marcadores/evidencias, compatibilidad de preferencias, cuatro paletas, idioma de interfaz y argumentos del catálogo. También se comprueba cerrar el flujo de importación si falla el guardado inicial y rechazar una advertencia de aprobación ausente que el modelo añadía sin respaldo. [Registro](evidence/performance-tests.log).

**Motores reales:** SpeechTranscriber importó la muestra sintética española y produjo los términos esperados. Foundation Models v4 procesó doce fragmentos sintéticos: resumen general, los tres temas y citas originales, seis hallazgos; 38,19 s y 10,25 MB de footprint final del cliente. Estas cifras excluyen los servicios de modelos de Apple y no representan una reunión completa. El resultado está incorporado a la verificación enlazada arriba.

**Interfaz aislada:** bundle `local.audio.intelligence.review`, SQLite, preferencias y servicio de Llavero separados. Se comprobaron las cuatro paletas, español/inglés sin cambiar reconocimiento `es-ES`, persistencia al relanzar, icono y pie lateral, destino de Ko-fi, renombrado, búsqueda, contexto abrir/cancelar y salto de cita al original. Ventanas de 1240 × 800 y aproximadamente 1000 × 702 puntos conservaron título, controles y pie; también se revisó apariencia oscura. Las tres capturas públicas actuales usan exclusivamente esa muestra sintética. El código de preparación de Review está excluido de la compilación distribuida.

Una importación anterior de Review quedó esperando al servicio nativo. Se añadió cancelación explícita durante la preparación y caché positiva de metadatos de recursos durante 60 s, invalidada al instalar o comprobar manualmente. Las siguientes importaciones finalizaron. No se afirma que todos los posibles bloqueos del servicio de macOS estén eliminados.

**Instruments:** Time Profiler de 10 s en Review en reposo, sin captura ni inferencia activa. Una observación separada de 10,12 s registró 0,40 % de un núcleo, RSS entre 19,61 y 20,33 MB; `sample` informó footprint 64,4 MB y pico de proceso 95,1 MB. Son medidas distintas; no se suman ni prueban ahorro, energía o estabilidad durante horas. La traza permanece temporal y no se publica.

**Alcance pendiente:** no se repitió Core Audio/micrófono con la firma de build 13, ni reuniones de varias horas, macOS 26, pesos FluidAudio/MLX o una petición real de Google. La captura histórica siguiente conserva su versión. La firma es ad hoc, sin notarización; TCC puede requerir renovar el permiso al actualizar. La entrega sigue como versión preliminar [0.6.0](https://github.com/AD0441/PAIMON/releases/tag/v0.6.0).

Entorno actual: Apple M1, 8 GB, macOS 27.2 build 26B118, Xcode 27.1; deployment macOS 26.0 arm64. [Entorno registrado](evidence/performance-environment.json).

## Versión 0.5.1 (12) · ajuste de ventana

**Release: BUILD SUCCEEDED.** Firma estricta de la app instalada y de los dos ZIP extraídos: PASS. Actual: 0.5.1 (12); anterior: 0.5.0 (11). Las recompilaciones de la misma versión conservaron el archivo anterior intacto. [Verificación histórica de 0.5.1](https://github.com/AD0441/PAIMON/blob/v0.5.1/docs/evidence/performance-install-verification.json).

La regresión se reprodujo en la app instalada: el área útil tenía 748 puntos de alto, pero NavigationSplitView calculaba 1.593 y centraba el contenido fuera de la ventana. Se acotaron ambas columnas al espacio que reciben. Después, navegación y área útil coincidieron en 748 puntos; al reducir la ventana también coincidieron en 650. Se retiraron del código final las mediciones temporales, que solo registraban rectángulos.

**Revisión visual: PASS.** Sesión vacía y sesión guardada; cabecera, controles, título único, marca de PAIMON y firma visibles. Tamaños observados: 1.240 × 800, 1.440 × 870, 1.440 × 702 y 1.000 × 702 puntos, con barra de herramientas incluida. Se probaron el menú nativo de redimensionado, abrir/cancelar Contexto en tamaño pequeño y aumentar/reducir el divisor por accesibilidad. La proporción del divisor se conserva en SceneStorage. No se publicaron capturas de la conversación del usuario.

Esta corrección modifica únicamente la composición de la interfaz y su versión. La batería de 75 pruebas de los motores y la persistencia sigue siendo la referencia de 0.5.0; no se presenta como una nueva prueba de captura, reconocimiento o Gemini.

## Versión 0.5.0 (11)

**75 pruebas aprobadas**, con Swift 6 y el mismo M1 de referencia. Incluyen las 55 anteriores y cobertura de Google desactivado por defecto, consentimiento por sesión, compatibilidad de los valores locales anteriores, claves fuera de URL/cuerpo, consultas de conexión sin transcripción, JSON truncado y bloqueado, cuotas, tamaño máximo de respuesta, revocación en curso y durante lectura de la clave, referencias originales y rechazo de responsables o acuerdos no respaldados. También comprueban contexto acotado, identidad estable, reconstrucción al cambiar de motor/contexto, vista ejecutiva sin modificar hallazgos, términos con acentos, progreso persistido, importación con búferes de hasta 4.096 frames y conservación de finales al interrumpir. [Registro histórico](https://github.com/AD0441/PAIMON/blob/v0.5.1/docs/evidence/performance-tests.log).

**Importación nativa real: PASS.** `PAIMON_TEST_NATIVE_IMPORT=1 ./script/test.sh` leyó `Tests/Fixtures/spanish-synthetic.aiff` mediante AVAudioFile y SpeechAnalyzer, sin alimentación artificial a ritmo real, produjo texto definitivo en español y lo guardó en SQLite. Se comprobaron micrófonos, cotización y viernes. La batería completa terminó en 1,051 s en esta ejecución; no es una medición general de velocidad para grabaciones largas. En el ejecutor restringido no se podían consultar los idiomas del sistema; la misma prueba fuera de esa restricción pasó. No se descargaron recursos.

**Google AI:** pruebas de contrato con transporte y clave sintéticos; estas pruebas automatizadas no envían conversaciones ni usan credenciales del usuario. Un fallo HTTP 503 informado por el usuario motivó la regresión de recuperación: 503/502 seguidos de éxito, mismos datos POST, máximo tres intentos, Retry-After largo sin repetición temprana, cancelación al revocar la clave durante la espera y ningún reintento para 400/401/403/404/429. En la app instalada se observó posteriormente «Síntesis final actualizada», con la casilla de Google AI seleccionada y sin error pendiente. La clave fue configurada por el usuario; no se incluye contenido de esa sesión en las evidencias. Esto confirma la finalización observada, sin medir cuotas, latencia remota ni auditar la calidad semántica. Los dobles de transporte solo están en las pruebas. La aplicación implementa HTTPS al endpoint oficial. [Estrategia oficial de reintentos](https://ai.google.dev/gemini-api/docs/troubleshooting).

**Release: BUILD SUCCEEDED.** Instalación y firma estricta verificadas, incluidos ambos ZIP extraídos. La recompilación de 0.5.0 (11) conservó intacto el ZIP anterior 0.4.0 (10). [Verificación de 0.5.0](https://github.com/AD0441/PAIMON/blob/6583215/docs/evidence/performance-install-verification.json).

**Interfaz de contexto: PASS.** En Release se comprobaron abrir, cancelar un borrador, guardar y volver a abrir. El contexto aparece en una sheet separada y los controles de captura y los paneles permanecen visibles. ⌘N limpia la selección sin abrir otra ventana. Se usó un borrador sintético sin modificar la transcripción del usuario. La captura en vivo de 0.4.0 sigue siendo evidencia histórica; la importación de un archivo no se presenta como una nueva prueba de Core Audio.

## Publicación histórica · 0.5.1

La versión publicada en esa etapa fue [0.5.1 (12)](https://github.com/AD0441/PAIMON/releases/tag/v0.5.1). El ZIP publicado corresponde al paquete actual verificado, no a una nueva compilación de los motores. Se adjunta SHA-256 para comprobar su integridad. La firma sigue siendo ad hoc, sin Developer ID ni notarización. El icono y las dos imágenes adjuntas son recursos públicos existentes: las capturas mantienen su condición histórica de 0.4.0 y usan únicamente la muestra sintética. No se adjuntan sesiones privadas, credenciales ni pesos de modelos.

Google AI es una alternativa manual para evitar inferencia local del resumen cuando la RAM limita su uso; la protección actual aplaza todos los proveedores mientras detecta presión de memoria. No se ha medido un ahorro de RAM ni se valida un cambio automático de motor. Los resultados de las pruebas se conservan con su versión; la publicación de documentación no representa otra prueba de audio o inferencia.

## Entorno histórico · 0.5.x

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

## Diarización local · 10 de noviembre de 2026

PAIMON 0.7.1 (17) se compiló en Release arm64, se instaló en Aplicaciones y se comprobó el inicio del proceso. Se validó la firma estricta de los dos respaldos extraídos y la coincidencia del ejecutable del ZIP actual con el de Aplicaciones.

| Respaldo local | Versión | SHA-256 |
| --- | --- | --- |
| `PAIMON-actual.zip` | 0.7.1 (17) | `198bf49f499cf956c861eba958b54e05c8c1daa4aab6636033d2f8944330203f` |
| `PAIMON-anterior.zip` | 0.7.0 (16) | `8f4ec3949a460aeb253aca8dbef334ea94109c640be208166bffe95c3da7f7ad` |

- MacBook Pro M1 con 8 GB. Xcode compiló PAIMON Release arm64 y se verificó su firma local. Compiló también FluidWorker con FluidAudio v0.17.3 en modo Release.
- `PAIMON_TEST_NATIVE_IMPORT=1 ./script/test.sh` pasó 96 pruebas, incluidas importación con Apple Speech y audio sintético, activación y desactivación de la integración mediante un ejecutable de prueba, alineación temporal, separación de fuentes, nombres persistentes y borrado en cascada. Se comprobó la respuesta de FluidWorker real cuando faltan los modelos.
- Para reproducir la prueba pendiente con inferencia real, [prepara los modelos](DEPENDENCIES.md#diarización-local-opcional), activa **Separar voces** e importa un audio de prueba con al menos dos voces alternadas y turnos de varios segundos. Comprueba que una voz que reaparece conserva su etiqueta. Pulsa la etiqueta, guarda el nombre y vuelve a abrir la sesión. Después reproduce el mismo audio en otra aplicación y repite con captura del sistema, incluyendo una pausa y reanudación.
- Pendientes la precisión con dos o más voces, el retraso en captura real y la memoria adicional de Core ML. Las pruebas automáticas de etiquetas verifican la integración y usan respuestas deterministas.

## Descarga de modelos desde Ajustes · PAIMON 0.7.2 (18)

Xcode compiló Release arm64 y se verificó el inicio desde Aplicaciones. El ejecutable FluidWorker y su licencia están dentro del bundle firmado y del ZIP actual. Se verificó la firma de ambos ZIP extraídos.

`PAIMON_TEST_NATIVE_IMPORT=1 ./script/test.sh` pasó 97 pruebas. El instalador aceptó un archivo con el digest correcto, reutilizó una instalación íntegra y descartó una descarga alterada sin dejar restos. Las consultas de cabecera a ambos pesos y al aviso de atribución devolvieron HTTP 200. La descarga de los pesos queda a cargo del botón explícito en Ajustes.

| Respaldo local | Versión | SHA-256 |
| --- | --- | --- |
| `PAIMON-actual.zip` | 0.7.2 (18) | `040d10fcd2ddd9263d0d0f196f3eec4d0c23a66bf35a1d30e834f522b188523c` |
| `PAIMON-anterior.zip` | 0.7.1 (17) | `47ad0ffc3ded763b14a019dd5343f2177031dfb1c312b4abc612612b66913423` |
