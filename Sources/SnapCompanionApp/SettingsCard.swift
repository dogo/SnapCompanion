import SwiftUI

struct SettingsCard<Content: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color
    let content: Content

    init(
        title: LocalizedStringResource,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.title2)
            .bold()
            .foregroundStyle(tint)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .shadow(color: tint.opacity(0.1), radius: 10, y: 5)
    }
}
