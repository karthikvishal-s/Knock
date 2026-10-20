import Foundation
import SwiftData

public struct CategoryDraft: Equatable, Sendable {
    public var name: String
    public var emoji: String
    public var colorHex: String
    public var kind: CategoryKind
    public var parentID: UUID?

    public init(name: String = "", emoji: String = "🏷️", colorHex: String = "#8E8E93", kind: CategoryKind = .expense, parentID: UUID? = nil) {
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.kind = kind
        self.parentID = parentID
    }

    public init(category: LedgerCategory) {
        self.init(name: category.name, emoji: category.emoji, colorHex: category.colorHex, kind: category.kind, parentID: category.parent?.id)
    }
}

public enum CategoryError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case invalidParent
    case kindMismatch
    case inUse

    public var errorDescription: String? {
        switch self {
        case .emptyName: String(localized: "Give the category a name.")
        case .duplicateName: String(localized: "A category with that name already exists.")
        case .invalidParent: String(localized: "A category can't be nested under itself or under a sub-category.")
        case .kindMismatch: String(localized: "Both categories must be expense or both income.")
        case .inUse: String(localized: "This category has transactions. Archive or merge it instead.")
        }
    }
}

/// Category management: add, edit, reorder, archive, merge and delete-when-unused.
public struct CategoryService {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func categories(_ kind: CategoryKind, includeArchived: Bool = true) throws -> [LedgerCategory] {
        let raw = kind.rawValue
        let all = try context.fetch(FetchDescriptor<LedgerCategory>(predicate: #Predicate { $0.kindRaw == raw }, sortBy: [SortDescriptor(\.sortOrder)]))
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    @discardableResult
    public func add(_ draft: CategoryDraft) throws -> LedgerCategory {
        let name = try validatedName(draft, excluding: nil)
        let order = (try categories(draft.kind).map(\.sortOrder).max() ?? -1) + 1
        let category = LedgerCategory(name: name, emoji: draft.emoji, colorHex: draft.colorHex, kind: draft.kind, sortOrder: order)
        context.insert(category)
        category.parent = try validatedParent(draft.parentID, for: category, kind: draft.kind)
        try commit()
        return category
    }

    public func update(_ category: LedgerCategory, with draft: CategoryDraft) throws {
        let name = try validatedName(draft, excluding: category.id)
        guard draft.kind == category.kind else { throw CategoryError.kindMismatch }
        let parent = try validatedParent(draft.parentID, for: category, kind: draft.kind)
        category.name = name
        category.emoji = draft.emoji.isEmpty ? "🏷️" : draft.emoji
        category.colorHex = draft.colorHex
        category.parent = parent
        try commit()
    }

    public func setArchived(_ category: LedgerCategory, _ archived: Bool) throws {
        category.isArchived = archived
        try commit()
    }

    public func reorder(_ ids: [UUID], kind: CategoryKind) throws {
        let all = try categories(kind)
        for (index, id) in ids.enumerated() {
            all.first { $0.id == id }?.sortOrder = index
        }
        try commit()
    }

    /// Moves every transaction, budget, recurring rule and sub-category from `source` to
    /// `target`, adds up their usage, then deletes `source`.
    public func merge(_ source: LedgerCategory, into target: LedgerCategory) throws {
        guard source.id != target.id else { return }
        guard source.kind == target.kind else { throw CategoryError.kindMismatch }
        for entry in source.entries ?? [] { entry.category = target }
        // One budget per category: keep the target's if it has one.
        if (target.budgets ?? []).isEmpty {
            for budget in source.budgets ?? [] { budget.category = target }
        } else {
            for budget in source.budgets ?? [] { context.delete(budget) }
        }
        for rule in source.recurringRules ?? [] { rule.category = target }
        for child in source.children ?? [] where child.id != target.id { child.parent = target.parent == nil ? target : target.parent }
        if target.parent?.id == source.id { target.parent = nil }
        target.usageCount += source.usageCount
        if let used = source.lastUsedAt, used > (target.lastUsedAt ?? .distantPast) { target.lastUsedAt = used }
        source.entries = []
        source.budgets = []
        context.delete(source)
        try commit()
    }

    public func delete(_ category: LedgerCategory) throws {
        guard (category.entries ?? []).isEmpty else { throw CategoryError.inUse }
        for child in category.children ?? [] { child.parent = nil }
        context.delete(category)
        try commit()
    }

    private func validatedName(_ draft: CategoryDraft, excluding id: UUID?) throws -> String {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CategoryError.emptyName }
        let clash = try categories(draft.kind).contains { $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        guard !clash else { throw CategoryError.duplicateName }
        return name
    }

    /// Only one level of nesting: a parent must be a top-level category of the same kind.
    private func validatedParent(_ parentID: UUID?, for category: LedgerCategory, kind: CategoryKind) throws -> LedgerCategory? {
        guard let parentID else { return nil }
        guard parentID != category.id,
              let parent = try categories(kind).first(where: { $0.id == parentID }),
              parent.parent == nil,
              (category.children ?? []).isEmpty else { throw CategoryError.invalidParent }
        return parent
    }

    private func commit() throws {
        try context.save()
        StoreEvents.bump()
    }
}

public enum TagError: LocalizedError, Equatable {
    case emptyName

    public var errorDescription: String? { String(localized: "Give the tag a name.") }
}

public struct TagService {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func all() throws -> [LedgerTag] {
        try context.fetch(FetchDescriptor<LedgerTag>(sortBy: [SortDescriptor(\.name)]))
    }

    /// Returns the existing tag with this name (case-insensitive) or creates it.
    @discardableResult
    public func findOrCreate(named rawName: String, colorHex: String = "#8E8E93") throws -> LedgerTag {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !name.isEmpty else { throw TagError.emptyName }
        if let existing = try all().first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let tag = LedgerTag(name: name, colorHex: colorHex)
        context.insert(tag)
        try context.save()
        return tag
    }

    public func rename(_ tag: LedgerTag, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TagError.emptyName }
        tag.name = trimmed
        try context.save()
        StoreEvents.bump()
    }

    public func delete(_ tag: LedgerTag) throws {
        context.delete(tag)
        try context.save()
        StoreEvents.bump()
    }
}
