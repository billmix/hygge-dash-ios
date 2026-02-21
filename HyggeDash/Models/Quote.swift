import Foundation

struct Quote: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let author: String

    var attributedText: String {
        "\"\(text)\"\n— \(author)"
    }
}
