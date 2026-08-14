import SwiftUI

struct CategoryCardView: View {
    let category: ProductCategory

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: category.iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.blue)
            }

            Text(category.rawValue)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        #if os(iOS)
            .background(Color(UIColor.secondarySystemGroupedBackground))
        #else
            .background(Color.gray.opacity(0.1))
        #endif
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

struct ProductCardView: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                #if os(iOS)
                    .fill(Color(UIColor.tertiarySystemGroupedBackground))
                #else
                    .fill(Color.gray.opacity(0.15))
                #endif
                    .frame(height: 140)

                Image(systemName: product.imageName)
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(product.category.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)

                Text(product.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(String(format: "%.1f", product.rating))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 4)

                Text(product.formattedPrice)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        #if os(iOS)
            .background(Color(UIColor.secondarySystemGroupedBackground))
        #else
            .background(Color.gray.opacity(0.1))
        #endif
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}
