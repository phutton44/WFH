import SwiftUI

struct DaysExplainedSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use this as the key for colours and labels on the Record calendar.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(DayTypeInfo.allExplained) { item in
                            DayTypeDescriptionTile(item: item)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Days Explained")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3.weight(.bold))
                    }
                    .buttonStyle(.plain)
                        .foregroundStyle(Color.holidayGreen)
                        .accessibilityLabel("Close")
                }
            }
        }
    }
}
