// ScreenContainer.swift
import SwiftUI
import UIKit

@MainActor
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
                    .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }

    func modernTextEditor(minHeight: CGFloat = 132) -> some View {
        scrollContentBackground(.hidden)
            .padding(9)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92))
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
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

@MainActor
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
            AppCanvasBackground()
        }
    }
}

struct AppCanvasBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.16),
                    Color.purple.opacity(0.055),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.075), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 440
            )
        }
        .ignoresSafeArea()
    }
}

/// A compact one-column date picker for short-horizon planning. It avoids the
/// separate month/day/year wheels used by the system date picker.
struct RelativeDayWheelPicker: View {
    @Binding var date: Date
    var dayRange: ClosedRange<Int> = 0...365

    var body: some View {
        Picker("Day", selection: dayOffset) {
            ForEach(availableOffsets, id: \.self) { offset in
                Text(label(for: offset)).tag(offset)
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 126)
        .clipped()
    }

    private var availableOffsets: [Int] {
        var offsets = Array(dayRange)
        let current = currentDayOffset
        if !dayRange.contains(current) {
            offsets.append(current)
            offsets.sort()
        }
        return offsets
    }

    private var currentDayOffset: Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
    }

    private var dayOffset: Binding<Int> {
        Binding(
            get: { currentDayOffset },
            set: { offset in
                let calendar = Calendar.current
                guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { return }
                let time = calendar.dateComponents([.hour, .minute], from: date)
                date = calendar.date(
                    bySettingHour: time.hour ?? 9,
                    minute: time.minute ?? 0,
                    second: 0,
                    of: day
                ) ?? day
            }
        )
    }

    private func label(for offset: Int) -> String {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: offset, to: Date()) else { return "Choose date" }
        switch offset {
        case 0: return "Today · " + day.formatted(.dateTime.weekday(.wide))
        case 1: return "Tomorrow · " + day.formatted(.dateTime.weekday(.wide))
        default: return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
    }
}

/// An appointment time picker with a five-minute minute wheel, preventing
/// accidental times such as 9:08 while preserving normal wheel interaction.
struct FiveMinuteTimePicker: View {
    @Binding var date: Date

    var body: some View {
        HStack(spacing: -6) {
            Picker("Hour", selection: hour) {
                ForEach(0..<24, id: \.self) { value in
                    Text(hourLabel(value)).tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 142)

            Picker("Minute", selection: minute) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { value in
                    Text(String(format: ":%02d", value)).tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 92)
        }
        .frame(height: 126)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private var hour: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: date) },
            set: { setTime(hour: $0, minute: Calendar.current.component(.minute, from: date)) }
        )
    }

    private var minute: Binding<Int> {
        Binding(
            get: { (Calendar.current.component(.minute, from: date) / 5) * 5 },
            set: { setTime(hour: Calendar.current.component(.hour, from: date), minute: $0) }
        )
    }

    private func setTime(hour: Int, minute: Int) {
        date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    private func hourLabel(_ hour: Int) -> String {
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(displayHour) " + (hour < 12 ? "AM" : "PM")
    }
}
