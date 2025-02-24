import Foundation

struct BloodGlucose: JSON, Identifiable, Hashable {
    enum Direction: String, JSON {
        case tripleUp = "TripleUp"
        case doubleUp = "DoubleUp"
        case singleUp = "SingleUp"
        case fortyFiveUp = "FortyFiveUp"
        case flat = "Flat"
        case fortyFiveDown = "FortyFiveDown"
        case singleDown = "SingleDown"
        case doubleDown = "DoubleDown"
        case tripleDown = "TripleDown"
        case none = "NONE"
        case notComputable = "NOT COMPUTABLE"
        case rateOutOfRange = "RATE OUT OF RANGE"
    }

    var _id = UUID().uuidString
    var id: String {
        _id
    }

    var sgv: Int?
    let direction: Direction?
    let date: UInt64
    let dateString: Date
    let filtered: Double?
    let noise: Int?

    var glucose: Int?

    var isStateValid: Bool { sgv ?? 0 >= 39 && noise ?? 1 != 4 }
}

enum GlucoseUnits: String, JSON {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"

    static let exchangeRate: Decimal = 0.0555
}

extension Int {
    var asMmolL: Decimal {
        Decimal(self) * GlucoseUnits.exchangeRate
    }
}

extension Decimal {
    var asMmolL: Decimal {
        self * GlucoseUnits.exchangeRate
    }

    var asMgdL: Decimal {
        self / GlucoseUnits.exchangeRate
    }
}

extension Double {
    var asMmolL: Decimal {
        Decimal(self) * GlucoseUnits.exchangeRate
    }

    var asMgdL: Decimal {
        Decimal(self) / GlucoseUnits.exchangeRate
    }
}
