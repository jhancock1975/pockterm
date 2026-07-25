import Foundation
import SwiftData

@Model final class Host {
    var id: UUID
    var label: String
    var address: String
    var port: Int
    var identity: Identity?
    var startupSnippet: String?
    var group: HostGroup?
    var isFavorite: Bool
    var lastConnectedAt: Date?
    var themeID: String?
    var fontID: String?
    var fontSize: Int = 0
    init(id: UUID = UUID(), label: String, address: String, port: Int = 22,
         identity: Identity? = nil, startupSnippet: String? = nil,
         group: HostGroup? = nil, isFavorite: Bool = false, lastConnectedAt: Date? = nil,
         themeID: String? = nil, fontID: String? = nil, fontSize: Int = 0) {
        self.id = id
        self.label = label
        self.address = address
        self.port = port
        self.identity = identity
        self.startupSnippet = startupSnippet
        self.group = group
        self.isFavorite = isFavorite
        self.lastConnectedAt = lastConnectedAt
        self.themeID = themeID
        self.fontID = fontID
        self.fontSize = fontSize
    }
}
