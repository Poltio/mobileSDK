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
        Product(
            id: "iphone-15",
            name: "iPhone 15",
            category: .phones,
            price: 799.00,
            rating: 4.6,
            description: "A magical new way to interact with iPhone with Dynamic Island, a 48MP main camera, and USB-C.",
            specs: ["A16 Bionic Chip", "6.1\" Super Retina XDR", "48MP Main Camera", "USB-C"],
            imageName: "iphone",
            isFeatured: false
        ),
        Product(
            id: "oneplus-12",
            name: "OnePlus 12",
            category: .phones,
            price: 799.00,
            rating: 4.6,
            description: "Flagship killer with Hasselblad camera tuning and blazing-fast 100W charging.",
            specs: ["Snapdragon 8 Gen 3", "6.82\" LTPO AMOLED", "Hasselblad Camera", "100W SuperVOOC"],
            imageName: "smartphone",
            isFeatured: false
        ),
        Product(
            id: "xiaomi-14-ultra",
            name: "Xiaomi 14 Ultra",
            category: .phones,
            price: 1099.00,
            rating: 4.7,
            description: "Photography powerhouse co-engineered with Leica, featuring a variable aperture main camera.",
            specs: ["Snapdragon 8 Gen 3", "Leica Optics", "6.73\" LTPO AMOLED", "90W Wired Charging"],
            imageName: "iphone.gen2",
            isFeatured: false
        ),
        Product(
            id: "galaxy-z-fold5",
            name: "Samsung Galaxy Z Fold 5",
            category: .phones,
            price: 1799.00,
            rating: 4.5,
            description: "A book-sized phone that unfolds into a tablet, built for serious multitasking.",
            specs: ["Snapdragon 8 Gen 2 for Galaxy", "7.6\" Foldable Display", "Multi-Window Multitasking", "S Pen Compatible"],
            imageName: "smartphone",
            isFeatured: false
        ),
        Product(
            id: "pixel-8",
            name: "Google Pixel 8",
            category: .phones,
            price: 699.00,
            rating: 4.6,
            description: "Compact powerhouse with the same Tensor G3 chip and AI smarts as the Pro, in a smaller frame.",
            specs: ["Google Tensor G3", "6.2\" Actua Display", "AI Call Screening", "7 Years Updates"],
            imageName: "iphone",
            isFeatured: false
        ),
        Product(
            id: "rog-phone-8",
            name: "ASUS ROG Phone 8",
            category: .phones,
            price: 1099.00,
            rating: 4.5,
            description: "Purpose-built gaming phone with a vapor chamber cooling system and ultrasonic shoulder triggers.",
            specs: ["Snapdragon 8 Gen 3", "165Hz AMOLED", "AirTrigger Ultrasonic Buttons", "5500mAh Battery"],
            imageName: "smartphone",
            isFeatured: false
        ),
        Product(
            id: "xperia-1-v",
            name: "Sony Xperia 1 V",
            category: .phones,
            price: 1399.00,
            rating: 4.3,
            description: "A creator's phone with a true 4K OLED display and full manual camera controls.",
            specs: ["Snapdragon 8 Gen 2", "4K HDR OLED", "24-70mm Zeiss Zoom Lens", "3.5mm Headphone Jack"],
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
        Product(
            id: "tcl-qm8-75",
            name: "TCL QM8 75\" Mini LED",
            category: .tvs,
            price: 1999.00,
            rating: 4.6,
            description: "High-brightness Mini LED backlighting with thousands of local dimming zones for punchy HDR.",
            specs: ["75\" 4K Mini LED", "5000+ Dimming Zones", "144Hz Gaming", "Google TV"],
            imageName: "tv",
            isFeatured: false
        ),
        Product(
            id: "hisense-u8k-65",
            name: "Hisense U8K 65\" ULED",
            category: .tvs,
            price: 1499.00,
            rating: 4.5,
            description: "Mini LED ULED technology with a full-array local dimming backlight for deep contrast at a great value.",
            specs: ["65\" 4K Mini LED ULED", "144Hz Gaming", "Dolby Vision IQ", "Google TV"],
            imageName: "tv.fill",
            isFeatured: false
        ),
        Product(
            id: "panasonic-mz2000-55",
            name: "Panasonic MZ2000 55\" OLED",
            category: .tvs,
            price: 1799.00,
            rating: 4.7,
            description: "Master OLED Ultimate panel with a dedicated heat pipe for sustained peak brightness.",
            specs: ["55\" Master OLED Ultimate", "HCX Pro AI Processor", "120Hz Gaming", "Dolby Atmos Speaker System"],
            imageName: "tv.circle",
            isFeatured: false
        ),
        Product(
            id: "vizio-m-series-65",
            name: "Vizio M-Series 65\" Quantum",
            category: .tvs,
            price: 999.00,
            rating: 4.3,
            description: "Quantum Color and full-array local dimming bring vibrant HDR picture quality at an accessible price.",
            specs: ["65\" 4K QLED", "Full-Array Local Dimming", "IQ Active Processor", "SmartCast"],
            imageName: "tv",
            isFeatured: false
        ),
        Product(
            id: "samsung-frame-55",
            name: "Samsung The Frame 55\"",
            category: .tvs,
            price: 1499.00,
            rating: 4.6,
            description: "A QLED TV that doubles as art, with a matte display and customizable bezels for when it's off.",
            specs: ["55\" 4K QLED", "Art Mode", "Anti-Reflection Matte Display", "No Gap Wall-Mount"],
            imageName: "tv.fill",
            isFeatured: false
        ),
        Product(
            id: "lg-c3-77",
            name: "LG C3 77\" OLED",
            category: .tvs,
            price: 2999.00,
            rating: 4.9,
            description: "A larger-format OLED with near-instant response times, built for cinephiles and gamers alike.",
            specs: ["77\" 4K OLED evo", "α9 AI Processor Gen6", "4x HDMI 2.1 48Gbps", "0.1ms Response Time"],
            imageName: "tv.circle",
            isFeatured: false
        ),
        Product(
            id: "sony-x90l-65",
            name: "Sony X90L 65\" LED",
            category: .tvs,
            price: 1299.00,
            rating: 4.5,
            description: "Full-array LED backlighting driven by the Cognitive Processor XR for lifelike contrast and color.",
            specs: ["65\" 4K Full-Array LED", "Cognitive Processor XR", "XR Triluminos Pro", "120Hz Gaming"],
            imageName: "tv",
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
