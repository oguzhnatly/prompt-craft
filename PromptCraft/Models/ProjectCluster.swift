import Foundation

/// Represents a detected project cluster from DBSCAN clustering
/// of context entries based on semantic similarity.
struct ProjectCluster: Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var customName: String?
    var isHidden: Bool
    var color: String
    let createdAt: Date
    var entryCount: Int
    var centroid: [Float]?

    var effectiveDisplayName: String {
        let trimmedCustom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedCustom.isEmpty ? displayName : trimmedCustom
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        customName: String? = nil,
        isHidden: Bool = false,
        color: String,
        createdAt: Date = Date(),
        entryCount: Int = 0,
        centroid: [Float]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.customName = customName
        self.isHidden = isHidden
        self.color = color
        self.createdAt = createdAt
        self.entryCount = entryCount
        self.centroid = centroid
    }
}
