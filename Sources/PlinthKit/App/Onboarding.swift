import AppKit
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, accessibility, previews, finish
    }

    @Published var step: Step = .welcome
    @Published var granted = Permissions.isAccessibilityTrusted
    /// nil until the user chooses — nothing is preselected.
    @Published var previews: Bool?
    @Published var dockFitted = SystemTweaks.isDockFitted
    @Published var nativeTilingOn = SystemTweaks.isNativeEdgeTilingOn
    @Published var launchAtLogin = true

    var onFinish: (() -> Void)?

    var canContinue: Bool {
        switch step {
        case .welcome, .finish: return true
        case .accessibility: return granted
        case .previews: return previews != nil
        }
    }

    func next() {
        guard canContinue else { return }
        if let following = Step(rawValue: step.rawValue + 1) {
            withAnimation(.snappy(duration: 0.35)) { step = following }
        } else {
            onFinish?()
        }
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.snappy(duration: 0.35)) { step = previous }
    }
}

/// First-run setup: what Plinth is, the one required permission, the previews
/// choice (nothing preselected), and fitting the Dock and macOS tiling to Plinth.
/// The only timer in the app lives here, and only while this window is open.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private let model = OnboardingModel()
    private var window: NSWindow?
    private var timer: Timer?
    private var axObserver: NSObjectProtocol?
    private let onDone: () -> Void

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        super.init()
        model.onFinish = { [weak self] in self?.finish() }
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.title = L("Plinth Setup")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: OnboardingView.width, height: OnboardingView.height))
            window.center()
            self.window = window
        }
        model.granted = Permissions.isAccessibilityTrusted
        model.dockFitted = SystemTweaks.isDockFitted
        model.nativeTilingOn = SystemTweaks.isNativeEdgeTilingOn
        startWatching()
        if let window { WindowPresenter.bringToFront(window) }
    }

    func windowWillClose(_ notification: Notification) {
        stopWatching()
        window = nil
        // Closed early: if the permission is there, Plinth still starts.
        if Permissions.isAccessibilityTrusted {
            Settings.shared.onboardingCompleted = true
            onDone()
        }
    }

    private func startWatching() {
        guard timer == nil else { return }
        axObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self?.check()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        if let axObserver {
            DistributedNotificationCenter.default().removeObserver(axObserver)
        }
        axObserver = nil
    }

    private func check() {
        let trusted = Permissions.isAccessibilityTrusted
        if trusted != model.granted {
            withAnimation(.snappy) { model.granted = trusted }
        }
    }

    private func finish() {
        guard Permissions.isAccessibilityTrusted else { return }
        let settings = Settings.shared
        settings.previewsEnabled = model.previews ?? false
        if settings.previewsEnabled { PreviewProvider.requestPermission() }
        if model.launchAtLogin != settings.launchAtLogin { settings.launchAtLogin = model.launchAtLogin }
        settings.onboardingCompleted = true

        stopWatching()
        window?.delegate = nil // windowWillClose must not run onDone a second time
        window?.close()
        window = nil
        onDone()
    }
}

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
                ForEach(OnboardingModel.Step.allCases, id: \.rawValue) { step in
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
        case .finish: return "Start Using Plinth"
        default: return "Continue"
        }
    }
}

private struct StepHeader: View {
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

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            VStack(spacing: 8) {
                Text("Welcome to Plinth")
                    .font(.system(size: 32, weight: .bold))
                Text("The Windows taskbar, ⌘Tab window switching and window snapping — in one small app that works as soon as it starts.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                FeatureCard(symbol: "menubar.dock.rectangle", title: "Taskbar",
                            text: "Every window one click away. Hover a button to see its windows.")
                FeatureCard(symbol: "command", title: "⌘Tab",
                            text: "Switch between windows, not just apps.")
                FeatureCard(symbol: "rectangle.split.2x1", title: "Snapping",
                            text: "Drag to an edge or press ⌃⌥ and an arrow.")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeatureCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(
                symbol: "accessibility",
                title: "Allow Accessibility",
                subtitle: "Plinth needs one permission. It is used to list, focus, move and minimize windows, and for the ⌘Tab and ⌃⌥ shortcuts."
            )

            HStack(spacing: 14) {
                Image(systemName: model.granted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 22))
                    .foregroundStyle(model.granted ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.granted ? LocalizedStringKey("Accessibility: allowed") : LocalizedStringKey("Accessibility: not yet allowed"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.granted ? LocalizedStringKey("All set. Continue to the next step.") : LocalizedStringKey("Turn on Plinth in the list. This page notices it by itself."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.granted {
                    Button("Open System Settings") { Permissions.requestAccessibility() }
                        .controlSize(.large)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

            PrivacyNote(text: "Plinth has no networking code and no third-party code. Nothing it sees leaves your Mac.")
            Spacer(minLength: 0)
        }
    }
}

private struct PreviewsStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeader(
                symbol: "rectangle.on.rectangle",
                title: "Show window thumbnails?",
                subtitle: "Choose how windows look in the taskbar and in ⌘Tab. You can change this later in Settings."
            )

            HStack(spacing: 14) {
                ChoiceCard(
                    selected: model.previews == false,
                    symbol: "list.bullet.rectangle",
                    title: "Icon and title",
                    text: "No extra permission. Windows are told apart by title and a mini-map of where they are on screen."
                ) { model.previews = false }
                ChoiceCard(
                    selected: model.previews == true,
                    symbol: "photo.on.rectangle",
                    title: "Thumbnails",
                    text: "Needs the Screen & System Audio Recording permission."
                ) { model.previews = true }
            }

            PrivacyNote(text: "Screen recording permission technically gives access to everything on screen. Plinth captures only a small image of one window, only while you hover the taskbar or use ⌘Tab, keeps it in memory and never while a password field is active.")
            Spacer(minLength: 0)
        }
    }
}

private struct ChoiceCard: View {
    let selected: Bool
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct FinishStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "checkmark.seal",
                title: "Almost done",
                subtitle: "Two quick adjustments make Plinth work like Windows. Each one is a single click."
            )

            VStack(spacing: 0) {
                SetupRow(
                    done: model.dockFitted,
                    title: "Fit the Dock under the taskbar",
                    text: "Keeps the Dock at the bottom, always visible and small, so maximized windows stop at the taskbar.",
                    actionTitle: "Fit"
                ) {
                    SystemTweaks.fitDock()
                    withAnimation(.snappy) { model.dockFitted = true }
                }
                Divider().padding(.leading, 52)
                SetupRow(
                    done: !model.nativeTilingOn,
                    title: "Turn off macOS edge tiling",
                    text: "macOS tiles windows dragged to screen edges too. Two snapping systems would fight.",
                    actionTitle: "Turn Off"
                ) {
                    SystemTweaks.disableNativeEdgeTiling()
                    withAnimation(.snappy) { model.nativeTilingOn = false }
                }
                Divider().padding(.leading, 52)
                HStack(spacing: 14) {
                    Image(systemName: "power")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    Text("Launch at login").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: $model.launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))

            HStack(spacing: 18) {
                ShortcutHint(keys: "⌘ Tab", text: "Switch windows")
                ShortcutHint(keys: "⌃⌥ ← →", text: "Snap left or right")
                ShortcutHint(keys: "⌃⌥ ↑", text: "Maximize")
            }
            Spacer(minLength: 0)
        }
    }
}

private struct SetupRow: View {
    let done: Bool
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18))
                .foregroundStyle(done ? Color.green : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if done {
                Text("Done").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            } else {
                Button(actionTitle, action: action)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ShortcutHint: View {
    let keys: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

private struct PrivacyNote: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
