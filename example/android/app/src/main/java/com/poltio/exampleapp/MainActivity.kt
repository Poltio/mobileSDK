package com.poltio.exampleapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.poltio.exampleapp.ui.screens.HomeScreen
import com.poltio.exampleapp.ui.screens.LogInspectorScreen
import com.poltio.exampleapp.ui.screens.PDPScreen
import com.poltio.exampleapp.ui.screens.PLPScreen
import com.poltio.exampleapp.ui.theme.PoltioTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PoltioTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    TechStoreApp()
                }
            }
        }
    }
}

sealed class Screen(val route: String, val title: String, val icon: ImageVector) {
    object Home : Screen("home", "Home", Icons.Default.Home)
    object Phones : Screen("category/Phones", "Phones", Icons.Default.Smartphone)
    object TVs : Screen("category/TVs", "TVs", Icons.Default.Tv)
    object Laptops : Screen("category/Laptops", "Laptops", Icons.Default.Laptop)
    object Logs : Screen("logs", "Logs", Icons.Default.BugReport)
}

@Composable
fun TechStoreApp() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    val bottomNavItems = listOf(
        Screen.Home,
        Screen.Phones,
        Screen.TVs,
        Screen.Laptops,
        Screen.Logs
    )

    Scaffold(
        bottomBar = {
            NavigationBar {
                bottomNavItems.forEach { screen ->
                    val selected = currentRoute == screen.route
                    NavigationBarItem(
                        icon = { Icon(screen.icon, contentDescription = screen.title) },
                        label = { Text(screen.title) },
                        selected = selected,
                        onClick = {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = Screen.Home.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(Screen.Home.route) {
                HomeScreen(
                    onNavigateCategory = { category ->
                        navController.navigate("category/$category")
                    },
                    onNavigateProduct = { productId ->
                        navController.navigate("product/$productId")
                    }
                )
            }

            composable("category/{categoryName}") { backStackEntry ->
                val categoryName = backStackEntry.arguments?.getString("categoryName") ?: "Phones"
                PLPScreen(
                    category = categoryName,
                    onNavigateProduct = { productId ->
                        navController.navigate("product/$productId")
                    }
                )
            }

            composable(
                "product/{productId}",
                arguments = listOf(navArgument("productId") { type = NavType.StringType })
            ) { backStackEntry ->
                val productId = backStackEntry.arguments?.getString("productId") ?: "phone-1"
                PDPScreen(productId = productId)
            }

            composable(Screen.Logs.route) {
                LogInspectorScreen()
            }
        }
    }
}
