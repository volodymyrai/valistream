//
//  LivePlaylists.swift
//  ValistreamIntegrationTests
//
//  Created by Volodymyr Akimenko on 12/06/2026.
//

/// Builds live media-playlist bodies (no `EXT-X-ENDLIST`) for scripted monitoring timelines.
///
/// A live window is identified by its media sequence and segment list; advancing the window between
/// timeline entries models a server publishing new segments (research §8).
///
/// Example:
/// ```swift
/// LivePlaylists.window(mediaSequence: 1, segments: ["s1.ts", "s2.ts", "s3.ts"])
/// ```
enum LivePlaylists {
    /// A live media playlist body. `discontinuityAt` inserts `EXT-X-DISCONTINUITY` before the
    /// segment at that index.
    static func window(
        mediaSequence: Int,
        segments: [String],
        targetDuration: Int = 6,
        discontinuityAt: Int? = nil
    ) -> String {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(targetDuration)",
            "#EXT-X-MEDIA-SEQUENCE:\(mediaSequence)",
        ]
        for (index, segment) in segments.enumerated() {
            if discontinuityAt == index {
                lines.append("#EXT-X-DISCONTINUITY")
            }
            lines.append("#EXTINF:\(targetDuration).0,")
            lines.append(segment)
        }
        return lines.joined(separator: "\n")
    }
}
