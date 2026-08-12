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
