import Foundation

/// Incremental SSE parser. URLSession has no built-in EventSource so we
/// roll a minimal one that matches the spec (https://html.spec.whatwg.org/
/// multipage/server-sent-events.html#event-stream-interpretation):
///
///   - `event: <name>` sets the next event's name
///   - `data: <line>` appends a line to the next event's data
///   - empty line dispatches the buffered event
///   - lines starting with `:` are comments and ignored
///   - `id:` / `retry:` are accepted but ignored (we don't need them for
///     graphql-sse single-connection mode)
struct SseEvent {
    let name: String?  // "next" | "complete" | nil ("message" in spec)
    let data: String
}

final class SseEventParser {
    private var eventName: String?
    private var dataLines: [String] = []
    /// Bytes left over from the previous chunk if it ended mid-line.
    private var pending = Data()

    /// Feeds a chunk of bytes and returns any complete events produced
    /// by the chunk. Partial events are buffered internally.
    func feed(_ data: Data) -> [SseEvent] {
        var combined = pending
        combined.append(data)
        pending = Data()

        var events: [SseEvent] = []
        var lineStart = combined.startIndex
        var i = combined.startIndex
        while i < combined.endIndex {
            let byte = combined[i]
            if byte == 0x0A /* \n */ {
                let lineSlice = combined[lineStart..<i]
                // Strip an optional trailing \r so CRLF and LF both work.
                let lineEnd = lineSlice.last == 0x0D ? combined.index(before: i) : i
                let line = String(data: combined[lineStart..<lineEnd], encoding: .utf8) ?? ""
                processLine(line, into: &events)
                lineStart = combined.index(after: i)
            }
            i = combined.index(after: i)
        }
        // Carry forward any bytes after the last newline.
        if lineStart < combined.endIndex {
            pending = Data(combined[lineStart..<combined.endIndex])
        }
        return events
    }

    private func processLine(_ line: String, into events: inout [SseEvent]) {
        if line.isEmpty {
            dispatch(into: &events)
            return
        }
        if line.first == ":" {
            return  // comment
        }
        // Split on the FIRST colon; the remainder is the value, with a
        // single optional leading space stripped (per spec).
        if let colonIdx = line.firstIndex(of: ":") {
            let field = String(line[line.startIndex..<colonIdx])
            var valueStart = line.index(after: colonIdx)
            if valueStart < line.endIndex && line[valueStart] == " " {
                valueStart = line.index(after: valueStart)
            }
            let value = String(line[valueStart..<line.endIndex])
            switch field {
            case "event": eventName = value
            case "data": dataLines.append(value)
            default: break  // id / retry / unknown — ignored
            }
        } else {
            // A field name with no colon is treated as a field with an
            // empty value (per spec). Nothing we care about here.
        }
    }

    private func dispatch(into events: inout [SseEvent]) {
        guard !dataLines.isEmpty || eventName != nil else { return }
        let data = dataLines.joined(separator: "\n")
        events.append(SseEvent(name: eventName, data: data))
        eventName = nil
        dataLines.removeAll(keepingCapacity: true)
    }
}
