# Procedencia de las evidencias

Los resultados corresponden a pruebas locales del proyecto. Los textos y audios incluidos son muestras sintéticas de diagnóstico; no se incluyen conversaciones privadas del usuario. Las capturas de `../images` muestran una sesión de esa misma muestra en la aplicación real. Únicamente se retiró el margen vacío exterior a la ventana.

Antes de subir el proyecto a GitHub se sustituyeron las rutas personales de los registros por `$PROJECT_ROOT`, `$USER_HOME` y `$TMPDIR`. Los registros originales se conservaron en un respaldo temporal local. Esta limpieza no cambia los resultados, tiempos, versiones ni recuentos medidos.

Las pruebas automáticas usan dobles de motor y no certifican por sí solas la captura o la inferencia reales. Los archivos de resultados indican qué backend y qué alcance se comprobaron. Una prueba acelerada de 240 minutos representados no es una reunión real de cuatro horas. Las métricas del proceso cliente excluyen los servicios de modelos de Apple.

Se conservan localmente solo cinco resultados de referencia: pruebas, entorno, instalación, controles históricos de captura y recuperación del resumen. Los registros anteriores están en el [historial de v0.4.0](https://github.com/AD0441/PAIMON/tree/v0.4.0/docs/evidence); las copias locales retiradas se enviaron a la Papelera. Las pruebas corresponden a 0.5.0 y la instalación y revisión de dimensiones a 0.5.1; los controles de captura y recuperación conservan su versión 0.4.0 indicada dentro del archivo. La comprobación de Google registra solo estados de interfaz, sin transcripción, clave ni solicitud. No se generan informes adicionales por cada limpieza.
