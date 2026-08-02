import SwiftUI

struct MetricCard: View {
    let title: LocalizedStringResource
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .foregroundStyle(tint)

            Text(value)
                .font(.title)
                .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .shadow(color: tint.opacity(0.12), radius: 10, y: 5)
    }
}
