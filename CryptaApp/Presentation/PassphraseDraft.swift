import Observation
import Foundation

@MainActor @Observable public final class PassphraseDraft: Identifiable {
    public let id = UUID()
    public var current = ""
    public var replacement = ""
    public var confirmation = ""
    public var acknowledged = false
    public init() {}
    func clear() { current = ""; replacement = ""; confirmation = ""; acknowledged = false }
}
