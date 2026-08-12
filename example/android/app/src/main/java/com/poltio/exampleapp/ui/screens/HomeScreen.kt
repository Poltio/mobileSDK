package com.poltio.exampleapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poltio.exampleapp.models.SampleCatalog
import com.poltio.exampleapp.services.PoltioSDKPlaceholder
import com.poltio.exampleapp.ui.components.ProductCard

@Composable
fun HomeScreen(
    onNavigateCategory: (String) -> Unit,
    onNavigateProduct: (String) -> Unit
) {
    LaunchedEffect(Unit) {
        PoltioSDKPlaceholder.trackScreen("Home / Landing")
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        // Hero Banner
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(20.dp))
                    .background(
                        Brush.horizontalGradient(
                            colors = listOf(
                                Color(0xFF4F46E5),
                                Color(0xFFEC4899)
                            )
                        )
                    )
                    .padding(24.dp)
            ) {
                Column {
                    Text(
                        text = "TechStore AI",
                        fontSize = 24.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Find your perfect gadget powered by Poltio TAG interactive widgets.",
                        fontSize = 14.sp,
                        color = Color.White.copy(alpha = 0.9f)
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
        }

        // Category Cards Section
        item {
            Text(
                text = "Shop by Category",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground
            )
            Spacer(modifier = Modifier.height(12.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                CategoryPill("Phones", Icons.Default.Smartphone, Modifier.weight(1f)) {
                    onNavigateCategory("Phones")
                }
                CategoryPill("TVs", Icons.Default.Tv, Modifier.weight(1f)) {
                    onNavigateCategory("TVs")
                }
                CategoryPill("Laptops", Icons.Default.Laptop, Modifier.weight(1f)) {
                    onNavigateCategory("Laptops")
                }
            }

            Spacer(modifier = Modifier.height(28.dp))
        }

        // Featured Products Section
        item {
            Text(
                text = "Featured Products",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground
            )
            Spacer(modifier = Modifier.height(12.dp))
        }

        items(SampleCatalog.products) { product ->
            ProductCard(product = product) {
                onNavigateProduct(product.id)
            }
        }
    }
}

@Composable
private fun CategoryPill(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Card(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .clickable { onClick() },
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(
            modifier = Modifier
                .padding(16.dp)
                .fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.height(32.dp)
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = title,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
    }
}
