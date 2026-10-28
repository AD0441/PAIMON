import Foundation
import CSQLite
import CryptoKit
public actor SessionStore {
    private let db: OpaquePointer
    public let directory: URL
    public init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalAudioIntelligence", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var connection: OpaquePointer?
        guard sqlite3_open_v2(self.directory.appendingPathComponent("sessions.sqlite").path, &connection, SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX, nil)==SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw LAIError.message("No se pudo abrir SQLite")
        }
        db=connection
        sqlite3_busy_timeout(connection, 3000)
        sqlite3_create_function_v2(connection,"lai_contains",2,SQLITE_UTF8|SQLITE_DETERMINISTIC,nil,{ context,_,values in
            guard let values,let a=sqlite3_value_text(values[0]),let b=sqlite3_value_text(values[1]) else { sqlite3_result_int(context,0); return }
            sqlite3_result_int(context,String(cString:a).range(of:String(cString:b),options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"es")) != nil ? 1:0)
        },nil,nil,nil)
        let schema="""
        PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA secure_delete=ON;
        CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY, created REAL NOT NULL, data TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS segments(seq INTEGER PRIMARY KEY AUTOINCREMENT, session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, id TEXT NOT NULL, start REAL NOT NULL, data TEXT NOT NULL, UNIQUE(session,id));
        CREATE INDEX IF NOT EXISTS segments_session ON segments(session,seq);
        CREATE TABLE IF NOT EXISTS summaries(seq INTEGER PRIMARY KEY AUTOINCREMENT, session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, data TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS summaries_session ON summaries(session,seq);
        CREATE INDEX IF NOT EXISTS sessions_created ON sessions(created DESC,id);
        CREATE TABLE IF NOT EXISTS findings(session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, template TEXT NOT NULL, key TEXT NOT NULL, kind TEXT NOT NULL, anchor TEXT NOT NULL, start REAL NOT NULL, data TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(session,template,key));
        CREATE INDEX IF NOT EXISTS findings_page ON findings(session,template,kind,start,key);
        CREATE INDEX IF NOT EXISTS findings_anchor ON findings(session,template,kind,anchor);
        CREATE TABLE IF NOT EXISTS finding_import(snapshot INTEGER PRIMARY KEY REFERENCES summaries(seq) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS summary_metrics(id TEXT PRIMARY KEY,session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,created REAL NOT NULL,data TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS summary_metrics_session ON summary_metrics(session,created);
        CREATE TABLE IF NOT EXISTS summary_final_jobs(session TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS bookmarks(id TEXT PRIMARY KEY, session TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE, time REAL NOT NULL, data TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS bookmarks_session_time ON bookmarks(session,time,id);
        CREATE INDEX IF NOT EXISTS segments_session_time ON segments(session,start);
        CREATE VIRTUAL TABLE IF NOT EXISTS transcript_search USING fts5(text, tokenize='unicode61 remove_diacritics 2', prefix='2 3');
        INSERT INTO transcript_search(transcript_search,rank) VALUES('secure-delete',1);
        CREATE TRIGGER IF NOT EXISTS segment_search_insert AFTER INSERT ON segments BEGIN
          INSERT INTO transcript_search(rowid,text) VALUES(new.seq,json_extract(new.data,'$.text'));
        END;
        CREATE TRIGGER IF NOT EXISTS segment_search_update AFTER UPDATE OF data ON segments BEGIN
          DELETE FROM transcript_search WHERE rowid=old.seq;
          INSERT INTO transcript_search(rowid,text) VALUES(new.seq,json_extract(new.data,'$.text'));
        END;
        CREATE TRIGGER IF NOT EXISTS segment_search_delete AFTER DELETE ON segments BEGIN
          DELETE FROM transcript_search WHERE rowid=old.seq;
        END;
        CREATE TABLE IF NOT EXISTS search_backfill(id INTEGER PRIMARY KEY CHECK(id=1),cursor INTEGER NOT NULL,watermark INTEGER NOT NULL);
        INSERT OR IGNORE INTO search_backfill SELECT 1,0,COALESCE(MAX(seq),0) FROM segments;
        PRAGMA user_version=3;
        """
        guard sqlite3_exec(connection,schema,nil,nil,nil)==SQLITE_OK else { sqlite3_close(connection); throw LAIError.message("No se pudo crear la base de datos") }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.directory.appendingPathComponent("sessions.sqlite").path)
    }
    isolated deinit { sqlite3_close(db) }
    private func statement(_ sql: String, values: [String] = []) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&s,nil)==SQLITE_OK, let s else { throw failure() }
        for (i,v) in values.enumerated() {
            let result=v.withCString { sqlite3_bind_text(s,Int32(i+1),$0,-1,unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            if result != SQLITE_OK { sqlite3_finalize(s); throw failure() }
        }; return s
    }
    private func failure() -> LAIError { .message("SQLite: \(String(cString:sqlite3_errmsg(db)))") }
    private func encode<T: Encodable>(_ value: T) throws -> String { String(decoding:try JSONEncoder().encode(value),as:UTF8.self) }
    private func decode<T: Decodable>(_ type: T.Type, _ s: OpaquePointer, _ col: Int32 = 0) throws -> T {
        guard let p=sqlite3_column_text(s,col) else { throw failure() }; return try JSONDecoder().decode(type,from:Data(String(cString:p).utf8))
    }
    private func write(_ sql: String, _ values: [String]) throws {
        let s=try statement(sql,values:values); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s)==SQLITE_DONE else { throw failure() }
    }
    public func save(_ session: Session) throws { try write("INSERT INTO sessions(id,created,data) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET created=excluded.created,data=excluded.data",[session.id.uuidString,String(session.created.timeIntervalSince1970),try encode(session)]) }
    public func append(_ segment: TranscriptSegment) throws {
        guard segment.isFinal else { return }
        try write("INSERT INTO segments(session,id,start,data) VALUES(?,?,?,?) ON CONFLICT(session,id) DO UPDATE SET data=excluded.data,start=excluded.start",[segment.sessionID.uuidString,segment.id,String(segment.start),try encode(segment)])
    }
    public func session(id:UUID) throws -> Session? {
        let s=try statement("SELECT data FROM sessions WHERE id=?",values:[id.uuidString]); defer { sqlite3_finalize(s) }
        return sqlite3_step(s)==SQLITE_ROW ? try decode(Session.self,s):nil
    }
    public func sessions(search: String = "",limit:Int=50,offset:Int=0) throws -> [Session] {
        let s=try statement("SELECT data FROM sessions WHERE (?='' OR lai_contains(json_extract(data,'$.title'),?)) ORDER BY created DESC,id LIMIT ? OFFSET ?",values:[search,search,String(max(1,min(200,limit))),String(max(0,offset))]); defer { sqlite3_finalize(s) }
        var result:[Session]=[]
        while sqlite3_step(s)==SQLITE_ROW { result.append(try decode(Session.self,s)) }; return result
    }
    public func recoverInterrupted() throws {
        let s=try statement("SELECT data FROM sessions WHERE json_extract(data,'$.status') IN ('recording','paused','importing')"); defer { sqlite3_finalize(s) }
        while sqlite3_step(s)==SQLITE_ROW { var session=try decode(Session.self,s); session.status="interrupted"; try save(session) }
    }
    public func segments(session: UUID, after: Int64 = 0, limit: Int = 200, search: String = "", newest: Bool = false, before: Int64 = Int64.max) throws -> [(Int64,TranscriptSegment)] {
        let order=newest ? "DESC" : "ASC"
        let s=try statement("SELECT seq,data FROM segments WHERE session=? AND seq>? AND seq<? AND (?='' OR lai_contains(json_extract(data,'$.text'),?)) ORDER BY seq \(order) LIMIT ?",values:[session.uuidString,String(after),String(before),search,search,String(limit)])
        defer { sqlite3_finalize(s) }; var result:[(Int64,TranscriptSegment)]=[]
        while sqlite3_step(s)==SQLITE_ROW { result.append((sqlite3_column_int64(s,0),try decode(TranscriptSegment.self,s,1))) }; return newest ? result.reversed() : result
    }
    public func processingProgress(session:UUID) throws -> SessionProcessingProgress {
        let snapshot=try latestSummary(session:session)
        var result=SessionProcessingProgress()
        let s=try statement("SELECT MAX(CAST(json_extract(data,'$.end') AS REAL)),MAX(CASE WHEN seq<=? THEN CAST(json_extract(data,'$.end') AS REAL) ELSE 0 END),SUM(CASE WHEN seq>? AND json_extract(data,'$.duplicateOf') IS NULL THEN 1 ELSE 0 END) FROM segments WHERE session=?",values:[String(snapshot?.throughRow ?? 0),String(snapshot?.throughRow ?? 0),session.uuidString])
        defer { sqlite3_finalize(s) }
        if sqlite3_step(s)==SQLITE_ROW {
            result.transcribedThrough=sqlite3_column_double(s,0)
            result.summarizedThrough=sqlite3_column_double(s,1)
            result.pendingSegments=Int(sqlite3_column_int64(s,2))
        }
        result.isFinal=snapshot?.isFinal==true && result.pendingSegments==0
        return result
    }
    /// Facts and the cursor commit together. A failed generation never advances either.
    public func save(_ snapshot: SummarySnapshot,additionalFindings:[Finding]=[],replaceRegister:Bool=false) throws {
        guard sqlite3_exec(db,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else { throw failure() }
        do {
            if replaceRegister {
                let template=(snapshot.summaryTemplate ?? .meeting).rawValue
                try write("DELETE FROM findings WHERE session=? AND template=?",[snapshot.sessionID.uuidString,template])
                // Keep historical snapshots, but do not re-import obsolete
                // findings after an explicit rebuild or processing upgrade.
                try write("INSERT OR IGNORE INTO finding_import(snapshot) SELECT seq FROM summaries WHERE session=? AND COALESCE(json_extract(data,'$.summaryTemplate'),'meeting')=?",[snapshot.sessionID.uuidString,template])
            }
            try write("INSERT INTO summaries(session,data) VALUES(?,?)",[snapshot.sessionID.uuidString,try encode(snapshot)])
            let seq=sqlite3_last_insert_rowid(db)
            try importFindings(snapshot.findings+additionalFindings,session:snapshot.sessionID,template:snapshot.summaryTemplate ?? .meeting,revision:seq)
            try write("INSERT INTO finding_import(snapshot) VALUES(?)",[String(seq)])
            if snapshot.isFinal { try completeFinalSummary(session:snapshot.sessionID) }
            guard sqlite3_exec(db,"COMMIT",nil,nil,nil)==SQLITE_OK else { throw failure() }
        } catch { sqlite3_exec(db,"ROLLBACK",nil,nil,nil); throw error }
    }
    private func importFindings(_ values:[Finding],session:UUID,template:SummaryTemplate,revision:Int64) throws {
        for value in values where value.kind != .topic && value.kind != .overview {
            let anchor=try statement("SELECT data,key FROM findings WHERE session=? AND template=? AND kind=? AND anchor=?",values:[session.uuidString,template.rawValue,value.kind.rawValue,value.segmentID])
            defer { sqlite3_finalize(anchor) }
            var existingKey:String?
            while sqlite3_step(anchor)==SQLITE_ROW {
                let prior=try decode(Finding.self,anchor)
                if prior.id==value.id || EvidenceValidator.merge(previous:[prior],new:[value]).count==1,let key=sqlite3_column_text(anchor,1) { existingKey=String(cString:key); break }
            }
            let fingerprint=value.kind.rawValue+"|"+value.segmentID+"|"+SummaryGrounding.words(value.text).sorted().joined(separator:" ")+"|"+(value.owner ?? "")+"|"+(value.due ?? "")
            let key=existingKey ?? SHA256.hash(data:Data(fingerprint.utf8)).map{String(format:"%02x",$0)}.joined()
            // An old snapshot imported later must not overwrite a newer phrasing.
            try write("INSERT INTO findings(session,template,key,kind,anchor,start,data,revision) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(session,template,key) DO UPDATE SET data=excluded.data,revision=excluded.revision WHERE excluded.revision>findings.revision",[session.uuidString,template.rawValue,key,value.kind.rawValue,value.segmentID,String(value.start),try encode(value),String(revision)])
        }
    }
    /// Small resumable migration of historical snapshots, including facts evicted by older apps.
    public func indexNextFindingBatch(session:UUID?=nil,limit:Int=12) throws -> Bool {
        let query="SELECT s.seq,s.data FROM summaries s LEFT JOIN finding_import i ON i.snapshot=s.seq WHERE i.snapshot IS NULL"+(session == nil ? "":" AND s.session=?")+" ORDER BY s.seq LIMIT ?"
        let values=(session.map{[$0.uuidString]} ?? [])+[String(max(1,min(20,limit)))]
        let s=try statement(query,values:values)
        defer { sqlite3_finalize(s) }
        var rows:[(Int64,SummarySnapshot)]=[]
        while sqlite3_step(s)==SQLITE_ROW { rows.append((sqlite3_column_int64(s,0),try decode(SummarySnapshot.self,s,1))) }
        guard !rows.isEmpty else { return true }
        guard sqlite3_exec(db,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else { throw failure() }
        do {
            // Newer versions win if two snapshots describe the same fact.
            for (seq,snapshot) in rows.reversed() {
                try importFindings(snapshot.findings,session:snapshot.sessionID,template:snapshot.summaryTemplate ?? .meeting,revision:seq)
                try write("INSERT OR IGNORE INTO finding_import(snapshot) VALUES(?)",[String(seq)])
            }
            guard sqlite3_exec(db,"COMMIT",nil,nil,nil)==SQLITE_OK else { throw failure() }
        } catch { sqlite3_exec(db,"ROLLBACK",nil,nil,nil); throw error }
        return false
    }
    public func findings(session:UUID,template:SummaryTemplate,kind:FindingKind?=nil,kinds:[FindingKind]=[],limit:Int=120,offset:Int=0) throws -> [Finding] {
        let filter=kind.map{[$0]} ?? Array(Set(kinds))
        let clause=filter.isEmpty ? "":" AND kind IN ("+filter.map{_ in "?"}.joined(separator:",")+")"
        let s=try statement("SELECT data FROM findings WHERE session=? AND template=?"+clause+" ORDER BY start,key LIMIT ? OFFSET ?",values:[session.uuidString,template.rawValue]+filter.map(\.rawValue)+[String(max(1,min(200,limit))),String(max(0,offset))])
        defer { sqlite3_finalize(s) }; var result:[Finding]=[]
        while sqlite3_step(s)==SQLITE_ROW { result.append(try decode(Finding.self,s)) }; return result
    }
    /// A bounded view; the complete register stays on disk and is paged for export.
    public func reportFindings(session:UUID,template:SummaryTemplate,offset:Int=0) throws -> [Finding] {
        let memory=try latestSummary(session:session)?.findings.filter{$0.kind == .topic || $0.kind == .overview} ?? []
        return memory+(try findings(session:session,template:template,limit:120,offset:offset))
    }
    public func finalContext(session:UUID,template:SummaryTemplate) throws -> [Finding] {
        var result:[Finding]=[]
        for kind in [FindingKind.decision,.task,.question,.concept] {
            let s=try statement("SELECT data FROM findings WHERE session=? AND template=? AND kind=? ORDER BY start,key",values:[session.uuidString,template.rawValue,kind.rawValue])
            defer { sqlite3_finalize(s) }
            // Keep early and recent commitments, without materializing the full register.
            var first:[Finding]=[],last:[Finding]=[]
            while sqlite3_step(s)==SQLITE_ROW {
                let finding=try decode(Finding.self,s)
                if first.count<3 { first.append(finding) } else { last.append(finding); if last.count>3 { last.removeFirst() } }
            }
            result += first+last
        }
        return result
    }
    public func pendingContent(session:UUID,after:Int64) throws -> PendingSummaryContent {
        let s=try statement("SELECT COUNT(*),COALESCE(SUM(length(CAST(json_extract(data,'$.text') AS BLOB))),0) FROM segments WHERE session=? AND seq>? AND json_extract(data,'$.duplicateOf') IS NULL",values:[session.uuidString,String(after)])
        defer { sqlite3_finalize(s) }; guard sqlite3_step(s)==SQLITE_ROW else { return .init() }
        return .init(segments:Int(sqlite3_column_int64(s,0)),bytes:Int(sqlite3_column_int64(s,1)))
    }
    public func requestFinalSummary(session:UUID) throws {
        try write("INSERT OR IGNORE INTO summary_final_jobs(session,created) VALUES(?,?)",[session.uuidString,String(Date().timeIntervalSince1970)])
    }
    public func completeFinalSummary(session:UUID) throws { try write("DELETE FROM summary_final_jobs WHERE session=?",[session.uuidString]) }
    public func pendingFinalSession() throws -> Session? {
        let s=try statement("SELECT s.data FROM summary_final_jobs j JOIN sessions s ON s.id=j.session ORDER BY j.created LIMIT 1"); defer { sqlite3_finalize(s) }
        return sqlite3_step(s)==SQLITE_ROW ? try decode(Session.self,s):nil
    }
    public func save(_ metrics:SummaryRunMetrics) throws {
        try write("INSERT INTO summary_metrics(id,session,created,data) VALUES(?,?,?,?)",[metrics.id.uuidString,metrics.sessionID.uuidString,String(metrics.created.timeIntervalSince1970),try encode(metrics)])
        try write("DELETE FROM summary_metrics WHERE id IN (SELECT id FROM summary_metrics ORDER BY created DESC LIMIT -1 OFFSET 2000)",[])
    }
    public func summaryMetrics(session:UUID) throws -> [SummaryRunMetrics] {
        let s=try statement("SELECT data FROM summary_metrics WHERE session=? ORDER BY created DESC LIMIT 200",values:[session.uuidString]); defer { sqlite3_finalize(s) }; var result:[SummaryRunMetrics]=[]
        while sqlite3_step(s)==SQLITE_ROW { result.append(try decode(SummaryRunMetrics.self,s)) }; return result
    }
    public func segmentWindow(session:UUID,segmentID:String) throws -> [(Int64,TranscriptSegment)] {
        let s=try statement("SELECT seq FROM segments WHERE session=? AND id=?",values:[session.uuidString,segmentID]); defer { sqlite3_finalize(s) }
        guard sqlite3_step(s)==SQLITE_ROW else { return [] }
        let anchor=sqlite3_column_int64(s,0)
        return try segments(session:session,limit:150,newest:true,before:anchor+1)+segments(session:session,after:anchor,limit:150)
    }
    public func latestSummary(session: UUID) throws -> SummarySnapshot? {
        let s=try statement("SELECT data FROM summaries WHERE session=? ORDER BY seq DESC LIMIT 1",values:[session.uuidString]); defer { sqlite3_finalize(s) }
        return sqlite3_step(s)==SQLITE_ROW ? try decode(SummarySnapshot.self,s) : nil
    }
    /// Bounded migration work. New transcript rows are indexed by triggers immediately.
    public func indexNextSearchBatch(limit:Int=100) throws -> Bool {
        let state=try statement("SELECT cursor,watermark FROM search_backfill WHERE id=1"); defer { sqlite3_finalize(state) }
        guard sqlite3_step(state)==SQLITE_ROW else { return true }
        let cursor=sqlite3_column_int64(state,0),watermark=sqlite3_column_int64(state,1)
        if cursor>=watermark { return true }
        let rows=try segmentsForIndex(after:cursor,through:watermark,limit:max(1,min(200,limit)))
        guard sqlite3_exec(db,"BEGIN IMMEDIATE",nil,nil,nil)==SQLITE_OK else { throw failure() }
        do {
            for (seq,text) in rows { try write("INSERT OR REPLACE INTO transcript_search(rowid,text) VALUES(?,?)",[String(seq),text]) }
            let end=rows.last?.0 ?? watermark
            try write("UPDATE search_backfill SET cursor=? WHERE id=1",[String(end)])
            guard sqlite3_exec(db,"COMMIT",nil,nil,nil)==SQLITE_OK else { throw failure() }
            return end>=watermark || rows.isEmpty
        } catch { sqlite3_exec(db,"ROLLBACK",nil,nil,nil); throw error }
    }
    private func segmentsForIndex(after:Int64,through:Int64,limit:Int) throws -> [(Int64,String)] {
        let s=try statement("SELECT seq,json_extract(data,'$.text') FROM segments WHERE seq>? AND seq<=? ORDER BY seq LIMIT ?",values:[String(after),String(through),String(limit)])
        defer { sqlite3_finalize(s) }; var rows:[(Int64,String)]=[]
        while sqlite3_step(s)==SQLITE_ROW {
            if let text=sqlite3_column_text(s,1) { rows.append((sqlite3_column_int64(s,0),String(cString:text))) }
        }
        return rows
    }
    public func searchTranscripts(_ query:String,limit:Int=50) throws -> [TranscriptSearchHit] {
        let words=String(query.prefix(512)).components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty}.prefix(8)
        guard !words.isEmpty else { return [] }
        // SQLite invokes this callback synchronously. Its context lives until the
        // handler is removed, before this actor method returns. Bound broad queries
        // so they cannot monopolize the connection used for incremental writes.
        let deadline=UnsafeMutablePointer<UInt64>.allocate(capacity:1)
        deadline.initialize(to:DispatchTime.now().uptimeNanoseconds+50_000_000)
        sqlite3_progress_handler(db,1000,{ context in
            guard let context else { return 0 }
            return DispatchTime.now().uptimeNanoseconds>context.assumingMemoryBound(to:UInt64.self).pointee ? 1:0
        },deadline)
        defer { sqlite3_progress_handler(db,0,nil,nil); deadline.deinitialize(count:1); deadline.deallocate() }
        let match=words.map{"\"\(String($0.prefix(64)))\"*"}.joined(separator:" AND ")
        let s=try statement("""
        SELECT g.seq,g.session,s.data,g.id,g.start,json_extract(g.data,'$.source'),snippet(transcript_search,0,'','',' … ',22)
        FROM transcript_search JOIN segments g ON g.seq=transcript_search.rowid JOIN sessions s ON s.id=g.session
        WHERE transcript_search MATCH ? ORDER BY transcript_search.rank LIMIT ?
        """,values:[match,String(max(1,min(100,limit)))])
        defer { sqlite3_finalize(s) }; var result:[TranscriptSearchHit]=[]
        var status=sqlite3_step(s)
        while status==SQLITE_ROW {
            let session=try decode(Session.self,s,2)
            if let id=sqlite3_column_text(s,3),let source=sqlite3_column_text(s,5),let text=sqlite3_column_text(s,6) {
                result.append(.init(id:sqlite3_column_int64(s,0),sessionID:session.id,title:session.title,created:session.created,segmentID:String(cString:id),source:AudioSource(rawValue:String(cString:source)) ?? .system,start:sqlite3_column_double(s,4),snippet:String(String(cString:text).prefix(600))))
            }
            status=sqlite3_step(s)
        }
        if status==SQLITE_INTERRUPT { throw LAIError.message("La búsqueda es demasiado amplia. Añade otra palabra.") }
        guard status==SQLITE_DONE else { throw failure() }
        return result
    }
    public func save(_ bookmark:SessionBookmark) throws {
        var value=bookmark; value.note=String(value.note.prefix(2000)); value.time=max(0,value.time.isFinite ? value.time:0)
        try write("INSERT INTO bookmarks(id,session,time,data) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data,time=excluded.time",[value.id.uuidString,value.sessionID.uuidString,String(value.time),try encode(value)])
    }
    public func bookmarks(session:UUID,limit:Int=100,offset:Int=0) throws -> [SessionBookmark] {
        let s=try statement("SELECT data FROM bookmarks WHERE session=? ORDER BY time,id LIMIT ? OFFSET ?",values:[session.uuidString,String(max(1,min(200,limit))),String(max(0,offset))])
        defer { sqlite3_finalize(s) }; var result:[SessionBookmark]=[]
        while sqlite3_step(s)==SQLITE_ROW { result.append(try decode(SessionBookmark.self,s)) }
        return result
    }
    public func deleteBookmark(_ id:UUID) throws { try write("DELETE FROM bookmarks WHERE id=?",[id.uuidString]) }
    public func bookmarkPage(containing bookmark:SessionBookmark) throws -> Int {
        let s=try statement("SELECT COUNT(*) FROM bookmarks WHERE session=? AND (time,id)<(?,?)",values:[bookmark.sessionID.uuidString,String(bookmark.time),bookmark.id.uuidString]); defer { sqlite3_finalize(s) }
        return sqlite3_step(s)==SQLITE_ROW ? Int(sqlite3_column_int64(s,0))/100:0
    }
    public func segmentID(session:UUID,at time:Double) throws -> String? {
        let s=try statement("SELECT id FROM segments WHERE session=? AND start<=? ORDER BY start DESC LIMIT 1",values:[session.uuidString,String(time)])
        defer { sqlite3_finalize(s) }
        if sqlite3_step(s)==SQLITE_ROW,let id=sqlite3_column_text(s,0) { return String(cString:id) }
        let first=try segments(session:session,limit:1)
        return first.first?.1.id
    }
    public func delete(session: UUID) throws {
        let folder=directory.appendingPathComponent(session.uuidString,isDirectory:true)
        if FileManager.default.fileExists(atPath:folder.path) { try FileManager.default.removeItem(at:folder) }
        try write("DELETE FROM sessions WHERE id=?",[session.uuidString])
        guard sqlite3_wal_checkpoint_v2(db,nil,SQLITE_CHECKPOINT_TRUNCATE,nil,nil)==SQLITE_OK else { throw failure() }
    }
}
