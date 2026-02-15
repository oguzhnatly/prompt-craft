import Combine
import Foundation

final class TemplateService: ObservableObject {
    static let shared = TemplateService()

    @Published private(set) var templates: [PromptTemplate] = []
    @Published private(set) var deletedBuiltInIDs: Set<UUID> = []

    private let storageURL: URL
    private let deletedBuiltInURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("PromptCraft", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageURL = appDir.appendingPathComponent("custom_templates.json")
        self.deletedBuiltInURL = appDir.appendingPathComponent("deleted_builtin_templates.json")

        loadTemplates()
    }

    // MARK: - Built-in Templates

    static let builtInTemplates: [PromptTemplate] = [
        PromptTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "Code Review Request",
            description: "Request a thorough code review with specific focus areas.",
            category: "Engineering",
            iconName: "magnifyingglass.circle",
            templateText: """
            Review the following {{language}} code for {{focus_area}}. The code is part of {{project_context}}:

            {{code}}

            Please provide:
            1. Issues found (bugs, security, performance)
            2. Suggestions for improvement
            3. Overall assessment
            """,
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            name: "Feature Specification",
            description: "Write a detailed feature specification from a high-level idea.",
            category: "Engineering",
            iconName: "list.clipboard",
            templateText: """
            Write a detailed feature specification for: {{feature_name}}

            Context: {{product_context}}
            Target users: {{target_users}}
            Key requirements: {{requirements}}

            Include user stories, acceptance criteria, technical considerations, and edge cases.
            """,
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            name: "Bug Investigation",
            description: "Investigate and diagnose a bug with structured context.",
            category: "Engineering",
            iconName: "ladybug",
            templateText: """
            Help me investigate and fix this bug:

            Expected behavior: {{expected_behavior}}
            Actual behavior: {{actual_behavior}}
            Steps to reproduce: {{steps_to_reproduce}}
            Environment: {{environment}}
            Error messages/logs: {{error_details}}

            Suggest likely root causes and debugging steps.
            """,
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            name: "Architecture Decision",
            description: "Evaluate architectural options for a technical decision.",
            category: "Engineering",
            iconName: "building.columns",
            templateText: """
            Help me make an architecture decision for {{system_component}}.

            Current situation: {{current_state}}
            Problem to solve: {{problem}}
            Options considered: {{options}}
            Constraints: {{constraints}}

            Evaluate each option with pros/cons, recommend an approach, and explain the trade-offs.
            """,
            isBuiltIn: true
        ),
        PromptTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            name: "Documentation Request",
            description: "Generate documentation for code, APIs, or processes.",
            category: "Communication",
            iconName: "doc.richtext",
            templateText: """
            Write {{documentation_type}} documentation for {{subject}}.

            Audience: {{audience}}
            Key topics to cover: {{topics}}
            Existing context: {{context}}

            Use clear language, include examples where helpful, and follow best practices for technical documentation.
            """,
            isBuiltIn: true
        ),
    ]

    // MARK: - CRUD

    func getAll() -> [PromptTemplate] {
        templates
    }

    func getById(_ id: UUID) -> PromptTemplate? {
        templates.first { $0.id == id }
    }

    func create(_ template: PromptTemplate) {
        var newTemplate = template
        newTemplate.createdAt = Date()
        newTemplate.modifiedAt = Date()
        templates.append(newTemplate)
        persistCustom()
    }

    func update(_ template: PromptTemplate) {
        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        var updated = template
        updated.modifiedAt = Date()
        templates[index] = updated
        persistCustom()
    }

    func delete(_ id: UUID) {
        guard let template = templates.first(where: { $0.id == id }) else { return }
        if template.isBuiltIn {
            deletedBuiltInIDs.insert(id)
            templates.removeAll { $0.id == id }
            persistDeletedBuiltIns()
        } else {
            templates.removeAll { $0.id == id }
            persistCustom()
        }
    }

    func duplicate(_ id: UUID) -> PromptTemplate? {
        guard let original = getById(id) else { return nil }
        let copy = PromptTemplate(
            name: "\(original.name) Copy",
            description: original.description,
            category: original.category,
            iconName: original.iconName,
            templateText: original.templateText,
            isBuiltIn: false
        )
        templates.append(copy)
        persistCustom()
        return copy
    }

    // MARK: - Built-in Restore

    func restoreAllBuiltIns() {
        deletedBuiltInIDs.removeAll()
        persistDeletedBuiltIns()
        loadTemplates()
    }

    var hasDeletedBuiltIns: Bool {
        !deletedBuiltInIDs.isEmpty
    }

    // MARK: - Import / Export

    func exportAsJSON(_ templateIDs: [UUID]? = nil) -> Data? {
        let toExport: [PromptTemplate]
        if let ids = templateIDs {
            toExport = templates.filter { ids.contains($0.id) }
        } else {
            toExport = templates.filter { !$0.isBuiltIn }
        }
        let envelope = TemplateExportEnvelope(templates: toExport)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(envelope)
    }

    func importFromJSON(_ data: Data) -> Int {
        guard let envelope = try? decoder.decode(TemplateExportEnvelope.self, from: data) else { return 0 }
        var count = 0
        for var template in envelope.templates {
            // Avoid ID conflicts with existing templates
            if templates.contains(where: { $0.id == template.id }) {
                let newTemplate = PromptTemplate(
                    name: template.name,
                    description: template.description,
                    category: template.category,
                    iconName: template.iconName,
                    templateText: template.templateText,
                    isBuiltIn: false
                )
                templates.append(newTemplate)
            } else {
                template.isBuiltIn = false
                templates.append(template)
            }
            count += 1
        }
        persistCustom()
        return count
    }

    // MARK: - Persistence

    private func loadTemplates() {
        // Load deleted built-in IDs
        if let data = try? Data(contentsOf: deletedBuiltInURL),
           let ids = try? decoder.decode(Set<UUID>.self, from: data) {
            deletedBuiltInIDs = ids
        }

        // Start with built-in templates, excluding deleted ones
        templates = Self.builtInTemplates.filter { !deletedBuiltInIDs.contains($0.id) }

        // Load custom templates
        if let data = try? Data(contentsOf: storageURL),
           let custom = try? decoder.decode([PromptTemplate].self, from: data) {
            templates.append(contentsOf: custom)
        }
    }

    private func persistCustom() {
        let custom = templates.filter { !$0.isBuiltIn }
        if let data = try? encoder.encode(custom) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private func persistDeletedBuiltIns() {
        if let data = try? encoder.encode(deletedBuiltInIDs) {
            try? data.write(to: deletedBuiltInURL, options: .atomic)
        }
    }
}
