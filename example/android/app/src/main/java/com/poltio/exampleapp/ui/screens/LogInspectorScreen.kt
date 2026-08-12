package com.poltio.exampleapp.ui.screens

import androidx.compose.foundation.background
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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.poltio.exampleapp.services.LogType
import com.poltio.exampleapp.services.PoltioSDKPlaceholder

@Composable
fun LogInspectorScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        Text(
            text = "Poltio SDK Activity Logs",
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onBackground
        )

        Text(
            text = "Live event stream for screen views, trigger rules, and widget presentations.",
            fontSize = 13.sp,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
        )

        Spacer(modifier = Modifier.height(16.dp))

        LazyColumn(
            modifier = Modifier.fillMaxSize()
        ) {
            items(PoltioSDKPlaceholder.logs) { log ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surface
                    )
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(6.dp))
                                .background(
                                    when (log.type) {
                                        LogType.INFO -> Color(0xFF3B82F6)
                                        LogType.SCREEN_TRACK -> Color(0xFF6366F1)
                                        LogType.EVENT -> Color(0xFF10B981)
                                        LogType.TRIGGER -> Color(0xFFEC4899)
                                    }.copy(alpha = 0.15f)
                                )
                                .padding(horizontal = 6.dp, vertical = 2.dp)
                        ) {
                            Text(
                                text = log.type.name,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                color = when (log.type) {
                                    LogType.INFO -> Color(0xFF3B82F6)
                                    LogType.SCREEN_TRACK -> Color(0xFF6366F1)
                                    LogType.EVENT -> Color(0xFF10B981)
                                    LogType.TRIGGER -> Color(0xFFEC4899)
                                }
                            )
                        }

                        Text(
                            text = "[${log.timestamp}]",
                            fontSize = 11.sp,
                            fontFamily = FontFamily.Monospace,
                            color = Color.Gray,
                            modifier = Modifier.padding(horizontal = 8.dp)
                        )

                        Text(
                            text = log.message,
                            fontSize = 13.sp,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
    }
}
