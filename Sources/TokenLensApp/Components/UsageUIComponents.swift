import SwiftUI

struct StatLine: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .fontWeight(.medium)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
