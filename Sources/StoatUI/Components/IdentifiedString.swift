import SwiftUI

struct IdentifiedString: Identifiable {
    let value: String
    var id: String { value }
}
