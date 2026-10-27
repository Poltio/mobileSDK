package com.poltio.exampleapp.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Checkroom
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.Watch
import androidx.compose.material.icons.filled.WbSunny
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poltio.exampleapp.services.PoltioSDKPlaceholder

/** Point a widget at this URL to show it on the Lookbook screen. */
private const val LOOKBOOK_URL = "example://lookbook"

private data class Look(val name: String, val price: String, val icon: ImageVector, val tint: Color)

private val looks = listOf(
    Look("Linen Shirt", "\$79", Icons.Default.Checkroom, Color(0xFFDBD1BD)),
    Look("Weekend Tote", "\$120", Icons.Default.ShoppingBag, Color(0xFFB89E85)),
    Look("Summer Shades", "\$95", Icons.Default.WbSunny, Color(0xFFCCD6D1)),
    Look("Field Watch", "\$110", Icons.Default.Watch, Color(0xFFE0DBE6)),
    Look("Gift Card", "From \$25", Icons.Default.CardGiftcard, Color(0xFFEBCCC2)),
)

/**
 * An editorial, image-led screen, like the one a fashion app opens on, for trying triggers over
 * full-bleed content. Mirrors the iOS example app's Lookbook tab.
 */
@Composable
fun LookbookScreen() {
    LaunchedEffect(Unit) {
        PoltioSDKPlaceholder.trackScreen("Lookbook", url = LOOKBOOK_URL)
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        item { LookbookHero() }

        item {
            SectionTitle("The Edit")
            LazyRow(
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(looks) { look ->
                    LookCard(look, Modifier.width(150.dp).height(210.dp))
                }
            }
        }

        // Gives the page enough scroll room to exercise scroll-driven trigger behavior.
        item { SectionTitle("New In") }
        items(looks.reversed().chunked(2)) { row ->
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                row.forEach { look -> LookCard(look, Modifier.weight(1f).height(230.dp)) }
                if (row.size == 1) Spacer(modifier = Modifier.weight(1f))
            }
        }

        item {
            Text(
                text = "Poltio tracks this screen as $LOOKBOOK_URL. Target that URL to show a widget here.",
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f),
                modifier = Modifier.padding(16.dp)
            )
        }
    }
}

@Composable
private fun LookbookHero() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(460.dp)
            .background(Brush.verticalGradient(listOf(Color(0xFFE8E0D4), Color(0xFF8C7D6B)))),
        contentAlignment = Alignment.BottomCenter
    ) {
        Icon(
            imageVector = Icons.Default.Checkroom,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.35f),
            modifier = Modifier
                .align(Alignment.Center)
                .offset(y = (-40).dp)
                .size(170.dp)
        )

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(bottom = 36.dp)
        ) {
            Text(
                text = "SUMMER EDIT",
                fontSize = 32.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Serif,
                letterSpacing = 1.5.sp,
                color = Color.White
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = "Linen, light knits and everything in between.",
                fontSize = 14.sp,
                color = Color.White.copy(alpha = 0.9f)
            )
            Spacer(modifier = Modifier.height(14.dp))
            Text(
                text = "EXPLORE",
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 2.sp,
                color = Color.White,
                modifier = Modifier
                    .border(1.dp, Color.White, CircleShape)
                    .padding(horizontal = 22.dp, vertical = 10.dp)
            )
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        fontSize = 20.sp,
        fontWeight = FontWeight.SemiBold,
        fontFamily = FontFamily.Serif,
        color = MaterialTheme.colorScheme.onBackground,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 12.dp)
    )
}

@Composable
private fun LookCard(look: Look, modifier: Modifier = Modifier) {
    Column(modifier = modifier) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .clip(RoundedCornerShape(4.dp))
                .background(look.tint),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = look.icon,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.85f),
                modifier = Modifier.size(52.dp)
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(text = look.name, fontSize = 14.sp, color = MaterialTheme.colorScheme.onBackground, maxLines = 1)
        Text(text = look.price, fontSize = 12.sp, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
    }
}
