import AppKit
import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            VStack(spacing: 8) {
                Text("Welcome to DockFlip")
                    .font(.system(size: 32, weight: .bold))
                Text("Your Dock works like the Windows taskbar, ⌘Tab switches windows, and windows snap into place — in one small app that works as soon as it starts.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                FeatureCard(symbol: "menubar.dock.rectangle", title: "Dock",
                            text: "Rest on an icon to see its windows and tabs. Click to minimize and restore.")
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

struct AccessibilityStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(
                symbol: "accessibility",
                title: "Allow Accessibility",
                subtitle: "DockFlip needs one permission. It is used to list, focus, move and minimize windows, and for the ⌘Tab and ⌃⌥ shortcuts."
            )

            HStack(spacing: 14) {
                Image(systemName: model.granted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 22))
                    .foregroundStyle(model.granted ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.granted ? LocalizedStringKey("Accessibility: allowed") : LocalizedStringKey("Accessibility: not yet allowed"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.granted ? LocalizedStringKey("All set. Continue to the next step.") : LocalizedStringKey("Turn on DockFlip in the list. This page notices it by itself."))
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

            if !model.granted {
                HStack(spacing: 10) {
                    Text("DockFlip is already switched on in the list, but nothing changes?")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Reset Permission") {
                        Permissions.resetAccessibility()
                        Permissions.requestAccessibility()
                    }
                    .controlSize(.small)
                }
            }

            PrivacyNote(text: "DockFlip has no networking code and no third-party code. Nothing it sees leaves your Mac.")
            Spacer(minLength: 0)
        }
    }
}

struct PreviewsStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeader(
                symbol: "rectangle.on.rectangle",
                title: "Show window thumbnails?",
                subtitle: "Choose how windows look in the Dock list and in ⌘Tab. You can change this later in Settings."
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

            PrivacyNote(text: "Screen recording permission technically gives access to everything on screen. DockFlip captures only a small image of one window, only while you rest on a Dock icon or use ⌘Tab, keeps it in memory only and never while a password field is active.")
            Spacer(minLength: 0)
        }
    }
}

struct FinishStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(
                symbol: "checkmark.seal",
                title: "Almost done",
                subtitle: "One quick adjustment makes DockFlip work like Windows. It is a single click."
            )

            VStack(spacing: 0) {
                SetupRow(
                    done: !model.nativeTilingOn,
                    title: "Turn off macOS edge tiling",
                    text: "macOS tiles windows dragged to screen edges too. Two snapping systems would fight.",
                    actionTitle: "Turn Off"
                ) {
                    NativeEdgeTiling.turnOff()
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
