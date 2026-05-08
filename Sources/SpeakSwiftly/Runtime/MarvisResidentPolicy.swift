import Foundation

package extension SpeakSwiftly {
    enum MarvisResidentPolicy: String, Codable, Equatable, CaseIterable {
        case dualResidentSerialized = "dual_resident_serialized"
        case singleResidentDynamic = "single_resident_dynamic"
    }
}
