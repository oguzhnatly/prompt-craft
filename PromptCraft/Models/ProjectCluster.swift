import Foundation

/// Represents a detected project cluster from DBSCAN clustering
/// of context entries based on semantic similarity.
struct ProjectCluster: Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var color: String
    let createdAt: Date
    var entryCount: Int
    var centroid: [Float]?

    init(
        id: UUID = UUID(),
        displayName: String,
        color: String,
        createdAt: Date = Date(),
        entryCount: Int = 0,
        centroid: [Float]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.color = color
        self.createdAt = createdAt
        self.entryCount = entryCount
        self.centroid = centroid
    }
}
