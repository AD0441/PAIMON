# PAIMON 0.4.0 — rendimiento y estabilidad

Trabajo realizado el 19 y 20 de octubre de 2026 sobre el proyecto existente. Se mantienen Core Audio Process Taps, SpeechTranscriber, Foundation Models, SwiftUI, barra de menús y procesamiento local. No se añadieron dependencias, modelos ni conexiones de red.

## Cambios verificables

- El coordinador serializa el trabajo, agrupa solicitudes pendientes y conserva la petición final al detener durante una actualización manual. Una finalización repetida sin contenido nuevo no vuelve a inferir.
- Las esperas de inferencia se pueden cancelar sin esperar a que termine quien ocupa la compuerta. Las generaciones activas usan cancelación cooperativa; no se fuerzan APIs privadas de descarga de modelos.
- SQLite v3 separa la transcripción, la memoria narrativa y el registro duradero de hallazgos. El límite de 80 elementos se aplica a la memoria del modelo. Las decisiones y tareas extraídas no desaparecen del informe al salir de esa memoria.
- Hechos y cursor se confirman juntos. La migración recorre snapshots antiguos en lotes y respeta la revisión más reciente y la plantilla. La eliminación de una sesión borra también registro, trabajos pendientes y métricas.
- La síntesis final considera memoria y hechos relevantes del comienzo y final de la sesión. El informe completo incluye todos los hallazgos registrados; la síntesis breve mantiene un contexto acotado.
- El exceso de contexto reduce el lote. Una respuesta fallida no confirma el cursor del bloque. Se usa `contextSize`; desde macOS 26.4 se cuentan tokens de prompt, instrucciones y esquema. En 26.0–26.3 se usa una estimación conservadora y se trata el error real del framework.
- El intervalo configurable se combina con volumen pendiente. Sin contenido nuevo no hay inferencia; con al menos 6.000 bytes puede adelantarse después de un minuto. La presión de memoria pospone el trabajo y conserva el final pendiente en disco para recuperarlo.
- La pantalla agrupa parciales y medidores cada 300 ms. Los definitivos se guardan inmediatamente. Una cola de texto llena espera hasta tres segundos antes de fallar visiblemente, en lugar de descartar un final sin informar.
- Páginas de 50 sesiones, 300 fragmentos y 120 hallazgos. Búsquedas del historial con espera de 300 ms. Exportaciones por páginas, negritas conservadas en Markdown/PDF y un único anexo de evidencias al final. El portapapeles genera el documento completo solo al solicitarlo.
- Mediciones en SQLite y signposts locales: duración, CPU del proceso cliente, footprint al terminar, contenido pendiente, lotes, reducciones y resultado. No incluyen transcripción, prompts, audio ni telemetría remota. Se retienen como máximo 2.000 mediciones.

## Entorno y alcance

Equipo de desarrollo Apple M1 con 8 GB; macOS 27.2 (26B5101f), Xcode 27.1. Compilación arm64 con destino mínimo macOS 26.0. Los ensayos ejecutados aquí no certifican macOS 26.0 ni el consumo total de los servicios de modelos de Apple.

## Pruebas automáticas

La referencia anterior tenía 35 pruebas. La batería ampliada contiene 55: audio, persistencia, FTS, formatos, citas, finalización simultánea, agrupación, cancelación, reducción de contexto, conservación de 160 decisiones, migración, trabajos finales tras reiniciar, historial Unicode, entrega de finales bajo contrapresión, recuperación de preferencias, reconstrucción del registro, cancelación global por memoria y dos regresiones de acuerdos y asuntos pendientes en español e inglés. [Referencia](evidence/performance-baseline-tests.log), [batería ampliada](evidence/performance-tests.log).

Rehacer desde la transcripción reemplaza el registro actual de esa plantilla después del primer lote válido; así también se pueden corregir hallazgos anteriores incorrectos. Si ese primer lote falla, el registro previo permanece. Los snapshots históricos se conservan, pero no se reimportan como hechos actuales tras reconstruir. Las actualizaciones incrementales ordinarias conservan los hechos antiguos.

```bash
./script/test.sh
```

Los dobles de motor de estas pruebas no se utilizan en la aplicación.

## Cargas largas aceleradas

[Resultados JSON](evidence/performance-long-sessions.json), [registro](evidence/performance-long-sessions.log). Se insertan seis fragmentos sintéticos por minuto representado, se aplican las políticas reales de actualización, se comprueban cursor y registro y se exporta el resultado. El motor del diagnóstico es determinista; no carga modelos ni captura audio. Por tanto, **240 minutos representados no son cuatro horas de ejecución real**.

| Minutos representados | Fragmentos y decisiones conservados/exportados | Tiempo del ensayo | Footprint final del cliente |
| --- | ---: | ---: | ---: |
| 10 | 60 | 0,09 s | 5,81 MB |
| 30 | 180 | 0,25 s | 6,67 MB |
| 60 | 360 | 0,60 s | 7,08 MB |
| 120 | 720 | 1,31 s | 7,97 MB |
| 240 | 1.440 | 2,57 s | 9,66 MB |

Todos terminaron sin fragmentos pendientes y con páginas dentro de sus límites. La memoria incluye el arnés de diagnóstico y la verificación JSON del exportado; no representa la aplicación con Speech y Foundation Models. No se extrapola batería ni latencia real de inferencia a partir de estos tiempos.

```bash
# Ejecutar después de compilar las pruebas:
"$TMPDIR/LocalAudioIntelligence-tests/out/Products/Debug/LAICheck" \
  --benchmark-long-sessions /tmp/paimon-long.json
```

## SQLite antes y después

Mismo ensayo con 1.200 fragmentos, 200 búsquedas y 200 escrituras concurrentes con esas búsquedas; bases temporales independientes y sin modelos.

| Medida | Antes | Después |
| --- | ---: | ---: |
| Búsqueda p95 | 2,60 ms | 2,55 ms |
| Escritura durante búsquedas p95 | 2,69 ms | 2,57 ms |
| Footprint final del cliente | 4,34 MB | 4,47 MB |

[Antes](evidence/performance-baseline-sqlite.json), [después](evidence/performance-after-sqlite.json). Son dos ejecuciones, sujetas a calentamiento y carga del sistema; no demuestran una mejora universal ni sustituyen un perfil de reunión real.

Se tomaron dos trazas reales de Instruments Time Profiler de diez segundos en reposo: [antes](evidence/performance-idle-before-instruments.log), [después](evidence/performance-idle-after-instruments.log), [estadísticas iniciales](evidence/performance-idle-before-stats.json), [estadísticas finales](evidence/performance-idle-after-stats.json). Las trazas originales están en `/tmp/paimon-idle-before-20261019.trace` y `/tmp/paimon-idle-after-20261019.trace`, con permisos privados; no se incorporan porque contienen metadatos del entorno. El número de filas de muestreo no equivale a porcentaje de CPU ni demuestra el consumo durante captura.

## Modelo real y audio real

La validación del modelo de Apple usa doce fragmentos sintéticos sobre catálogo, microscopios y calendario. Comprueba síntesis general, cobertura de los tres temas, citas originales y exclusión del saludo final. [Resultado](evidence/performance-native-summary.json), [informe](evidence/performance-native-summary.md). El footprint informado pertenece al cliente; excluye los servicios de modelos del sistema.

SpeechTranscriber real volvió a transcribir el archivo de voz sintética: un segmento definitivo completo, 10,50 s de tiempo total con alimentación a ritmo real, 0,22 s de CPU y 20,06 MB de RSS máximo del cliente. [Resultado](evidence/performance-file-asr.json), [texto reconocido](evidence/performance-file-asr.log). Este ensayo lee un archivo; no valida por sí solo el process tap.

Para repetir la captura real se usa `script/validate_local_audio.sh`: reproduce una voz sintética local, captura solo el propio bundle mediante Core Audio y transcribe con SpeechTranscriber. Requiere una sesión de macOS desbloqueada y permiso de audio del sistema. El estado de la repetición de esta versión se documenta en [VALIDATION.md](VALIDATION.md); una compilación exitosa o una prueba de texto no cuentan como captura validada.

Las primeras repeticiones esperaron en Core Audio y terminaron sin búferes. Se conservan los [fallos](evidence/performance-capture-repeat.json) y el [diagnóstico de firma](evidence/performance-capture-permission-mismatch.json): el interruptor de permiso estaba activado, pero TCC rechazaba el requisito de una compilación con firma ad hoc distinta. Tras renovar el permiso con autorización del usuario y mantener el mismo binario, **la cadena completa real pasó en build 9**: 1.052 búferes, 538.624 frames, 769 búferes con señal, un segmento definitivo y cinco hallazgos, búsqueda y marcador persistidos. Preparación 0,41 s y captura 11,33 s; no se guardó audio. Footprint final del cliente 64,19 MB, sin incluir los servicios de Apple. [Resultado](evidence/performance-capture-validation.json), [sesión sintética](evidence/performance-capture-validation.session.json).

La revisión visual de ese resumen detectó un asunto pendiente presentado como acuerdo. Build 10 añade una comprobación por frase y procesamiento Apple v3; se verificó con dos regresiones y Foundation Models real. Tras una tentativa interrumpida por bloqueo de pantalla, se comprobó Release instalada con audio real: texto parcial y definitivo correcto, pausa, reanudación, detención y JSON exportado desde la interfaz. Una sesión de 25,07 s dejó un único fragmento, sin duplicados ni captura activa. [Comprobaciones](evidence/performance-release-ui-validation.json).

En esa repetición, macOS señaló presión de memoria real (nivel 2). La transcripción se conservó y el resumen final quedó como trabajo pendiente en SQLite; no se forzó la inferencia ni se cerraron apps del usuario. Posteriormente se verificó el resultado final v3 con cinco hallazgos y la cola vacía, y se revisaron el resumen y sus citas en Release instalada. El disparador exacto de recuperación y la transición de presión no se registraron de forma independiente; el indicador global seguía en nivel 2 en la comprobación posterior. [Resultado posterior](evidence/performance-summary-recovery.json), [estado y alcance](evidence/performance-capture-status.json).

El diagnóstico ahora copia la muestra a una carpeta temporal para evitar pedir acceso de PAIMON al Escritorio. Su tarea pertenece al modelo de la app, y respalda/restaura las preferencias incluso tras una interrupción. La finalización del motor cancela explícitamente el flujo de resultados si falla la finalización del analizador; una tarea cancelada no debe dejarlo esperando indefinidamente.

`./script/open_audio_fixture.sh` prepara un reproductor de voz sintética independiente, sin permisos de captura. Permite comprobar los botones de Release eligiendo únicamente **PAIMON Audio Fixture** como fuente. No modifica ni recompila PAIMON; así evita cambiar su firma después de conceder el permiso. No reproduce nada hasta pulsar **Reproducir muestra**.

## Comprobación prolongada pendiente

Repetir con audio autorizado durante 30, 60, 120 y 240 minutos, primero solo sistema y después sistema/micrófono con audífonos. Registrar con Instruments Time Profiler, Allocations, Audio System Trace y Foundation Models. Revisar crecimiento sostenido, recursos de procesos de modelos, huecos de captura, latencia de finales y resúmenes, estado térmico, bloqueo de pantalla y desconexión de dispositivos. No se induce presión global artificial en el Mac de uso diario.

Las preguntas y compromisos antiguos pueden necesitar conciliación humana cuando una intervención posterior los modifica. El registro preserva las afirmaciones extraídas y su evidencia; no garantiza una resolución semántica perfecta ni que se extraiga cada hecho del audio. El portapapeles crea un documento completo y su coste crece con los hallazgos seleccionados; las exportaciones permanecen paginadas.

APIs verificadas en el SDK instalado y en la documentación oficial: [gestión del contexto](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), [contextSize](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize), [rendimiento de SwiftUI](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance).
