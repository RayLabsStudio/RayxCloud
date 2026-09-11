// DebugLogFile.swift
// Debug builds mirror stdout and stderr into Documents/rayxcloud.log so the
// stream and auth logs can be pulled off a phone without a USB cable:
//   xcrun devicectl device copy from --device <id> \
//     --domain-type appDataContainer --domain-identifier com.raylabsstudio.rayxcloud \
//     --source Documents/rayxcloud.log --destination ./rayxcloud.log
//

import Foundation

enum DebugLogFile {
    static let fileName = "rayxcloud.log"

    static func install() {
#if DEBUG
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = documents.appendingPathComponent(fileName)
        // Keep only the latest run so the file stays small.
        try? FileManager.default.removeItem(at: url)
        let path = url.path
        freopen(path, "a+", stdout)
        freopen(path, "a+", stderr)
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)
        print("[RayxCloud] log file started \(Date())")
#endif
    }
}
