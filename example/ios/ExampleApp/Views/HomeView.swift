import PoltioSDK
import SwiftUI

struct HomeView: View {
    let products: [Product] = Product.sampleProducts
    @State private var selectedCategory: ProductCategory?

    var featuredProducts: [Product] {
        products.filter(\.isFeatured)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero Banner
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 180)
                        .cornerRadius(20)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Find Your Dream Tech")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Text("Interactive phone finder & product matchers powered by Poltio TAG.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(20)
                    }
                    .padding(.horizontal)

                    // Categories Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Shop by Category")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        HStack(spacing: 12) {
                            ForEach(ProductCategory.allCases) { category in
                                NavigationLink(destination: PLPView(category: category)) {
                                    CategoryCardView(category: category)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Featured Products Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Featured Products")
                                .font(.title3)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(featuredProducts) { product in
                                    NavigationLink(destination: PDPView(product: product)) {
                                        ProductCardView(product: product)
                                            .frame(width: 180, height: 260)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("TechStore")
            #if os(iOS)
                .background(Color(UIColor.systemGroupedBackground))
            #else
                .background(Color.gray.opacity(0.05))
            #endif
                .onAppear {
                    PoltioSDK.track(event: "view", params: ["url": "example://home"])
                }
        }
    }
}
