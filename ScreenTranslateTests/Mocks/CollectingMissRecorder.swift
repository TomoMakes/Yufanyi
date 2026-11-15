@testable import ScreenTranslate

/// 把要存的未命中收在内存里的假记录器
final class CollectingMissRecorder: LunaMissRecording, @unchecked Sendable {
    private(set) var misses: [LunaMiss] = []

    func record(_ miss: LunaMiss) {
        misses.append(miss)
    }
}
