import Combine
import Foundation

final class TemplateEditorViewModel: ObservableObject {

    // MARK: - Mode

    enum Mode: Equatable {
        case create
        case edit(UUID)
        case readOnly(UUID)

        var isReadOnly: Bool {
            if case .readOnly = self { return true }
            return false
        }

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create): return true
            case (.edit(let a), .edit(let b)): return a == b
            case (.readOnly(let a), .readOnly(let b)): return a == b
            default: return false
            }
        }
    }

    let mode: Mode

    // MARK: - Draft State

    @Published var name: String = ""
    @Published var description: String = ""
    @Published var category: String = "General"
    @Published var iconName: String = "doc.text"
    @Published var templateText: String = ""

    // MARK: - Validation

    @Published var nameError: String?
    @Published var templateTextError: String?

    // MARK: - Dirty Tracking

    @Published var isDirty: Bool = false
    @Published var showDiscardAlert: Bool = false

    // MARK: - Services

    private let templateService: TemplateService
    private var cancellables = Set<AnyCancellable>()
    private var originalTemplate: PromptTemplate?

    // MARK: - Static Data

    static let categoryPresets: [String] = [
        "General", "Engineering", "Communication", "Research", "Creative", "Business",
    ]

    static let availableIcons: [String] = [
        "doc.text", "list.clipboard", "magnifyingglass.circle", "ladybug", "building.columns",
        "doc.richtext", "sparkles", "hammer", "pencil", "lightbulb",
        "chart.bar", "envelope", "person", "globe", "gearshape",
        "book", "star", "bolt", "flame", "leaf",
        "cpu", "terminal", "list.bullet", "checkmark.circle", "wand.and.stars",
        "text.alignleft", "paperplane", "lock", "arrow.triangle.branch", "paintbrush",
    ]

    // MARK: - Init

    init(mode: Mode, templateService: TemplateService = .shared) {
        self.mode = mode
        self.templateService = templateService

        switch mode {
        case .create:
            break
        case .edit(let id), .readOnly(let id):
            if let template = templateService.getById(id) {
                loadTemplate(template)
                originalTemplate = template
            }
        }

        observeChanges()
    }

    // MARK: - Load

    private func loadTemplate(_ template: PromptTemplate) {
        name = template.name
        description = template.description
        category = template.category
        iconName = template.iconName
        templateText = template.templateText
    }

    // MARK: - Observe Changes

    private func observeChanges() {
        Publishers.CombineLatest4($name, $description, $category, $iconName)
            .dropFirst()
            .sink { [weak self] _ in self?.isDirty = true }
            .store(in: &cancellables)

        $templateText
            .dropFirst()
            .sink { [weak self] _ in self?.isDirty = true }
            .store(in: &cancellables)
    }

    // MARK: - Computed

    var extractedPlaceholders: [String] {
        let pattern = "\\{\\{([^}]+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = templateText as NSString
        let matches = regex.matches(in: templateText, range: NSRange(location: 0, length: nsString.length))
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            let name = nsString.substring(with: match.range(at: 1))
            if !seen.contains(name) {
                seen.insert(name)
                result.append(name)
            }
        }
        return result
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !templateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var navigationTitle: String {
        switch mode {
        case .create: return "New Template"
        case .edit: return "Edit Template"
        case .readOnly: return "View Template"
        }
    }

    var saveButtonTitle: String {
        switch mode {
        case .create: return "Create"
        case .edit: return "Save"
        case .readOnly: return ""
        }
    }

    // MARK: - Validation

    func validate() -> Bool {
        nameError = nil
        templateTextError = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            nameError = "Name is required."
            return false
        }
        if trimmedName.count > 60 {
            nameError = "Name must be 60 characters or less."
            return false
        }

        let trimmedText = templateText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            templateTextError = "Template text is required."
            return false
        }

        return true
    }

    // MARK: - Save

    @discardableResult
    func save() -> PromptTemplate? {
        guard validate() else { return nil }

        switch mode {
        case .create:
            let template = PromptTemplate(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                iconName: iconName,
                templateText: templateText,
                isBuiltIn: false
            )
            templateService.create(template)
            isDirty = false
            return template

        case .edit(let id):
            guard var existing = templateService.getById(id) else { return nil }
            existing.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.category = category
            existing.iconName = iconName
            existing.templateText = templateText
            templateService.update(existing)
            isDirty = false
            return existing

        case .readOnly:
            return nil
        }
    }
}
