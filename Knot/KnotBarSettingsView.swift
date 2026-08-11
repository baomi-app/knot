import SwiftUI

struct KnotBarSettingsView: View {
    @ObservedObject var store: KnotBarSettingsStore
    @ObservedObject private var controller = KnotBarController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Knot Bar")
                    .font(.title2.weight(.semibold))
                Text("Keep less-used menu bar items out of the way.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Enable Knot Bar", isOn: enabledBinding)
                    .fontWeight(.medium)

                Divider()

                HStack(spacing: 12) {
                    Label(
                        controller.isCollapsed && store.isEnabled ? "Items hidden" : "Items visible",
                        systemImage: controller.isCollapsed && store.isEnabled ? "eye.slash" : "eye"
                    )
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button(controller.isCollapsed ? "Reveal Items" : "Hide Items") {
                        controller.toggle()
                    }
                    .disabled(!store.isEnabled)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            Label {
                Text("Hold ⌘ and drag items you want to hide to the left of Knot Bar’s separator. Keep the chevron on the right.")
            } icon: {
                Image(systemName: "command")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { store.isEnabled }, set: { store.setEnabled($0) })
    }
}
