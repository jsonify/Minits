import SK1Tokens
import SK1UI
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The first-run intro, shown once over Home on a fresh install: what Minits does in three steps, that it all stays on
/// the device, the reminder to tell everyone they're being recorded, and the microphone.
///
/// SK-1 look: an LCD header (WELCOME), the three steps as numbered sunken trays, a teal lamp for "on this device", an
/// amber lamp for the consent reminder, and the microphone's state as a lamp (teal on, red off). The orange key at
/// the bottom asks for the microphone, or, once that's answered, gets started; "Not now" skips asking.
struct IntroView: View {
    /// Called when it's done (Get started or Not now).
    let finish: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var mic: AudioRecorder.Permission
    @State private var asking = false

    /// `mic` is the microphone's state to start from; the app reads the real one.
    init(mic: AudioRecorder.Permission = AudioRecorder.permission, finish: @escaping () -> Void) {
        _mic = State(initialValue: mic)
        self.finish = finish
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SKCaption("Minits · MN-1")
                header
                Text("Record a meeting on this phone or Mac. Minits works out who said what and drafts the minutes or a summary.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                    SKCaption("How it works")
                    VStack(spacing: 8) {
                        step(1, "Record",
                             "Put the phone in the middle of the table and tap Record. It keeps going with the screen locked.")
                        step(2, "Who said what",
                             "Each member reads one sentence, once, so Minits learns their voice. After the meeting it names every line and asks you about the ones it isn't sure of.")
                        step(3, "Minutes or a summary",
                             "A board meeting gets formal minutes with motions and votes; an ad-hoc meeting gets a plain summary. Edit it, share it or save a PDF.")
                    }
                }

                note(lamp: .teal, caption: "On this device",
                     text: "The recording, the voices, the transcript and the minutes never leave this device. No account, no cloud.")
                note(lamp: .warning, caption: "Before you record",
                     text: "Let everyone know the meeting is being recorded. California and some other states require everyone's consent.")

                microphone
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .sk1Chassis()
        .safeAreaInset(edge: .bottom) { footer }
        .interactiveDismissDisabled()
    }

    private var palette: SK1.Palette { SK1.palette(for: scheme) }

    // MARK: Parts

    private var header: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        return SKLCD {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("WELCOME")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .lineLimit(1)
                    Text("RECORD · WHO SAID WHAT · MINUTES")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                SKSevenSegment("123", digitHeight: 30, spacing: 4)
                    .shadow(color: ink.opacity(0.15), radius: 0, x: 1, y: 1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Welcome to Minits: record, who said what, minutes"))
    }

    private func step(_ number: Int, _ title: String, _ text: String) -> some View {
        SKWell {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SKChip("\(number)", minWidth: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(sk1Hex: palette.ink))
                    Text(text)
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(number), \(title). \(text)"))
    }

    private func note(lamp: SKLampColor, caption: String, text: String) -> some View {
        SKWell {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SKLamp(color: lamp, lit: true, glow: 4, size: 7)
                    SKCaption(caption)
                }
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(sk1Hex: palette.ink))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Microphone")
            SKWell {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SKLamp(color: micLamp, lit: mic != .undetermined, glow: 4, size: 7, label: micStatus)
                        Text(micText)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(sk1Hex: palette.ink))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    #if os(iOS)
                    if mic == .denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.sk1Key(.cream))
                    }
                    #endif
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var micLamp: SKLampColor {
        switch mic {
        case .granted: return .success
        case .denied: return .danger
        case .undetermined: return .teal
        }
    }

    private var micStatus: String {
        switch mic {
        case .granted: return "Microphone on"
        case .denied: return "Microphone off"
        case .undetermined: return "Not asked yet"
        }
    }

    private var micText: String {
        switch mic {
        case .undetermined:
            return "Minits needs the microphone to record meetings and voice samples. You'll be asked once."
        case .granted:
            return "The microphone is on. You're ready to record."
        case .denied:
            #if os(iOS)
            return "The microphone is off, so Minits can't record. Turn it on in Settings › Privacy & Security › Microphone."
            #else
            return "The microphone is off, so Minits can't record. Turn it on in System Settings › Privacy & Security › Microphone."
            #endif
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            if mic == .undetermined {
                Button {
                    Task { await askForMicrophone() }
                } label: {
                    Label("Allow microphone", systemImage: "mic.fill")
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
                .disabled(asking)
                Button("Not now", action: finish)
                    .buttonStyle(.sk1Key(.cream))
            } else {
                Button(action: finish) {
                    Label("Get started", systemImage: "arrow.right")
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color(sk1Hex: palette.chassis)
                SKGroove()
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func askForMicrophone() async {
        asking = true
        _ = await AudioRecorder.requestPermission()
        mic = AudioRecorder.permission
        asking = false
    }
}

extension View {
    /// Shows `IntroView` over everything: full screen on iPhone, a sheet on Mac.
    func introCover(isPresented: Binding<Bool>, finish: @escaping () -> Void) -> some View {
        #if os(iOS)
        return fullScreenCover(isPresented: isPresented) { IntroView(finish: finish) }
        #else
        return sheet(isPresented: isPresented) {
            IntroView(finish: finish)
                .frame(minWidth: 440, idealWidth: 480, minHeight: 640, idealHeight: 760)
        }
        #endif
    }
}
