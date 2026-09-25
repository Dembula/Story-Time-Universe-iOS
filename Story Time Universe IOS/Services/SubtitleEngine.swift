import Foundation

/// A single timed subtitle cue (VTT or SRT).
struct SubtitleCue: Identifiable, Hashable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    init(start: TimeInterval, end: TimeInterval, text: String) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.text = text
    }

    func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }
}

/// Downloads and parses WebVTT / SRT tracks from filmmaker-uploaded subtitle files.
@MainActor
final class SubtitleEngine: ObservableObject {
    @Published private(set) var cues: [SubtitleCue] = []
    @Published private(set) var activeText: String?
    @Published private(set) var availableTracks: [SubtitleTrack] = []
    @Published private(set) var selectedTrackId: String?
    @Published var isEnabled = true

    private var loadGeneration = 0

    func reset() {
        loadGeneration += 1
        cues = []
        activeText = nil
        availableTracks = []
        selectedTrackId = nil
        isEnabled = true
    }

    func load(tracks: [SubtitleTrack]?) async {
        loadGeneration += 1
        let generation = loadGeneration
        cues = []
        activeText = nil
        availableTracks = tracks ?? []
        selectedTrackId = nil

        guard let tracks, !tracks.isEmpty else { return }

        let preferred = tracks.first(where: { $0.isDefault == true })
            ?? tracks.first(where: { ($0.language ?? "").lowercased().hasPrefix("en") })
            ?? tracks.first

        guard let preferred else { return }
        selectedTrackId = preferred.id
        await applyTrack(preferred, generation: generation)
    }

    func selectTrack(id: String?) async {
        guard let id,
              let track = availableTracks.first(where: { $0.id == id }) else {
            selectedTrackId = nil
            cues = []
            activeText = nil
            return
        }
        selectedTrackId = id
        isEnabled = true
        loadGeneration += 1
        let generation = loadGeneration
        await applyTrack(track, generation: generation)
    }

    func updateTime(_ seconds: TimeInterval) {
        guard isEnabled, !cues.isEmpty, seconds.isFinite else {
            if activeText != nil { activeText = nil }
            return
        }
        // Binary search for active cue.
        var lo = 0
        var hi = cues.count - 1
        var found: String?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cue = cues[mid]
            if seconds < cue.start {
                hi = mid - 1
            } else if seconds >= cue.end {
                lo = mid + 1
            } else {
                found = cue.text
                break
            }
        }
        if activeText != found {
            activeText = found
        }
    }

    private func applyTrack(_ track: SubtitleTrack, generation: Int) async {
        guard let raw = track.vttUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = MediaURL.httpURL(from: raw) ?? URL(string: raw, relativeTo: AppConfig.apiBaseURL)?.absoluteURL
        else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue(DeviceIdentity.userAgent, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard generation == loadGeneration else { return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let body = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            else { return }

            let parsed = Self.parse(body)
            guard generation == loadGeneration else { return }
            cues = parsed
            activeText = nil
        } catch {
            // Keep playing without captions if the file can't be fetched.
        }
    }

    // MARK: - Parsers

    static func parse(_ raw: String) -> [SubtitleCue] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("WEBVTT") || trimmed.contains("-->") && trimmed.contains(".") {
            return parseVTT(trimmed)
        }
        return parseSRT(trimmed)
    }

    private static func parseVTT(_ raw: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }
                .filter { !$0.isEmpty && !$0.hasPrefix("NOTE") && !$0.uppercased().hasPrefix("WEBVTT") && !$0.hasPrefix("STYLE") }

            guard let timingLine = lines.first(where: { $0.contains("-->") }),
                  let range = parseTimingLine(timingLine) else { continue }

            let textLines = lines.filter { !$0.contains("-->") && Int($0) == nil }
            let text = sanitizeCueText(textLines.joined(separator: "\n"))
            guard !text.isEmpty, range.end > range.start else { continue }
            cues.append(SubtitleCue(start: range.start, end: range.end, text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func parseSRT(_ raw: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }
                .filter { !$0.isEmpty }

            guard let timingLine = lines.first(where: { $0.contains("-->") }),
                  let range = parseTimingLine(timingLine) else { continue }

            let textLines = lines.filter { !$0.contains("-->") && Int($0) == nil }
            let text = sanitizeCueText(textLines.joined(separator: "\n"))
            guard !text.isEmpty, range.end > range.start else { continue }
            cues.append(SubtitleCue(start: range.start, end: range.end, text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func parseTimingLine(_ line: String) -> (start: TimeInterval, end: TimeInterval)? {
        let cleaned = line
            .replacingOccurrences(of: ",", with: ".")
            .components(separatedBy: "-->")
        guard cleaned.count >= 2,
              let start = parseTimestamp(cleaned[0].trimmingCharacters(in: .whitespaces)),
              let end = parseTimestamp(cleaned[1].split(separator: " ").first.map(String.init) ?? cleaned[1])
        else { return nil }
        return (start, end)
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }

        let hours: Double
        let minutes: Double
        let secondsPart: String
        if parts.count == 3 {
            hours = Double(parts[0]) ?? 0
            minutes = Double(parts[1]) ?? 0
            secondsPart = parts[2]
        } else {
            hours = 0
            minutes = Double(parts[0]) ?? 0
            secondsPart = parts[1]
        }
        guard let seconds = Double(secondsPart) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func sanitizeCueText(_ text: String) -> String {
        var result = text
        // Strip simple VTT/HTML tags.
        while let open = result.range(of: "<"), let close = result.range(of: ">", range: open.upperBound..<result.endIndex) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
