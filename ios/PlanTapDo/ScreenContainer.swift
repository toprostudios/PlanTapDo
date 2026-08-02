// ScreenContainer.swift
import SwiftUI

struct ScreenContainer<Content: View>: View {
    let maxWidth: CGFloat
    let content: Content

    init(maxWidth: CGFloat = 600, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    content
                        .frame(maxWidth: min(maxWidth, geometry.size.width - 24))
                }
                .frame(width: geometry.size.width)
                .frame(minHeight: geometry.size.height, alignment: .top)
                .padding(.vertical, 8)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background {
            ZStack {
                Color(uiColor: .systemGroupedBackground)

                LinearGradient(
                    colors: [
                        Color.indigo.opacity(0.12),
                        Color.purple.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
    }
}
