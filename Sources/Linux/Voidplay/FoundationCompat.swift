import Foundation

// Darwin Foundation re-exports these CoreFoundation helpers; swift-corelibs does not.
func CFAbsoluteTimeGetCurrent() -> CFAbsoluteTime { Date.timeIntervalSinceReferenceDate }
typealias CFAbsoluteTime = Double

/// Darwin-only memory pool scope; on Linux ARC frees eagerly, so the body just runs.
@discardableResult
func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}

extension MutableCollection where Self: RangeReplaceableCollection {
    /// SwiftUI's list reorder helper, which Darwin code gets for free from SwiftUI.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[index(startIndex, offsetBy: $0)] }
        let before = source.filter { $0 < destination }.count
        for offset in source.sorted(by: >) {
            remove(at: index(startIndex, offsetBy: offset))
        }
        insert(contentsOf: moving, at: index(startIndex, offsetBy: destination - before))
    }
}
