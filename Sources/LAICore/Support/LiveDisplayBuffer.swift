import Foundation

/// Latest UI values only. Definitive text bypasses this buffer and is persisted
/// by RecordingPipeline before presentation. At most one partial per source.
public struct LiveDisplayBuffer:Sendable {
    public private(set) var partials:[AudioSource:TranscriptSegment]=[:]
    public private(set) var levels:[AudioSource:Float]=[:]
    public private(set) var voice:[AudioSource:Bool]=[:]
    public init() {}
    public mutating func partial(_ segment:TranscriptSegment) { partials[segment.source]=segment }
    public mutating func finalized(_ source:AudioSource) { partials[source]=nil }
    public mutating func activity(_ source:AudioSource,level:Float,active:Bool) { levels[source]=level; voice[source]=active }
    public mutating func drain() -> Self { let value=self; self=Self(); return value }
}
