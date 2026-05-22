import SwiftUI

struct WidgetTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.heavy))
            .tracking(0.8)
            .foregroundStyle(Color.primaryText)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
