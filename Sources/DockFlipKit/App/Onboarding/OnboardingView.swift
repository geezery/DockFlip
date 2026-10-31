import AppKit
import SwiftUI

// MARK: - Views

struct OnboardingView: View {
    static let width: CGFloat = 760
    static let height: CGFloat = 560

    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch model.step {
                case .welcome: WelcomeStep().transition(stepTransition)
                case .accessibility: AccessibilityStep(model: model).transition(stepTransition)
                case .previews: PreviewsStep(model: model).transition(stepTransition)
                case .finish: FinishStep(model: model).transition(stepTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 44)

            footer
        }
        .frame(width: Self.width, height: Self.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(model.steps, id: \.rawValue) { step in
                    Capsule()
                        .fill(step == model.step ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: step == model.step ? 22 : 7, height: 7)
                }
            }
            .animation(.snappy, value: model.step)

            Spacer()

            if model.step != .welcome {
                Button("Back") { model.back() }
                    .controlSize(.large)
            }
            Button {
                model.next()
            } label: {
                Text(primaryTitle).frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canContinue)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 22)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .top) { Divider() }
    }

    private var primaryTitle: LocalizedStringKey {
        switch model.step {
        case .welcome: return "Get Started"
        case .finish: return "Start Using DockFlip"
        default: return "Continue"
        }
    }
}

struct StepHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.12)))
            Text(title)
                .font(.system(size: 26, weight: .bold))
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
