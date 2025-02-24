import Algorithms
import SwiftDate
import SwiftUI

private enum PredictionType: Hashable {
    case iob
    case cob
    case zt
    case uam
}

struct DotInfo {
    let rect: CGRect
    let value: Decimal
}

typealias GlucoseYRange = (minValue: Int, minY: CGFloat, maxValue: Int, maxY: CGFloat)

struct MainChartView: View {
    private enum Config {
        static let endID = "End"
        static let screenHours = 5
        static let basalHeight: CGFloat = 60
        static let topYPadding: CGFloat = 20
        static let bottomYPadding: CGFloat = 50
        static let minAdditionalWidth: CGFloat = 150
        static let maxGlucose = 450
        static let minGlucose = 70
        static let yLinesCount = 5
        static let bolusSize: CGFloat = 8
        static let bolusScale: CGFloat = 3
        static let carbsSize: CGFloat = 10
        static let carbsScale: CGFloat = 0.3
    }

    @Binding var glucose: [BloodGlucose]
    @Binding var suggestion: Suggestion?
    @Binding var tempBasals: [PumpHistoryEvent]
    @Binding var boluses: [PumpHistoryEvent]
    @Binding var hours: Int
    @Binding var maxBasal: Decimal
    @Binding var basalProfile: [BasalProfileEntry]
    @Binding var tempTargets: [TempTarget]
    @Binding var carbs: [CarbsEntry]
    let units: GlucoseUnits

    @State var didAppearTrigger = false
    @State private var glucoseDots: [CGRect] = []
    @State private var predictionDots: [PredictionType: [CGRect]] = [:]
    @State private var bolusDots: [DotInfo] = []
    @State private var bolusPath = Path()
    @State private var tempBasalPath = Path()
    @State private var regularBasalPath = Path()
    @State private var tempTargetsPath = Path()
    @State private var carbsDots: [DotInfo] = []
    @State private var carbsPath = Path()
    @State private var glucoseYGange: GlucoseYRange = (0, 0, 0, 0)
    @State private var offset: CGFloat = 0

    private let calculationQueue = DispatchQueue(label: "MainChartView.calculationQueue")

    private var dateDormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumIntegerDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        return formatter
    }

    private var carbsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    // MARK: - Views

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                yGridView(fullSize: geo.size)
                mainScrollView(fullSize: geo.size)
                glucoseLabelsView(fullSize: geo.size)
            }
        }
    }

    private func mainScrollView(fullSize: CGSize) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { scroll in
                ZStack(alignment: .top) {
                    tempTargetsView(fullSize: fullSize).drawingGroup()
                    basalView(fullSize: fullSize).drawingGroup()

                    mainView(fullSize: fullSize).id(Config.endID)
                        .drawingGroup()
                        .onChange(of: glucose) { _ in
                            scroll.scrollTo(Config.endID, anchor: .trailing)
                        }
                        .onChange(of: suggestion) { _ in
                            scroll.scrollTo(Config.endID, anchor: .trailing)
                        }
                        .onChange(of: tempBasals) { _ in
                            scroll.scrollTo(Config.endID, anchor: .trailing)
                        }
                        .onAppear {
                            // add trigger to the end of main queue
                            DispatchQueue.main.async {
                                scroll.scrollTo(Config.endID, anchor: .trailing)
                                didAppearTrigger = true
                            }
                        }
                }
            }
        }
    }

    private func yGridView(fullSize: CGSize) -> some View {
        Path { path in
            let range = glucoseYGange
            let step = (range.maxY - range.minY) / CGFloat(Config.yLinesCount)
            for line in 0 ... Config.yLinesCount {
                path.move(to: CGPoint(x: 0, y: range.minY + CGFloat(line) * step))
                path.addLine(to: CGPoint(x: fullSize.width, y: range.minY + CGFloat(line) * step))
            }
        }.stroke(Color.secondary, lineWidth: 0.2)
    }

    private func glucoseLabelsView(fullSize: CGSize) -> some View {
        ForEach(0 ..< Config.yLinesCount + 1) { line -> AnyView in
            let range = glucoseYGange
            let yStep = (range.maxY - range.minY) / CGFloat(Config.yLinesCount)
            let valueStep = Double(range.maxValue - range.minValue) / Double(Config.yLinesCount)
            let value = round(Double(range.maxValue) - Double(line) * valueStep) *
                (units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)

            return Text(glucoseFormatter.string(from: value as NSNumber)!)
                .position(CGPoint(x: fullSize.width - 12, y: range.minY + CGFloat(line) * yStep))
                .font(.caption2)
                .asAny()
        }
    }

    private func basalView(fullSize: CGSize) -> some View {
        ZStack {
            tempBasalPath.fill(Color.tempBasal)
            tempBasalPath.stroke(Color.tempBasal, lineWidth: 1)
            regularBasalPath.stroke(Color.basal, lineWidth: 1)
        }
        .frame(width: fullGlucoseWidth(viewWidth: fullSize.width) + additionalWidth(viewWidth: fullSize.width))
        .frame(maxHeight: Config.basalHeight)
        .background(Color.secondary.opacity(0.1))
        .onChange(of: tempBasals) { _ in
            calculateBasalPoints(fullSize: fullSize)
        }
        .onChange(of: maxBasal) { _ in
            calculateBasalPoints(fullSize: fullSize)
        }
        .onChange(of: basalProfile) { _ in
            calculateBasalPoints(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) { _ in
            calculateBasalPoints(fullSize: fullSize)
        }
    }

    private func mainView(fullSize: CGSize) -> some View {
        Group {
            VStack {
                ZStack {
                    xGridView(fullSize: fullSize)
                    carbsView(fullSize: fullSize)
                    bolusView(fullSize: fullSize)
                    glucoseView(fullSize: fullSize)
                    predictionsView(fullSize: fullSize)
                }
                timeLabelsView(fullSize: fullSize)
            }
        }
        .frame(width: fullGlucoseWidth(viewWidth: fullSize.width) + additionalWidth(viewWidth: fullSize.width))
    }

    private func xGridView(fullSize: CGSize) -> some View {
        Path { path in
            for hour in 0 ..< hours + hours {
                let x = firstHourPosition(viewWidth: fullSize.width) +
                    oneSecondStep(viewWidth: fullSize.width) *
                    CGFloat(hour) * CGFloat(1.hours.timeInterval)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: fullSize.height - 20))
            }
        }
        .stroke(Color.secondary, lineWidth: 0.2)
    }

    private func timeLabelsView(fullSize: CGSize) -> some View {
        ZStack {
            // X time labels
            ForEach(0 ..< hours + hours) { hour in
                Text(dateDormatter.string(from: firstHourDate().addingTimeInterval(hour.hours.timeInterval)))
                    .font(.caption)
                    .position(
                        x: firstHourPosition(viewWidth: fullSize.width) +
                            oneSecondStep(viewWidth: fullSize.width) *
                            CGFloat(hour) * CGFloat(1.hours.timeInterval),
                        y: 10.0
                    )
                    .foregroundColor(.secondary)
            }
        }.frame(maxHeight: 20)
    }

    private func glucoseView(fullSize: CGSize) -> some View {
        Path { path in
            for rect in glucoseDots {
                path.addEllipse(in: rect)
            }
        }
        .fill(Color.loopGreen)
        .onChange(of: glucose) { _ in
            update(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) { _ in
            update(fullSize: fullSize)
        }
    }

    private func bolusView(fullSize: CGSize) -> some View {
        ZStack {
            bolusPath
                .fill(Color.insulin)
            bolusPath
                .stroke(Color.primary, lineWidth: 0.5)

            ForEach(bolusDots, id: \.rect.minX) { info -> AnyView in
                let position = CGPoint(x: info.rect.midX, y: info.rect.maxY + 8)
                return Text(bolusFormatter.string(from: info.value as NSNumber)!).font(.caption2)
                    .position(position)
                    .asAny()
            }
        }
        .onChange(of: boluses) { _ in
            calculateBolusDots(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) { _ in
            calculateBolusDots(fullSize: fullSize)
        }
    }

    private func carbsView(fullSize: CGSize) -> some View {
        ZStack {
            carbsPath
                .fill(Color.loopYellow)
            carbsPath
                .stroke(Color.primary, lineWidth: 0.5)

            ForEach(carbsDots, id: \.rect.minX) { info -> AnyView in
                let position = CGPoint(x: info.rect.midX, y: info.rect.minY - 8)
                return Text(carbsFormatter.string(from: info.value as NSNumber)!).font(.caption2)
                    .position(position)
                    .asAny()
            }
        }
        .onChange(of: carbs) { _ in
            calculateCarbsDots(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) { _ in
            calculateCarbsDots(fullSize: fullSize)
        }
    }

    private func tempTargetsView(fullSize: CGSize) -> some View {
        ZStack {
            tempTargetsPath
                .fill(Color.tempBasal.opacity(0.5))
        }
        .onChange(of: glucose) { _ in
            calculateTempTargetsRects(fullSize: fullSize)
        }
        .onChange(of: tempTargets) { _ in
            calculateTempTargetsRects(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) { _ in
            calculateTempTargetsRects(fullSize: fullSize)
        }
    }

    private func predictionsView(fullSize: CGSize) -> some View {
        Group {
            Path { path in
                for rect in predictionDots[.iob] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.insulin)

            Path { path in
                for rect in predictionDots[.cob] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.loopYellow)

            Path { path in
                for rect in predictionDots[.zt] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.zt)

            Path { path in
                for rect in predictionDots[.uam] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.uam)
        }
        .onChange(of: suggestion) { _ in
            update(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) { _ in
            update(fullSize: fullSize)
        }
    }
}

// MARK: - Calculations

extension MainChartView {
    private func update(fullSize: CGSize) {
        calculatePredictionDots(fullSize: fullSize, type: .iob)
        calculatePredictionDots(fullSize: fullSize, type: .cob)
        calculatePredictionDots(fullSize: fullSize, type: .zt)
        calculatePredictionDots(fullSize: fullSize, type: .uam)
        calculateGlucoseDots(fullSize: fullSize)
        calculateBolusDots(fullSize: fullSize)
        calculateCarbsDots(fullSize: fullSize)
        calculateTempTargetsRects(fullSize: fullSize)
        calculateTempTargetsRects(fullSize: fullSize)
    }

    private func calculateGlucoseDots(fullSize: CGSize) {
        calculationQueue.async {
            let dots = glucose.concurrentMap { value -> CGRect in
                let position = glucoseToCoordinate(value, fullSize: fullSize)
                return CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
            }

            let range = self.getGlucoseYRange(fullSize: fullSize)

            DispatchQueue.main.async {
                glucoseYGange = range
                glucoseDots = dots
            }
        }
    }

    private func calculateBolusDots(fullSize: CGSize) {
        calculationQueue.async {
            let dots = boluses.map { value -> DotInfo in
                let center = timeToInterpolatedPoint(value.timestamp.timeIntervalSince1970, fullSize: fullSize)
                let size = Config.bolusSize + CGFloat(value.amount ?? 0) * Config.bolusScale
                let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
                return DotInfo(rect: rect, value: value.amount ?? 0)
            }

            let path = Path { path in
                for dot in dots {
                    path.addEllipse(in: dot.rect)
                }
            }

            DispatchQueue.main.async {
                bolusDots = dots
                bolusPath = path
            }
        }
    }

    private func calculateCarbsDots(fullSize: CGSize) {
        calculationQueue.async {
            let dots = carbs.map { value -> DotInfo in
                let center = timeToInterpolatedPoint(value.createdAt.timeIntervalSince1970, fullSize: fullSize)
                let size = Config.carbsSize + CGFloat(value.carbs) * Config.carbsScale
                let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
                return DotInfo(rect: rect, value: value.carbs)
            }

            let path = Path { path in
                for dot in dots {
                    path.addEllipse(in: dot.rect)
                }
            }

            DispatchQueue.main.async {
                carbsDots = dots
                carbsPath = path
            }
        }
    }

    private func calculatePredictionDots(fullSize: CGSize, type: PredictionType) {
        calculationQueue.async {
            let values: [Int] = { () -> [Int] in
                switch type {
                case .iob:
                    return suggestion?.predictions?.iob ?? []
                case .cob:
                    return suggestion?.predictions?.cob ?? []
                case .zt:
                    return suggestion?.predictions?.zt ?? []
                case .uam:
                    return suggestion?.predictions?.uam ?? []
                }
            }()

            var index = 0
            let dots = values.map { value -> CGRect in
                let position = predictionToCoordinate(value, fullSize: fullSize, index: index)
                index += 1
                return CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
            }
            DispatchQueue.main.async {
                predictionDots[type] = dots
            }
        }
    }

    private func calculateBasalPoints(fullSize: CGSize) {
        calculationQueue.async {
            let dayAgoTime = Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970
            let firstTempTime = (tempBasals.first?.timestamp ?? Date()).timeIntervalSince1970
            var lastTimeEnd = firstTempTime
            let firstRegularBasalPoints = findRegularBasalPoints(
                timeBegin: dayAgoTime,
                timeEnd: firstTempTime,
                fullSize: fullSize
            )
            let tempBasalPoints = firstRegularBasalPoints + tempBasals.chunks(ofCount: 2).map { chunk -> [CGPoint] in
                let chunk = Array(chunk)
                guard chunk.count == 2, chunk[0].type == .tempBasal, chunk[1].type == .tempBasalDuration else { return [] }
                let timeBegin = chunk[0].timestamp.timeIntervalSince1970
                let timeEnd = timeBegin + (chunk[1].durationMin ?? 0).minutes.timeInterval
                let rateCost = Config.basalHeight / CGFloat(maxBasal)
                let x0 = timeToXCoordinate(timeBegin, fullSize: fullSize)
                let y0 = Config.basalHeight - CGFloat(chunk[0].rate ?? 0) * rateCost
                let regularPoints = findRegularBasalPoints(timeBegin: lastTimeEnd, timeEnd: timeBegin, fullSize: fullSize)
                lastTimeEnd = timeEnd
                return regularPoints + [CGPoint(x: x0, y: y0)]
            }.flatMap { $0 }
            let tempBasalPath = Path { path in
                var yPoint: CGFloat = Config.basalHeight
                path.move(to: CGPoint(x: 0, y: yPoint))

                for point in tempBasalPoints {
                    path.addLine(to: CGPoint(x: point.x, y: yPoint))
                    path.addLine(to: point)
                    yPoint = point.y
                }
                let lastPoint = lastBasalPoint(fullSize: fullSize)
                path.addLine(to: CGPoint(x: lastPoint.x, y: yPoint))
                path.addLine(to: CGPoint(x: lastPoint.x, y: Config.basalHeight))
                path.addLine(to: CGPoint(x: 0, y: Config.basalHeight))
            }

            let endDateTime = dayAgoTime + 1.days.timeInterval + 6.hours.timeInterval
            let regularBasalPoints = findRegularBasalPoints(
                timeBegin: dayAgoTime,
                timeEnd: endDateTime,
                fullSize: fullSize
            )

            let regularBasalPath = Path { path in
                var yPoint: CGFloat = Config.basalHeight
                path.move(to: CGPoint(x: -50, y: yPoint))

                for point in regularBasalPoints {
                    path.addLine(to: CGPoint(x: point.x, y: yPoint))
                    path.addLine(to: point)
                    yPoint = point.y
                }
                path.addLine(to: CGPoint(x: timeToXCoordinate(endDateTime, fullSize: fullSize), y: yPoint))
            }

            DispatchQueue.main.async {
                self.tempBasalPath = tempBasalPath
                self.regularBasalPath = regularBasalPath
            }
        }
    }

    private func calculateTempTargetsRects(fullSize: CGSize) {
        calculationQueue.async {
            var rects = tempTargets.map { tempTarget -> CGRect in
                let x0 = timeToXCoordinate(tempTarget.createdAt.timeIntervalSince1970, fullSize: fullSize)
                let y0 = glucoseToYCoordinate(Int(tempTarget.targetTop), fullSize: fullSize)
                let x1 = timeToXCoordinate(
                    tempTarget.createdAt.timeIntervalSince1970 + Int(tempTarget.duration).minutes.timeInterval,
                    fullSize: fullSize
                )
                let y1 = glucoseToYCoordinate(Int(tempTarget.targetBottom), fullSize: fullSize)
                return CGRect(
                    x: x0,
                    y: y0 - 3,
                    width: x1 - x0,
                    height: y1 - y0 + 6
                )
            }
            if rects.count > 1 {
                rects = rects.reduce([]) { result, rect -> [CGRect] in
                    guard var last = result.last else { return [rect] }
                    if last.origin.x + last.width > rect.origin.x {
                        last.size.width = rect.origin.x - last.origin.x
                    }
                    var res = Array(result.dropLast())
                    res.append(contentsOf: [last, rect])
                    return res
                }
            }

            let path = Path { path in
                path.addRects(rects)
            }

            DispatchQueue.main.async {
                tempTargetsPath = path
            }
        }
    }

    private func findRegularBasalPoints(timeBegin: TimeInterval, timeEnd: TimeInterval, fullSize: CGSize) -> [CGPoint] {
        guard timeBegin < timeEnd else {
            return []
        }
        let beginDate = Date(timeIntervalSince1970: timeBegin)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: beginDate)

        let basalNormalized = basalProfile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval).timeIntervalSince1970,
                rate: $0.rate
            )
        } + basalProfile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval + 1.days.timeInterval).timeIntervalSince1970,
                rate: $0.rate
            )
        } + basalProfile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval + 2.days.timeInterval).timeIntervalSince1970,
                rate: $0.rate
            )
        }

        let basalTruncatedPoints = basalNormalized.windows(ofCount: 2)
            .compactMap { window -> CGPoint? in
                let window = Array(window)
                if window[0].time < timeBegin, window[1].time < timeBegin {
                    return nil
                }

                let rateCost = Config.basalHeight / CGFloat(maxBasal)
                if window[0].time < timeBegin, window[1].time >= timeBegin {
                    let x = timeToXCoordinate(timeBegin, fullSize: fullSize)
                    let y = Config.basalHeight - CGFloat(window[0].rate) * rateCost
                    return CGPoint(x: x, y: y)
                }

                if window[0].time >= timeBegin, window[0].time < timeEnd {
                    let x = timeToXCoordinate(window[0].time, fullSize: fullSize)
                    let y = Config.basalHeight - CGFloat(window[0].rate) * rateCost
                    return CGPoint(x: x, y: y)
                }

                return nil
            }

        return basalTruncatedPoints
    }

    private func lastBasalPoint(fullSize: CGSize) -> CGPoint {
        let lastBasal = Array(tempBasals.suffix(2))
        guard lastBasal.count == 2 else {
            return CGPoint(x: timeToXCoordinate(Date().timeIntervalSince1970, fullSize: fullSize), y: Config.basalHeight)
        }
        let endBasalTime = lastBasal[0].timestamp.timeIntervalSince1970 + (lastBasal[1].durationMin?.minutes.timeInterval ?? 0)
        let rateCost = Config.basalHeight / CGFloat(maxBasal)
        let x = timeToXCoordinate(endBasalTime, fullSize: fullSize)
        let y = Config.basalHeight - CGFloat(lastBasal[0].rate ?? 0) * rateCost
        return CGPoint(x: x, y: y)
    }

    private func fullGlucoseWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * CGFloat(hours) / CGFloat(Config.screenHours)
    }

    private func additionalWidth(viewWidth: CGFloat) -> CGFloat {
        guard let predictions = suggestion?.predictions,
              let deliveredAt = suggestion?.deliverAt,
              let last = glucose.last
        else {
            return Config.minAdditionalWidth
        }

        let iob = predictions.iob?.count ?? 0
        let zt = predictions.zt?.count ?? 0
        let cob = predictions.cob?.count ?? 0
        let uam = predictions.uam?.count ?? 0
        let max = [iob, zt, cob, uam].max() ?? 0

        let lastDeltaTime = last.dateString.timeIntervalSince(deliveredAt)
        let additionalTime = CGFloat(TimeInterval(max) * 5.minutes.timeInterval - lastDeltaTime)
        let oneSecondWidth = oneSecondStep(viewWidth: viewWidth)

        return Swift.max(additionalTime * oneSecondWidth, Config.minAdditionalWidth)
    }

    private func oneSecondStep(viewWidth: CGFloat) -> CGFloat {
        viewWidth / (CGFloat(Config.screenHours) * CGFloat(1.hours.timeInterval))
    }

    private func maxPredValue() -> Int? {
        [
            suggestion?.predictions?.cob ?? [],
            suggestion?.predictions?.iob ?? [],
            suggestion?.predictions?.zt ?? [],
            suggestion?.predictions?.uam ?? []
        ]
        .flatMap { $0 }
        .max()
    }

    private func minPredValue() -> Int? {
        [
            suggestion?.predictions?.cob ?? [],
            suggestion?.predictions?.iob ?? [],
            suggestion?.predictions?.zt ?? [],
            suggestion?.predictions?.uam ?? []
        ]
        .flatMap { $0 }
        .min()
    }

    private func glucoseToCoordinate(_ glucoseEntry: BloodGlucose, fullSize: CGSize) -> CGPoint {
        let x = timeToXCoordinate(glucoseEntry.dateString.timeIntervalSince1970, fullSize: fullSize)
        let y = glucoseToYCoordinate(glucoseEntry.glucose ?? 0, fullSize: fullSize)

        return CGPoint(x: x, y: y)
    }

    private func predictionToCoordinate(_ pred: Int, fullSize: CGSize, index: Int) -> CGPoint {
        guard let deliveredAt = suggestion?.deliverAt else {
            return .zero
        }

        let predTime = deliveredAt.timeIntervalSince1970 + TimeInterval(index) * 5.minutes.timeInterval
        let x = timeToXCoordinate(predTime, fullSize: fullSize)
        let y = glucoseToYCoordinate(pred, fullSize: fullSize)

        return CGPoint(x: x, y: y)
    }

    private func timeToXCoordinate(_ time: TimeInterval, fullSize: CGSize) -> CGFloat {
        let xOffset = -(
            glucose.first?.dateString.timeIntervalSince1970 ?? Date()
                .addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970
        )
        let stepXFraction = fullGlucoseWidth(viewWidth: fullSize.width) / CGFloat(hours.hours.timeInterval)
        let x = CGFloat(time + xOffset) * stepXFraction
        return x
    }

    private func glucoseToYCoordinate(_ glucoseValue: Int, fullSize: CGSize) -> CGFloat {
        let topYPaddint = Config.topYPadding + Config.basalHeight
        let bottomYPadding = Config.bottomYPadding
        var maxValue = glucose.compactMap(\.glucose).max() ?? Config.maxGlucose
        if let maxPredValue = maxPredValue() {
            maxValue = max(maxValue, maxPredValue)
        }
        var minValue = glucose.compactMap(\.glucose).min() ?? Config.minGlucose
        if let minPredValue = minPredValue() {
            minValue = min(minValue, minPredValue)
        }
        let stepYFraction = (fullSize.height - topYPaddint - bottomYPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let y = fullSize.height - CGFloat(glucoseValue) * stepYFraction + yOffset - bottomYPadding
        return y
    }

    private func timeToInterpolatedPoint(_ time: TimeInterval, fullSize: CGSize) -> CGPoint {
        var nextIndex = 0
        for (index, value) in glucose.enumerated() {
            if value.dateString.timeIntervalSince1970 > time {
                nextIndex = index
                break
            }
        }
        let x = timeToXCoordinate(time, fullSize: fullSize)

        guard nextIndex > 0 else {
            let lastY = glucoseToYCoordinate(glucose.last?.glucose ?? 0, fullSize: fullSize)
            return CGPoint(x: x, y: lastY)
        }

        let prevX = timeToXCoordinate(glucose[nextIndex - 1].dateString.timeIntervalSince1970, fullSize: fullSize)
        let prevY = glucoseToYCoordinate(glucose[nextIndex - 1].glucose ?? 0, fullSize: fullSize)
        let nextX = timeToXCoordinate(glucose[nextIndex].dateString.timeIntervalSince1970, fullSize: fullSize)
        let nextY = glucoseToYCoordinate(glucose[nextIndex].glucose ?? 0, fullSize: fullSize)
        let delta = nextX - prevX
        let fraction = (x - prevX) / delta

        return pointInLine(CGPoint(x: prevX, y: prevY), CGPoint(x: nextX, y: nextY), fraction)
    }

    private func getGlucoseYRange(fullSize: CGSize) -> GlucoseYRange {
        let topYPaddint = Config.topYPadding + Config.basalHeight
        let bottomYPadding = Config.bottomYPadding
        var maxValue = glucose.compactMap(\.glucose).max() ?? Config.maxGlucose
        if let maxPredValue = maxPredValue() {
            maxValue = max(maxValue, maxPredValue)
        }
        var minValue = glucose.compactMap(\.glucose).min() ?? Config.minGlucose
        if let minPredValue = minPredValue() {
            minValue = min(minValue, minPredValue)
        }
        let stepYFraction = (fullSize.height - topYPaddint - bottomYPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let maxY = fullSize.height - CGFloat(minValue) * stepYFraction + yOffset - bottomYPadding
        let minY = fullSize.height - CGFloat(maxValue) * stepYFraction + yOffset - bottomYPadding
        return (minValue: minValue, minY: minY, maxValue: maxValue, maxY: maxY)
    }

    private func firstHourDate() -> Date {
        let firstDate = glucose.first?.dateString ?? Date()
        return firstDate.dateTruncated(from: .minute)!
    }

    private func firstHourPosition(viewWidth: CGFloat) -> CGFloat {
        let firstDate = glucose.first?.dateString ?? Date()
        let firstHour = firstHourDate()

        let lastDeltaTime = firstHour.timeIntervalSince(firstDate)
        let oneSecondWidth = oneSecondStep(viewWidth: viewWidth)
        return oneSecondWidth * CGFloat(lastDeltaTime)
    }
}
