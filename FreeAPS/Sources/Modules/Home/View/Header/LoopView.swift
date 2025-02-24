import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    private enum Config {
        static let lag: TimeInterval = 30
    }

    @Binding var suggestion: Suggestion?
    @Binding var enactedSuggestion: Suggestion?
    @Binding var closedLoop: Bool
    @Binding var timerDate: Date
    @Binding var isLooping: Bool
    @Binding var lastLoopDate: Date

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private let rect = CGRect(x: 0, y: 0, width: 32, height: 32)
    var body: some View {
        VStack(alignment: .center) {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 6)
                    .frame(width: rect.width, height: rect.height)
                    .mask(mask(in: rect).fill(style: FillStyle(eoFill: true)))
                if isLooping {
                    ProgressView()
                }
            }
            if isLooping {
                Text("looping").font(.caption2)
            } else if actualSuggestion?.timestamp != nil {
                Text("\(Int((timerDate.timeIntervalSince(lastLoopDate) - Config.lag) / 60) + 1) min ago").font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("--").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private var color: Color {
        guard actualSuggestion?.timestamp != nil else {
            return .loopGray
        }
        let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    func mask(in rect: CGRect) -> Path {
        var path = Rectangle().path(in: rect)
        if !closedLoop {
            path.addPath(Rectangle().path(in: CGRect(x: rect.minX, y: rect.midY - 5, width: rect.width, height: 10)))
        }
        return path
    }

    private var actualSuggestion: Suggestion? {
        if closedLoop, suggestion?.rate != nil || suggestion?.units != nil {
            return enactedSuggestion ?? suggestion
        } else {
            return suggestion
        }
    }
}

extension View {
    func animateForever(
        using animation: Animation = Animation.easeInOut(duration: 1),
        autoreverses: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        let repeated = animation.repeatForever(autoreverses: autoreverses)

        return onAppear {
            withAnimation(repeated) {
                action()
            }
        }
    }
}
