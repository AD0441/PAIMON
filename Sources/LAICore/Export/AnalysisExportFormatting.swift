import Foundation

enum AnalysisExportFormatting {
    static var metadata: [String: Any] {
        ["polarity": "For text.version>=2: interpretive ordinal index, not a probability. Neutral=0; mixed/uncertain/unexamined=null. Version1 preserves original NaturalLanguage scores.",
         "strength": ["mild":1.0/3,"clear":2.0/3,"strong":1.0],
         "units": ["times":"seconds in session","level":"dBFS","pitch":"Hz","distance":"1 - cosine similarity"],
         "vocalEmotionCategories": Dictionary(uniqueKeysWithValues:VocalEmotion.allCases.map{(String($0.rawValue),$0.title)}),
         "vocalEmotionScores": "Experimental model output; not a psychological diagnosis or calibrated probability.",
         "storedRawEmbeddings": false]
    }

    static func number(_ value: Double?) -> String {
        value.map { String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),$0) } ?? "Sin puntuación"
    }
    static func sentiments(_ saved: SavedSentiment?) -> [String] {
        guard let saved else { return ["No hay análisis textual guardado."] }
        var rows=["Motor: "+saved.engine+" · versión "+String(saved.version),
                  "Fragmentos evaluados: "+String(saved.report.tagged)+" de "+String(saved.report.points.count)]
        if !saved.matchesCurrentTranscript { rows.append("Análisis anterior a una modificación de la transcripción.") }
        if saved.version < 2 { rows.append("Puntuaciones originales de NaturalLanguage; este análisis aún no usa la revisión local de neutralidad.") }
        for point in saved.report.points {
            let time=point.time.map(timestamp) ?? "Fragmento "+String(point.id+1)
            rows.append(time+" · "+point.segmentID+" · polaridad: "+number(point.score)+" · original NaturalLanguage: "+number(point.rawAppleScore ?? (saved.version<2 ? point.score:nil)))
            if let value=point.polarity { rows.append("Clasificación: "+value.title) }
            if let strength=point.strength { rows.append("Intensidad ordinal: "+strength.title) }
            if let speaker=point.speaker { rows.append("Hablante: "+speaker) }
            if !point.emotions.isEmpty { rows.append("Emociones expresadas: "+point.emotions.joined(separator:", ")) }
            if !point.context.isEmpty { rows.append("Contexto: "+point.context.joined(separator:", ")) }
            if let quote=point.polarityEvidence { rows.append("Cita de valoración: «"+quote+"»") }
            rows.append(point.excerpt)
        }
        return rows
    }
    static func vocal(_ saved: SavedVocalAnalysis) -> [String] {
        var rows=["Fuente: "+saved.source.title+" · análisis guardado: "+saved.updated.formatted()]
        for point in saved.measurements ?? [] {
            rows.append(timestamp(point.start)+" – "+timestamp(point.end)+" · nivel dBFS: "+number(point.level)+" · altura Hz: "+number(point.pitch)+" · variación Hz: "+number(point.pitchVariation)+" · nivel bajo s: "+number(point.quietSeconds)+" / "+number(point.measuredSeconds))
        }
        if let report=saved.emotions {
            rows.append("Modelo: "+report.model.title+" · "+report.artifactIdentifier+" · muestreo: "+String(report.sampled))
            for point in report.points {
                rows.append(timestamp(point.start)+" – "+timestamp(point.end)+" · estimación vocal: "+(point.emotion?.title ?? "Sin etiqueta")+" · puntuación del modelo: "+number(point.confidence))
            }
        }
        for distance in saved.distances ?? [] {
            rows.append(timestamp(distance.from)+" → "+timestamp(distance.to)+" · distancia de patrones vocales: "+number(distance.distance))
        }
        if let report=saved.sounds {
            rows.append("Sonidos seleccionados: "+(saved.soundIdentifiers ?? []).joined(separator:", ")+" · límite alcanzado: "+String(report.limited))
            for event in report.events { rows.append(timestamp(event.start)+" – "+timestamp(event.end)+" · "+event.kind.title+" · "+event.kind.rawValue) }
        }
        return rows
    }
    static func live(_ points: [LiveVocalResult]) -> [String] {
        points.flatMap { point -> [String] in
            var rows=[point.source.title+" · "+timestamp(point.start)+" – "+timestamp(point.end)+" · nivel dBFS: "+number(point.level)+" · altura Hz: "+number(point.pitch)+" · nivel bajo %: "+number(point.quietPercent),
                "Modelo: "+(point.modelIdentifier ?? "Sin modelo emocional")+" · estimación: "+(point.emotion?.title ?? "Sin etiqueta")+" · puntuación: "+number(point.score)+" · inferencia omitida: "+String(point.deferred)]
            if let distance=point.distanceFromPrevious { rows.append("Distancia respecto a la muestra anterior: "+number(distance)) }
            rows += point.sounds.map { timestamp($0.start)+" – "+timestamp($0.end)+" · "+VocalSoundAnalysis.categoryName($0.identifier) }
            return rows
        }
    }
    static func assistant(_ turns: [AssistantTurn], revision: Int64, evidence: Bool) -> [String] {
        turns.flatMap { turn -> [String] in
            var rows=["Pregunta · "+turn.created.formatted()+": "+turn.question,
                      "Respuesta: "+(turn.reply.text ?? "No se encontró respuesta respaldada en los fragmentos consultados.")]
            if turn.transcriptRevision != revision { rows.append("Respuesta guardada antes de modificar la transcripción; revisa sus citas.") }
            if turn.reply.sampled { rows.append("Se consultó una selección de la transcripción.") }
            if evidence { rows += turn.reply.evidence.map { "["+timestamp($0.start)+"] «"+$0.quote+"» · "+$0.segmentID } }
            return rows
        }
    }
}
