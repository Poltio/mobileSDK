import PoltioSDK
import SwiftUI

struct PLPView: View {
    let category: ProductCategory

    var categoryProducts: [Product] {
        Product.sampleProducts.filter { $0.category == category }
    }

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Banner for Category
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(category.rawValue) Catalog")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Browse top-rated \(category.rawValue.lowercased())")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Spacer()
                    Image(systemName: category.iconName)
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                }
                .padding()
                #if os(iOS)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                #else
                    .background(Color.gray.opacity(0.1))
                #endif
                    .cornerRadius(16)
                    .padding(.horizontal)

                // Product Grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(categoryProducts) { product in
                        NavigationLink(destination: PDPView(product: product)) {
                            ProductCardView(product: product)
                                .frame(height: 250)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(category.rawValue)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(UIColor.systemGroupedBackground))
        #else
            .background(Color.gray.opacity(0.05))
        #endif
            .onAppear {
                PoltioSDK.track(event: "view", params: ["url": "example://plp/\(category.rawValue.lowercased())"])
            }
    }
}
