import SwiftUI

/// An editorial, image-led screen, like the one a fashion app opens on, for trying triggers over
/// full-bleed content. Tracked as `poltiodemo://lookbook`: point a widget at that URL to show it here.
struct LookbookView: View {
    static let trackedURL = "poltiodemo://lookbook"

    private let looks = Look.samples

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero

                VStack(alignment: .leading, spacing: 12) {
                    Text("The Edit")
                        .font(.system(.title3, design: .serif))
                        .fontWeight(.semibold)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(looks) { look in
                                LookCardView(look: look)
                                    .frame(width: 150, height: 210)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Gives the page enough scroll room to exercise scroll-driven trigger behavior.
                VStack(alignment: .leading, spacing: 12) {
                    Text("New In")
                        .font(.system(.title3, design: .serif))
                        .fontWeight(.semibold)
                        .padding(.horizontal)

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(looks.reversed()) { look in
                            LookCardView(look: look)
                                .frame(height: 230)
                        }
                    }
                    .padding(.horizontal)
                }

                Text("Poltio tracks this screen as \(Self.trackedURL). Target that URL to show a widget here.")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        #if os(iOS)
            .background(Color(UIColor.systemBackground))
        #endif
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color(red: 0.91, green: 0.88, blue: 0.83), Color(red: 0.55, green: 0.49, blue: 0.42)],
                startPoint: .top,
                endPoint: .bottom
            )

            Image(systemName: "tshirt.fill")
                .font(.system(size: 180))
                .foregroundColor(.white.opacity(0.35))
                .offset(y: -150)

            VStack(spacing: 14) {
                Text("SUMMER EDIT")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .tracking(1.5)
                    .foregroundColor(.white)

                Text("Linen, light knits and everything in between.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))

                Text("EXPLORE")
                    .font(.footnote.weight(.semibold))
                    .tracking(2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .overlay(Capsule().stroke(Color.white, lineWidth: 1))
            }
            .padding(.bottom, 40)
        }
        .frame(height: 540)
    }
}

private struct Look: Identifiable {
    let id: String
    let name: String
    let price: String
    let symbol: String
    let tint: Color

    static let samples = [
        Look(id: "linen-shirt", name: "Linen Shirt", price: "$79", symbol: "tshirt.fill", tint: Color(red: 0.86, green: 0.82, blue: 0.74)),
        Look(id: "weekend-tote", name: "Weekend Tote", price: "$120", symbol: "handbag.fill", tint: Color(red: 0.72, green: 0.62, blue: 0.52)),
        Look(id: "round-frames", name: "Round Frames", price: "$95", symbol: "eyeglasses", tint: Color(red: 0.80, green: 0.84, blue: 0.82)),
        Look(id: "canvas-sneakers", name: "Canvas Sneakers", price: "$110", symbol: "shoeprints.fill", tint: Color(red: 0.88, green: 0.86, blue: 0.90)),
        Look(id: "gift-card", name: "Gift Card", price: "From $25", symbol: "giftcard.fill", tint: Color(red: 0.92, green: 0.80, blue: 0.76)),
    ]
}

private struct LookCardView: View {
    let look: Look

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(look.tint)

                Image(systemName: look.symbol)
                    .font(.system(size: 52))
                    .foregroundColor(.white.opacity(0.85))
            }

            Text(look.name)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(look.price)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
