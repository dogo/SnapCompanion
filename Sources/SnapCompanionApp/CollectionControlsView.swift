import SnapSyncCore
import SwiftUI

struct CollectionControlsView: View {
    @Binding var filter: CollectionFilter
    @Binding var sort: CollectionSort
    let resultCount: Int

    var body: some View {
        HStack {
            Label(.viewOptions, systemImage: "line.3.horizontal.decrease.circle.fill")
                .font(.headline)

            Spacer()

            Picker(selection: $filter) {
                ForEach(CollectionFilter.allCases) { option in
                    Label {
                        Text(option.title)
                    } icon: {
                        Image(systemName: option.systemImage)
                    }
                    .tag(option)
                }
            } label: {
                Text(.filter)
            }
            .pickerStyle(.menu)

            Picker(selection: $sort) {
                ForEach(CollectionSort.allCases) { option in
                    Label {
                        Text(option.title)
                    } icon: {
                        Image(systemName: option.systemImage)
                    }
                    .tag(option)
                }
            } label: {
                Text(.sort)
            }
            .pickerStyle(.menu)

            Text(.resultCount(resultCount))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

private extension CollectionFilter {
    var title: LocalizedStringResource {
        switch self {
        case .all: .filterAll
        case .owned: .filterOwned
        case .missing: .filterMissing
        case .withVariants: .filterWithVariants
        case .withBoosters: .filterWithBoosters
        case .withoutBoosters: .filterWithoutBoosters
        }
    }

    var systemImage: String {
        switch self {
        case .all: "rectangle.stack.fill"
        case .owned: "checkmark.circle.fill"
        case .missing: "lock.fill"
        case .withVariants: "sparkles"
        case .withBoosters: "arrow.up.circle.fill"
        case .withoutBoosters: "minus.circle"
        }
    }
}

private extension CollectionSort {
    var title: LocalizedStringResource {
        switch self {
        case .nameAscending: .sortNameAscending
        case .nameDescending: .sortNameDescending
        case .mostVariants: .sortMostVariants
        case .mostBoosters: .sortMostBoosters
        }
    }

    var systemImage: String {
        switch self {
        case .nameAscending, .nameDescending: "textformat.abc"
        case .mostVariants: "sparkles"
        case .mostBoosters: "arrow.up.circle.fill"
        }
    }
}
