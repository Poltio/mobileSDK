import PoltioSDK
import SwiftUI

struct PDPView: View {
    let product: Product
    @State private var showAddedToCartToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Product Image Box
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                    #if os(iOS)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                    #else
                        .fill(Color.gray.opacity(0.1))
                    #endif
                        .frame(height: 260)

                    Image(systemName: product.imageName)
                        .font(.system(size: 100))
                        .foregroundColor(.blue.opacity(0.8))
                }
                .padding(.horizontal)

                // Title & Price Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(product.category.rawValue.uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.orange)
                            Text(String(format: "%.1f Rating", product.rating))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }

                    Text(product.name)
                        .font(.title)
                        .fontWeight(.bold)

                    Text(product.formattedPrice)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Interactive Poltio Finder Banner
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundColor(.purple)
                        Text("Poltio TAG Interactive Finder")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Text("Not sure if this \(product.category.rawValue.dropLast().lowercased()) fits your needs? Use our interactive finder quiz to match your style.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button(action: {
                        print("[ExampleApp] Triggering Poltio TAG interactive widget for \(product.id)")
                    }) {
                        HStack {
                            Image(systemName: "questionmark.bubble.fill")
                            Text("Help Me Choose My \(product.category.rawValue.dropLast())")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color.purple.opacity(0.08))
                .cornerRadius(16)
                .padding(.horizontal)

                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                    Text(product.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Technical Specs
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Specifications")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(product.specs, id: \.self) { spec in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(spec)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground))
        #else
        .background(Color.gray.opacity(0.05))
        #endif
        .safeAreaInset(edge: .bottom) {
            // Sticky Buy Button
            HStack {
                VStack(alignment: .leading) {
                    Text("Total Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(product.formattedPrice)
                        .font(.headline)
                        .fontWeight(.bold)
                }
                Spacer()
                Button(action: {
                    showAddedToCartToast = true
                }) {
                    Text("Add to Cart")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .cornerRadius(14)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .alert("Added to Cart!", isPresented: $showAddedToCartToast) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(product.name) has been added to your shopping cart.")
        }
        .onAppear {
            PoltioSDK.track(event: "view", params: ["url": "example://pdp"])
        }
    }
}
