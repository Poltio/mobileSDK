import Foundation

enum ProductCategory: String, CaseIterable, Identifiable, Codable {
    case phones = "Phones"
    case tvs = "TVs"
    case laptops = "Laptops"

    var id: String {
        rawValue
    }

    var iconName: String {
        switch self {
        case .phones: "iphone"
        case .tvs: "tv"
        case .laptops: "laptopcomputer"
        }
    }

    var routeKey: String {
        switch self {
        case .phones: "phones"
        case .tvs: "tvs"
        case .laptops: "laptops"
        }
    }
}

struct Product: Identifiable, Codable {
    let id: String
    let name: String
    let category: ProductCategory
    let price: Double
    let rating: Double
    let description: String
    let specs: [String]
    let imageName: String
    let isFeatured: Bool

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: price)) ?? "$\(price)"
    }
}

extension Product {
    static let sampleProducts: [Product] = [
        // Phones
        Product(
            id: "iphone-15-pro",
            name: "iPhone 15 Pro Max",
            category: .phones,
            price: 1199.00,
            rating: 4.9,
            description: "Forged in titanium and featuring the groundbreaking A17 Pro chip, a customizable Action button, and the most powerful iPhone camera system ever.",
            specs: ["A17 Pro Chip", "6.7\" Super Retina XDR", "48MP Main Camera", "Titanium Design"],
            imageName: "iphone",
            isFeatured: true
        ),
        Product(
            id: "s24-ultra",
            name: "Samsung Galaxy S24 Ultra",
            category: .phones,
            price: 1299.00,
            rating: 4.8,
            description: "Unleash new ways to create, connect and accomplish with Galaxy AI. S Pen included with QHD+ AMOLED display.",
            specs: ["Snapdragon 8 Gen 3", "200MP Camera", "Built-in S Pen", "Galaxy AI"],
            imageName: "smartphone",
            isFeatured: true
        ),
        Product(
            id: "pixel-8-pro",
            name: "Google Pixel 8 Pro",
            category: .phones,
            price: 999.00,
            rating: 4.7,
            description: "The most powerful, personal Pixel yet. Advanced Google AI features and pro-level triple camera system.",
            specs: ["Google Tensor G3", "6.7\" Super Actua Display", "Best Take & Magic Editor", "7 Years Updates"],
            imageName: "iphone.gen2",
            isFeatured: false
        ),

        // TVs
        Product(
            id: "lg-oled-65",
            name: "LG OLED evo 65\" 4K Smart TV",
            category: .tvs,
            price: 1799.00,
            rating: 4.9,
            description: "Self-lit OLED pixels create beautiful picture quality with infinite contrast, perfect black, and over a billion colors.",
            specs: ["65\" 4K OLED", "α9 AI Processor Gen6", "120Hz Gaming", "Dolby Vision & Atmos"],
            imageName: "tv",
            isFeatured: true
        ),
        Product(
            id: "samsung-qled-55",
            name: "Samsung QLED 55\" Neo 4K",
            category: .tvs,
            price: 1299.00,
            rating: 4.7,
            description: "Quantum Matrix Technology with Mini LEDs delivers precise light control and brilliant contrast.",
            specs: ["55\" Neo QLED", "Neural Quantum Processor", "Motion Xcelerator 120Hz", "Object Tracking Sound"],
            imageName: "tv.fill",
            isFeatured: false
        ),
        Product(
            id: "sony-bravia-75",
            name: "Sony BRAVIA XR 75\" Mini LED",
            category: .tvs,
            price: 2499.00,
            rating: 4.8,
            description: "Cognitive Processor XR delivers dynamic contrast and realistic colors optimized for movies and gaming.",
            specs: ["75\" Mini LED", "Cognitive Processor XR", "Acoustic Multi-Audio", "Perfect for PS5"],
            imageName: "tv.circle",
            isFeatured: false
        ),

        // Laptops
        Product(
            id: "macbook-pro-16",
            name: "MacBook Pro 16\" (M3 Max)",
            category: .laptops,
            price: 3499.00,
            rating: 5.0,
            description: "Mind-blowing performance with the M3 Max chip. Up to 22 hours of battery life and Liquid Retina XDR display.",
            specs: ["Apple M3 Max Chip", "36GB Unified Memory", "1TB SSD", "Liquid Retina XDR"],
            imageName: "laptopcomputer",
            isFeatured: true
        ),
        Product(
            id: "dell-xps-15",
            name: "Dell XPS 15 OLED",
            category: .laptops,
            price: 1999.00,
            rating: 4.6,
            description: "Precision crafted from CNC aluminum with 3.5K OLED Touch display and powerful NVIDIA RTX graphics.",
            specs: ["Intel Core i9 13th Gen", "NVIDIA RTX 4060", "32GB RAM", "3.5K OLED Touch"],
            imageName: "laptopcomputer.and.iphone",
            isFeatured: false
        ),
        Product(
            id: "thinkpad-x1",
            name: "Lenovo ThinkPad X1 Carbon",
            category: .laptops,
            price: 1649.00,
            rating: 4.7,
            description: "Ultralight enterprise power. Carbon-fiber weave chassis with all-day battery and military-grade durability.",
            specs: ["Intel Core i7 Evo", "14\" 2.8K OLED Display", "16GB RAM / 512GB SSD", "1.12 kg Ultra Light"],
            imageName: "macbook",
            isFeatured: false
        ),
    ]
}
