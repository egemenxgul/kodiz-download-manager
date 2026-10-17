import SwiftUI
import KodizEngine

public struct SegmentCanvasView: View {
    public let segments: [Segment]
    public let totalBytes: Int64?

    public init(segments: [Segment], totalBytes: Int64?) {
        self.segments = segments
        self.totalBytes = totalBytes
    }

    public var body: some View {
        Canvas { context, size in
            guard let total = totalBytes, total > 0, !segments.isEmpty else {
                // Indeterminate or unknown size: draw striped pattern
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .color(Color.blue.opacity(0.3)))
                return
            }

            let sorted = segments.sorted(by: { $0.start < $1.start })

            for segment in sorted {
                let segStartRatio = Double(segment.start) / Double(total)
                let segLength = Double(max(1, segment.end - segment.start + 1))
                let segWidthRatio = segLength / Double(total)

                let x = segStartRatio * size.width
                let w = max(2.0, segWidthRatio * size.width)

                let fullRect = CGRect(x: x, y: 0, width: w, height: size.height)

                // Background container of segment
                context.fill(Path(fullRect), with: .color(Color.secondary.opacity(0.15)))

                // Downloaded portion inside segment
                let receivedRatio = Double(min(segment.received, Int64(segLength))) / segLength
                let receivedWidth = w * receivedRatio

                let receivedRect = CGRect(x: x, y: 0, width: receivedWidth, height: size.height)

                let fillColor: Color
                switch segment.state {
                case .completed:
                    fillColor = Color.green
                case .downloading:
                    fillColor = Color.blue
                case .failed:
                    fillColor = Color.red
                case .pending:
                    fillColor = Color.orange.opacity(0.6)
                }

                context.fill(Path(receivedRect), with: .color(fillColor))

                // Border separator
                let borderPath = Path { p in
                    p.move(to: CGPoint(x: x + w, y: 0))
                    p.addLine(to: CGPoint(x: x + w, y: size.height))
                }
                context.stroke(borderPath, with: .color(Color.black.opacity(0.3)), lineWidth: 1)
            }
        }
        .frame(height: 22)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}
