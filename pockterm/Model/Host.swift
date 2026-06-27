import Foundation
import SwiftData

@Model final class Host {
    var id: UUID
    var label: String
    var address: String
    var port: Int
    var identity: Identity?
    var startupSnippet: String?
    init(id: UUID = UUID(), label: String, address: String, port: Int = 22,
         identity: Identity? = nil, startupSnippet: String? = nil) {
        self.id = id
        self.label = label
        self.address = address
        self.port = port
        self.identity = identity
        self.startupSnippet = startupSnippet
    }
}
