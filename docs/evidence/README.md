# Procedencia de las evidencias

Este directorio reúne evidencias históricas con alcances distintos, junto con validaciones más recientes de la compilación 31. Las capturas de `../images` son muestras sintéticas de versiones anteriores; no muestran transcripciones privadas. Los registros de muestras sintéticas y las comprobaciones sobre el equipo se identifican por separado; ninguno debe leerse como prueba de precisión general.

| Archivo | Versión y alcance |
| --- | --- |
| `performance-tests.log` | Histórico 0.6.0: 84 pruebas, incluida importación nativa real |
| `performance-environment.json` | Registro de entorno M1 de 8 GB, macOS 27.2 |
| `performance-install-verification.json` | Histórico 0.6.0: firma, dos paquetes, SHA-256, resumen nativo, revisión aislada y métricas |
| `performance-release-ui-validation.json` | Histórico 0.4.0: controles reales de captura y exportación |
| `performance-summary-recovery.json` | Histórico 0.4.0: recuperación de síntesis pendiente |
| `discourse-live-validation.json` | 0.14.0: evidencia de análisis de discurso incremental y voz durante la captura |
| `polarity-export-validation.json` | 0.15.0: polaridad contextual, exportación y memoria; incluye casos de prueba sintéticos y resultados de validación identificados por alcance |

Las pruebas con dobles de motor verifican contratos y errores; no certifican hardware o inferencia. Los ensayos nativos se identifican por separado. Los casos sintéticos de polaridad comprueban comportamientos seleccionados, no la precisión general. Las métricas del cliente excluyen servicios de modelos de Apple. No hay prueba real de varias horas ni ejecución en macOS 26. La traza de Instruments permanece en una ubicación temporal y no se publica.

Los resultados reemplazados siguen en el historial de Git y sus tags; no se crean informes adicionales por cada compilación. Las evidencias históricas mantienen su versión y alcance originales; las nuevas no sustituyen registros previos ni implican que todas las imágenes correspondan a la versión actual. Este índice pertenece a la documentación y no añade conexiones de red a PAIMON.
