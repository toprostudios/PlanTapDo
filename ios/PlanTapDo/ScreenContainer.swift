// ScreenContainer.swift
import SwiftUI
import UIKit

enum AppHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

extension View {
    /// Dismisses the keyboard for taps outside the active text input without
    /// preventing the tapped control from receiving its normal action.
    func dismissKeyboardWhenBackgroundTapped() -> some View {
        background(KeyboardDismissalTapDetector())
    }

    /// A shared, low-chrome input treatment that feels at home beside the app's
    /// cards instead of falling back to the dated system bordered-field look.
    func modernTextInput() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.035), radius: 5, y: 2)
    }

    func modernTextEditor(minHeight: CGFloat = 132) -> some View {
        scrollContentBackground(.hidden)
            .padding(9)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    func tactilePress() -> some View {
        buttonStyle(TactileButtonStyle())
    }
}

private struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
}

/// A window-level recognizer is needed because `Form`, sheets, and scroll views
/// often consume SwiftUI tap gestures before a parent view sees them.
private struct KeyboardDismissalTapDetector: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissalDetectorView {
        KeyboardDismissalDetectorView()
    }

    func updateUIView(_ uiView: KeyboardDismissalDetectorView, context: Context) {}
}

private final class KeyboardDismissalDetectorView: UIView, UIGestureRecognizerDelegate {
    private var tapRecognizer: UITapGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard let window, tapRecognizer == nil else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
        tapRecognizer = recognizer
    }

    deinit {
        if let tapRecognizer {
            tapRecognizer.view?.removeGestureRecognizer(tapRecognizer)
        }
    }

    @objc private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Let tapping an input focus it normally; any other tap dismisses the
        // currently focused input, including taps on Form rows and buttons.
        var view = touch.view
        while let currentView = view {
            if currentView is UITextField || currentView is UITextView {
                return false
            }
            view = currentView.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // This recognizer only observes taps to dismiss the keyboard. Controls
        // such as Start, Pause, and Save must still receive their own gesture.
        true
    }
}

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
