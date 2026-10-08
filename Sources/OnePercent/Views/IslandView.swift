import SwiftUI

/// The phase-two surface deliberately contains no task domain logic. Its live button and
/// focusable field ensure the panel is verified as an interactive SwiftUI/AppKit surface.
struct IslandView: View {
    @State private var verificationText = ""
    @State private var didReceiveInteraction = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(IslandPalette.completedAccent)
                    .accessibilityHidden(true)

                Text("One Percent")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IslandPalette.primaryText)

                Spacer(minLength: 0)

                Button {
                    didReceiveInteraction.toggle()
                } label: {
                    Image(systemName: didReceiveInteraction ? "checkmark.circle.fill" : "hand.tap.fill")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(didReceiveInteraction ? IslandPalette.completedAccent : IslandPalette.secondaryText)
                .accessibilityLabel("Verify panel interaction")
                .help("Verifies that the notch panel receives clicks")
            }

            Rectangle()
                .fill(IslandPalette.border)
                .frame(height: 1)

            Text("Notch interaction is ready")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IslandPalette.primaryText)

            TextField("Type to verify keyboard focus", text: $verificationText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(IslandPalette.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(IslandPalette.primarySurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(IslandPalette.border, lineWidth: 1)
                }
                .accessibilityLabel("Panel keyboard focus check")

            Text("Hover the camera area. Leaving both areas closes this panel after a short delay.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(IslandPalette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IslandPalette.background)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
