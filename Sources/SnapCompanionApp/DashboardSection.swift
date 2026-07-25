import Foundation

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case collection
    case decks
    case session
    case settings

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .overview: .sectionOverview
        case .collection: .sectionCollection
        case .decks: .sectionDecks
        case .session: .sectionSession
        case .settings: .sectionSettings
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .collection: "rectangle.stack.fill"
        case .decks: "square.stack.3d.up.fill"
        case .session: "chart.bar.fill"
        case .settings: "gearshape"
        }
    }
}
