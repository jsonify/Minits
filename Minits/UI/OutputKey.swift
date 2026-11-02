import SK1Tokens
import SK1UI
import SwiftUI
#if os(iOS)
import AVKit
#endif

/// The AirPlay key: a cream SK-1 key that opens iOS's list of places to play sound (this iPhone, Bluetooth,
/// AirPlay). It's lit, with the orange bar, while sound goes to another device. iPhone only: on the Mac, sound goes
/// wherever the system's output is set, so this draws nothing there.
///
/// The key face is drawn by SwiftUI; an invisible `AVRoutePickerView` over it takes the tap, since only that view can
/// open the system's route list.
struct OutputKey: View {
    @Environment(\.audioRoute) private var route

    var body: some View {
        #if os(iOS)
        Button {} label: { Image(systemName: "airplayaudio") }
            .buttonStyle(.sk1Key(isOn: route.deviceName != nil))
            .allowsHitTesting(false)
            .overlay { RoutePicker() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Choose where sound plays"))
            .accessibilityValue(Text(route.deviceName ?? "This iPhone"))
            .accessibilityAddTraits(.isButton)
        #else
        EmptyView()
        #endif
    }
}

/// A line under Review's LCD or the Transcript's keys, shown only while sound goes to another device: where it's
/// going, and how to bring it back.
struct OutputNote: View {
    @Environment(\.audioRoute) private var route

    var body: some View {
        if let name = route.deviceName {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SKLamp(color: .orange, lit: true, glow: 3, size: 7, label: "Playing elsewhere")
                Text(AudioRoute.note(deviceName: name))
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#if os(iOS)
/// The system's route button with its own icon hidden; `OutputKey` draws the key under it.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        picker.prioritizesVideoDevices = false
        picker.backgroundColor = .clear
        // VoiceOver reads the key, not this.
        picker.isAccessibilityElement = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
