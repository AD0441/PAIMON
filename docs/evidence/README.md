# Procedencia de las evidencias

Solo se publican resultados de diagnóstico y muestras sintéticas. Las capturas actuales de `../images` corresponden a PAIMON 0.6.0 en una instancia aislada; no muestran transcripciones privadas ni usan una simulación del reconocimiento o del resumen.

Se conservan cinco archivos de resultados y este índice:

| Archivo | Versión y alcance |
| --- | --- |
| `performance-tests.log` | 0.6.0: 84 pruebas, incluida importación nativa real |
| `performance-environment.json` | Entorno actual M1 de 8 GB, macOS 27.2 |
| `performance-install-verification.json` | 0.6.0: firma, dos paquetes, SHA-256, resumen nativo, revisión aislada y métricas |
| `performance-release-ui-validation.json` | Histórico 0.4.0: controles reales de captura y exportación |
| `performance-summary-recovery.json` | Histórico 0.4.0: recuperación de síntesis pendiente |

Las pruebas con dobles de motor verifican contratos y errores; no certifican hardware o inferencia. Los ensayos nativos se identifican por separado. Las métricas del cliente excluyen servicios de modelos de Apple. No hay prueba real de varias horas ni ejecución en macOS 26. La traza de Instruments permanece en una ubicación temporal y no se publica.

Los resultados reemplazados siguen en el historial de Git y sus tags; no se crean informes adicionales por cada compilación. Las imágenes e iconos se adjuntan a la release 0.6.0 para evitar depender del dominio raw de GitHub. Esto pertenece a la documentación y no añade conexiones de red a PAIMON.
