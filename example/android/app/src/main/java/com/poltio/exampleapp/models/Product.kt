package com.poltio.exampleapp.models

data class Product(
    val id: String,
    val name: String,
    val category: String, // "Phones", "TVs", "Laptops"
    val price: String,
    val description: String,
    val badge: String,
    val specs: List<String>,
    val poltioWidgetTitle: String,
    val poltioUrl: String
)

object SampleCatalog {
    val products = listOf(
        // PHONES
        Product(
            id = "phone-1",
            name = "ProPhone 15 Max",
            category = "Phones",
            price = "$1,199",
            description = "Ultimate flagship phone with titanium design and pro camera system.",
            badge = "Bestseller",
            specs = listOf("6.7-inch OLED", "512GB Storage", "Triple 48MP Camera", "5G Network"),
            poltioWidgetTitle = "Phone Recommendation Quiz",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        Product(
            id = "phone-2",
            name = "PixelTech Ultra 8",
            category = "Phones",
            price = "$999",
            description = "Pure Android experience powered by advanced AI and real-time live translate.",
            badge = "New AI Feature",
            specs = listOf("6.8-inch 120Hz", "256GB Storage", "AI Photo Magic", "All-day Battery"),
            poltioWidgetTitle = "Find Your Ideal Smartphone",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        Product(
            id = "phone-3",
            name = "FoldMax Z 5G",
            category = "Phones",
            price = "$1,799",
            description = "Book-style foldable that opens into a full tablet for serious multitasking.",
            badge = "Foldable",
            specs = listOf("7.6-inch Foldable", "512GB Storage", "Multi-Window Multitasking", "Stylus Compatible"),
            poltioWidgetTitle = "Phone Recommendation Quiz",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        Product(
            id = "phone-4",
            name = "ClearShot Pro 12",
            category = "Phones",
            price = "$1,099",
            description = "Photography-first flagship with a variable aperture lens and pro-grade optics.",
            badge = "Camera Pro",
            specs = listOf("6.73-inch AMOLED", "256GB Storage", "Variable Aperture Lens", "90W Fast Charging"),
            poltioWidgetTitle = "Find Your Ideal Smartphone",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        Product(
            id = "phone-5",
            name = "NovaPhone X3",
            category = "Phones",
            price = "$799",
            description = "Everyday flagship with a bright display and all-day battery, without the flagship price tag.",
            badge = "Best Value",
            specs = listOf("6.1-inch OLED", "128GB Storage", "48MP Main Camera", "USB-C"),
            poltioWidgetTitle = "Phone Recommendation Quiz",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        Product(
            id = "phone-6",
            name = "SwiftEdge 9 Pro",
            category = "Phones",
            price = "$799",
            description = "Flagship-tier speed and camera tuning at a mid-range price, with 100W charging.",
            badge = "Fast Charging",
            specs = listOf("6.82-inch LTPO AMOLED", "256GB Storage", "Pro Camera Tuning", "100W SuperCharge"),
            poltioWidgetTitle = "Find Your Ideal Smartphone",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        Product(
            id = "phone-7",
            name = "TitanCore Mini",
            category = "Phones",
            price = "$699",
            description = "Compact powerhouse with the same core chipset and AI smarts as its bigger sibling.",
            badge = "Compact",
            specs = listOf("6.2-inch Display", "128GB Storage", "AI Call Screening", "Multi-Year Updates"),
            poltioWidgetTitle = "Phone Recommendation Quiz",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        Product(
            id = "phone-8",
            name = "AuraLite S7",
            category = "Phones",
            price = "$599",
            description = "Lightweight, affordable, and dependable, built for everyday use without compromise.",
            badge = "Everyday Value",
            specs = listOf("6.4-inch OLED", "128GB Storage", "Dual Camera System", "5000mAh Battery"),
            poltioWidgetTitle = "Find Your Ideal Smartphone",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        Product(
            id = "phone-9",
            name = "ZenPhone Flip 3",
            category = "Phones",
            price = "$999",
            description = "A pocketable clamshell foldable with a large cover screen for quick glances on the go.",
            badge = "Foldable",
            specs = listOf("6.7-inch Foldable Display", "256GB Storage", "Large Cover Screen", "Compact Flip Design"),
            poltioWidgetTitle = "Phone Recommendation Quiz",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        Product(
            id = "phone-10",
            name = "GameForce RS Pro",
            category = "Phones",
            price = "$1,099",
            description = "Purpose-built gaming phone with vapor chamber cooling and ultrasonic shoulder triggers.",
            badge = "Gaming",
            specs = listOf("165Hz AMOLED", "512GB Storage", "Vapor Chamber Cooling", "5500mAh Battery"),
            poltioWidgetTitle = "Find Your Ideal Smartphone",
            poltioUrl = "https://poltio.com/p/phone-finder"
        ),
        // TVs
        Product(
            id = "tv-1",
            name = "CineMax 65\" OLED TV",
            category = "TVs",
            price = "$1,899",
            description = "Self-lit OLED pixels deliver perfect blacks and infinite contrast for movies.",
            badge = "4K HDR",
            specs = listOf("65-inch 4K OLED", "120Hz Gaming Port", "Dolby Vision & Atmos", "Smart OS"),
            poltioWidgetTitle = "TV Screen Size & Feature Calculator",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        Product(
            id = "tv-2",
            name = "VisionPro 75\" QLED 8K",
            category = "TVs",
            price = "$2,499",
            description = "Breathtaking 8K clarity with quantum dot color accuracy for ultimate home cinema.",
            badge = "8K Flagship",
            specs = listOf("75-inch 8K QLED", "Mini-LED Backlight", "100W Built-in Audio", "Anti-Glare"),
            poltioWidgetTitle = "TV Buying Assistant",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        Product(
            id = "tv-3",
            name = "LumaScreen 75\" Mini LED",
            category = "TVs",
            price = "$1,999",
            description = "High-brightness Mini LED backlighting with thousands of local dimming zones for punchy HDR.",
            badge = "Mini LED",
            specs = listOf("75-inch 4K Mini LED", "5000+ Dimming Zones", "144Hz Gaming", "Smart OS"),
            poltioWidgetTitle = "TV Screen Size & Feature Calculator",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        Product(
            id = "tv-4",
            name = "PrismView 55\" OLED",
            category = "TVs",
            price = "$1,799",
            description = "Self-lit OLED pixels with a dedicated cooling system for sustained peak brightness.",
            badge = "OLED",
            specs = listOf("55-inch OLED", "AI Processor", "120Hz Gaming", "Dolby Atmos Speaker System"),
            poltioWidgetTitle = "TV Buying Assistant",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        Product(
            id = "tv-5",
            name = "ClarityMax 65\" ULED",
            category = "TVs",
            price = "$1,499",
            description = "Full-array local dimming ULED technology delivers deep contrast at a great value.",
            badge = "Best Value",
            specs = listOf("65-inch 4K ULED", "144Hz Gaming", "Dolby Vision IQ", "Smart OS"),
            poltioWidgetTitle = "TV Screen Size & Feature Calculator",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        Product(
            id = "tv-6",
            name = "HomeCinema 85\" QLED",
            category = "TVs",
            price = "$3,299",
            description = "A massive quantum dot display built for dedicated home theater rooms.",
            badge = "Home Theater",
            specs = listOf("85-inch 4K QLED", "Full-Array Local Dimming", "120Hz Gaming", "Object Tracking Sound"),
            poltioWidgetTitle = "TV Buying Assistant",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        Product(
            id = "tv-7",
            name = "FrameArt 55\" Display",
            category = "TVs",
            price = "$1,499",
            description = "A QLED display that doubles as art, with a matte screen and customizable bezels.",
            badge = "Art Mode",
            specs = listOf("55-inch 4K QLED", "Art Mode", "Anti-Reflection Matte Display", "No Gap Wall-Mount"),
            poltioWidgetTitle = "TV Screen Size & Feature Calculator",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        Product(
            id = "tv-8",
            name = "PureView 77\" OLED",
            category = "TVs",
            price = "$2,999",
            description = "A larger-format OLED with near-instant response times for cinephiles and gamers alike.",
            badge = "Premium OLED",
            specs = listOf("77-inch 4K OLED evo", "AI Processor Gen6", "4x HDMI 2.1 48Gbps", "0.1ms Response Time"),
            poltioWidgetTitle = "TV Buying Assistant",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        Product(
            id = "tv-9",
            name = "StreamCast 50\" Smart TV",
            category = "TVs",
            price = "$599",
            description = "An affordable, compact smart TV with a built-in streaming hub for smaller rooms.",
            badge = "Compact",
            specs = listOf("50-inch 4K LED", "Built-in Streaming Hub", "Voice Remote", "HDR10"),
            poltioWidgetTitle = "TV Screen Size & Feature Calculator",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        Product(
            id = "tv-10",
            name = "UltraWide 65\" LED",
            category = "TVs",
            price = "$1,299",
            description = "Full-array LED backlighting delivers lifelike contrast and color for everyday viewing.",
            badge = "Full-Array LED",
            specs = listOf("65-inch 4K Full-Array LED", "AI Processor", "Triluminos Color", "120Hz Gaming"),
            poltioWidgetTitle = "TV Buying Assistant",
            poltioUrl = "https://poltio.com/p/tv-finder"
        ),
        // LAPTOPS
        Product(
            id = "laptop-1",
            name = "UltraBook Pro 16",
            category = "Laptops",
            price = "$2,399",
            description = "Blazing performance for video editing, 3D rendering, and heavy software development.",
            badge = "Creator Edition",
            specs = listOf("M3 Max 12-Core", "32GB Unified RAM", "1TB NVMe SSD", "22-hour Battery"),
            poltioWidgetTitle = "Laptop Matchmaker Quiz",
            poltioUrl = "https://poltio.com/p/laptop-finder"
        ),
        Product(
            id = "laptop-2",
            name = "AirLite 14 Laptop",
            category = "Laptops",
            price = "$1,099",
            description = "Incredibly thin and lightweight laptop designed for students and mobile professionals.",
            badge = "Ultra Portable",
            specs = listOf("14-inch Retina", "16GB RAM", "512GB Storage", "Fanless Silent Design"),
            poltioWidgetTitle = "Laptop Matchmaker Quiz",
            poltioUrl = "https://poltio.com/p/laptop-finder"
        )
    )

    fun getByCategory(category: String): List<Product> {
        return products.filter { it.category.equals(category, ignoreCase = true) }
    }

    fun getById(id: String): Product? {
        return products.find { it.id == id }
    }
}
