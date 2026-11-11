# Revisión inteligente · PAIMON 0.13.0

Pulsa **Revisar transcripción** en una sesión terminada. Elige **Ortografía y puntuación**, **Contexto y terminología** o **Revisión completa**. Apple Intelligence trabaja localmente con el texto objetivo, hasta dos fragmentos anteriores y posteriores de la misma fuente, y el objetivo, temario y glosario de la sesión.

Cada propuesta muestra la expresión original, el reemplazo, su categoría y el motivo. Puedes aceptarla, rechazarla, abrir la transcripción o escuchar el fragmento si existe audio. Las propuestas ambiguas pueden pedir revisar el audio sin inventar un reemplazo. No se aplica nada automáticamente.

**Aceptar propuestas de bajo riesgo** se limita a la página visible y a puntuación o mayúsculas que conservan las palabras y los datos protegidos. Las tildes, los nombres y la terminología requieren aceptación individual. Se rechazan referencias inexistentes, citas ambiguas, propuestas superpuestas y cambios en cifras, separadores numéricos, unidades simbólicas o negaciones detectadas. Estas reglas no garantizan que toda sugerencia aceptable conserve el significado: la revisión humana sigue siendo necesaria.

El servicio divide los textos largos, consulta el presupuesto de contexto oficial y utiliza solicitudes independientes con salida estructurada. No envía transcripciones completas. Reutiliza InferenceGate; la captura, los resúmenes activos o la presión de memoria interrumpen la revisión desde su interfaz. Admite cancelación y conserva las propuestas ya verificadas.

SQLite guarda las propuestas, sus estados, la versión de revisión y el texto base necesario para validar la aceptación. No guarda los prompts. Una huella de texto, vecinos, modo y contexto evita repetir la inferencia para fragmentos ya revisados. La aceptación comprueba que no haya ediciones manuales posteriores; varias propuestas del mismo lote se aplican sin perder las anteriores.

Las correcciones usan el mecanismo existente de originalText y revisión de la transcripción. No cambian identificadores, tiempos ni hablantes. Los resúmenes dependientes se marcan para actualizar; sus evidencias históricas no se reescriben silenciosamente. La búsqueda y el Asistente usan la revisión vigente.

La exportación permite elegir **Exportar texto original sin correcciones** en TXT, Markdown, PDF y JSON. El original sigue disponible tras aceptar propuestas. Eliminar la sesión borra también las sugerencias y los puntos de control mediante claves foráneas con eliminación en cascada.

La primera implementación utiliza exclusivamente Apple Foundation Models. Si Apple Intelligence o el idioma no están disponibles, se informa en la interfaz. No descarga otro LLM ni utiliza Google AI para revisar.
