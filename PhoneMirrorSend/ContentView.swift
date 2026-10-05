import SwiftUI
import ReplayKit
import UIKit

/// Holds the system picker and can trigger its internal button, so we can present
/// our own clearly-visible button instead of the faint stock one.
final class BroadcastPickerCoordinator: ObservableObject {
    weak var picker: RPSystemBroadcastPickerView?

    func trigger() {
        guard let picker else { return }
        for case let button as UIButton in picker.subviews {
            button.sendActions(for: .allTouchEvents)
        }
    }
}

struct HiddenBroadcastPicker: UIViewRepresentable {
    let extensionIdentifier: String
    let coordinator: BroadcastPickerCoordinator

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = extensionIdentifier
        picker.showsMicrophoneButton = false
        coordinator.picker = picker
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var coordinator = BroadcastPickerCoordinator()

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("PhoneMirror")
                .font(.largeTitle.bold())
            Text("Emite la pantalla de este iPhone al Mac por Wi‑Fi.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            ZStack {
                HiddenBroadcastPicker(
                    extensionIdentifier: "com.edunavajas.phonemirror.send.broadcast",
                    coordinator: coordinator)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)

                Button {
                    coordinator.trigger()
                } label: {
                    Label("Iniciar emisión", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("¿No hace nada el botón? Hazlo desde el Centro de Control:")
                    .font(.subheadline.weight(.semibold))
                Text("1. Desliza para abrir el Centro de Control.\n2. Mantén pulsado el botón de grabar pantalla.\n3. Elige PhoneMirror ▸ Iniciar emisión.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
    }
}

#Preview {
    ContentView()
}
