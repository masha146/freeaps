import SwiftUI

extension AddTempTarget {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: AddTempTargetProvider {
        @Injected() private var storage: TempTargetsStorage!
        @Injected() private var settingsManager: SettingsManager!
        @Injected() var apsManager: APSManager!

        @Published var low: Decimal = 0
        @Published var high: Decimal = 0
        @Published var duration: Decimal = 0
        @Published var date = Date()
        @Published var newPresetName = ""
        @Published var presets: [TempTarget] = []

        private(set) var units: GlucoseUnits = .mmolL

        override func subscribe() {
            units = settingsManager.settings.units
            presets = storage.presets()
        }

        func enact() {
            var lowTarget = low
            var highTarget = high

            highTarget = max(highTarget, lowTarget)

            if units == .mmolL {
                lowTarget = lowTarget.asMgdL
                highTarget = highTarget.asMgdL
            }

            let entry = TempTarget(
                name: TempTarget.custom,
                createdAt: date,
                targetTop: highTarget,
                targetBottom: lowTarget,
                duration: duration,
                enteredBy: TempTarget.manual
            )
            storage.storeTempTargets([entry])
            apsManager.determineBasal().sink { _ in }.store(in: &lifetime)

            showModal(for: nil)
        }

        func cancel() {
            let entry = TempTarget(
                name: TempTarget.cancel,
                createdAt: Date(),
                targetTop: 0,
                targetBottom: 0,
                duration: 0,
                enteredBy: TempTarget.manual
            )
            storage.storeTempTargets([entry])
            apsManager.determineBasal().sink { _ in }.store(in: &lifetime)

            showModal(for: nil)
        }

        func save() {
            var lowTarget = low
            var highTarget = high

            highTarget = max(highTarget, lowTarget)

            if units == .mmolL {
                lowTarget = lowTarget.asMgdL
                highTarget = highTarget.asMgdL
            }

            let entry = TempTarget(
                name: newPresetName.isEmpty ? TempTarget.custom : newPresetName,
                createdAt: Date(),
                targetTop: highTarget,
                targetBottom: lowTarget,
                duration: duration,
                enteredBy: TempTarget.manual
            )

            presets.append(entry)
            storage.storePresets(presets)
        }

        func enactPreset(id: String) {
            if var preset = presets.first(where: { $0.id == id }) {
                preset.createdAt = Date()
                storage.storeTempTargets([preset])
                apsManager.determineBasal().sink { _ in }.store(in: &lifetime)
                showModal(for: nil)
            }
        }

        func removePreset(id: String) {
            presets = presets.filter { $0.id != id }
            storage.storePresets(presets)
        }
    }
}
