// Import the Flutter material package for UI components
import 'package:flutter/material.dart'; 
// Import the FL Chart package to render charts in the app
import 'package:fl_chart/fl_chart.dart';
// Import Dart's async library for Timer and asynchronous operations
import 'dart:async';
// Import Dart's math library for random number generation and mathematical functions
import 'dart:math';
// Import Dart's firebase package
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Initialize Firebase Messaging Background Handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("🔹 Background Message: ${message.notification?.title}");
}

// Main entry point of the Flutter application
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp()); // Launch the MyApp widget as the root of the app
}

// Define the main application widget, which is stateless
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Build the widget tree for the application
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Remove the debug banner
      title: 'Leak Detection App', // Set the title of the app
      theme: ThemeData(
        // Generate a color scheme using a blue seed color
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        scaffoldBackgroundColor: Colors.black, // Set the scaffold background color to black
      ),
      home: FlowMonitoringApp(), // Set the home widget to FlowMonitoringApp
    );
  }
}

// Define a stateful widget for monitoring water flow
class FlowMonitoringApp extends StatefulWidget {
  @override
  _FlowMonitoringAppState createState() => _FlowMonitoringAppState();
}

// State class for FlowMonitoringApp that holds dynamic data and UI updates
class _FlowMonitoringAppState extends State<FlowMonitoringApp> {
  PageController _pageController = PageController(); // Controller for managing page navigation
  int currentPage = 0; // Current page index in the PageView
  double currentFlowRate = 0.0; // Holds the current water flow rate
  double previousFlowRate = 0.0; // Holds the previous water flow rate for comparison
  List<FlSpot> chartData = <FlSpot>[]; // List of data points for the flow rate chart
  int time = 0; // Time counter used in the simulation (in seconds)
  double totalFlow = 0.0; // Accumulated flow used for average flow calculation
  int decreasingTrend = 0; // Counter for consecutive decreases in flow rate
  bool showLeakAlert = false; // Flag to indicate if a water leak alert should be shown

    // Firebase Messaging instance
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialization method, called when the state is first created
  @override
  void initState() {
    super.initState();
    _setupFirebaseMessaging();
    startFlowRateSimulation(); // Start simulating the water flow rate changes
  }

  // ✅ Initialize Firebase Messaging
  void _setupFirebaseMessaging() async {
    // Request notification permission
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ Notifications Permission Granted');
    } else {
      print('🚨 Notifications Permission Denied');
    }

    // Get and print FCM token
    String? token = await messaging.getToken();
    print("🔹 FCM Token: $token");

    // Initialize Local Notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Handle notifications when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("🔔 Foreground Notification Received: ${message.notification?.title}");
      _showNotification(message.notification?.title, message.notification?.body);
    });

    // Handle when user taps on notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("🔔 Notification Clicked: ${message.notification?.title}");
    });
  }

  // ✅ Function to Show Local Notification
  void _showNotification(String? title, String? body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'leak_detect_channel',
      'Leak Detection Alerts',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: false,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }
  

  // Function to simulate flow rate changes periodically
  void startFlowRateSimulation() {
    // Create a periodic timer that triggers every 2 seconds
    Timer.periodic(Duration(seconds: 2), (timer) {
      setState(() {
        previousFlowRate = currentFlowRate; // Store the current flow rate before updating

        // Simulate stable flow for the first 15 seconds, then simulate leakage (decreasing flow)
        if (time < 15) {
          currentFlowRate = 8.0; // Set a constant stable flow rate
        } else {
          // Reduce the flow rate by a random amount (up to 2) but not lower than 2.0
          currentFlowRate = max(2.0, currentFlowRate - (Random().nextDouble() * 2));
        }

        totalFlow += currentFlowRate; // Update total accumulated flow
        chartData.add(FlSpot(time.toDouble(), currentFlowRate)); // Add a new data point for the chart
        time++; // Increment the time counter

        // Keep only the most recent 20 data points in the chart data
        if (chartData.length > 20) {
          chartData.removeAt(0);
        }

        // Check if the flow rate is decreasing compared to the previous value
        if (currentFlowRate < previousFlowRate) {
          decreasingTrend++; // Increase the counter for a decreasing trend
        } else {
          decreasingTrend = 0; // Reset the counter if the flow rate is not decreasing
        }

        // If the flow rate has been decreasing consecutively for 5 intervals, show a leak alert
        if (decreasingTrend >= 5) {
          showLeakAlert = true;
          _sendPushNotification("⚠️ Leak Detected", "A possible water leak has been detected!");

        } else {
          showLeakAlert = false;
        }
      });
    });
  }

    // ✅ Function to Send Push Notification
void _sendPushNotification(String title, String body) {
  _showNotification(title, body);
}

  // Calculate and return the average flow rate based on the collected data
  double getAverageFlowRate() {
    if (chartData.isEmpty) return 0.0; // Avoid division by zero if no data exists
    return totalFlow / chartData.length; // Compute the average flow rate
  }

  // Navigate to a specific page in the PageView
  void goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: Duration(milliseconds: 300), // Duration of the page transition animation
      curve: Curves.easeInOut, // Use an ease in/out curve for smooth transition
    );
    setState(() {
      currentPage = page; // Update the current page index state
    });
  }

  // Build the widget tree for the FlowMonitoringApp
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Set the background color of the scaffold
      body: Stack(
        // Use a Stack to overlay the PageView and navigation buttons
        children: [
          // The PageView widget allows swiping between different screens
          PageView(
            controller: _pageController, // Attach the page controller to manage pages
            children: [
              FlowRateChartScreen(chartData: chartData), // First page: displays the flow rate chart
              CurrentFlowScreen(
                currentFlowRate: currentFlowRate, // Pass current flow rate to the screen
                previousFlowRate: previousFlowRate, // Pass previous flow rate for comparison
                averageFlowRate: getAverageFlowRate(), // Pass calculated average flow rate
                showLeakAlert: showLeakAlert, // Pass leak alert status
              ),
            ],
          ),
          // Display a forward navigation button when on the first page
          if (currentPage == 0)
            Positioned(
              right: 20, // Position 20 pixels from the right
              top: MediaQuery.of(context).size.height / 2 - 30, // Vertically center the button
              child: IconButton(
                icon: Icon(Icons.arrow_forward_ios, color: Colors.white, size: 30), // Icon for forward navigation
                onPressed: () => goToPage(1), // Navigate to the second page when pressed
              ),
            ),
          // Display a back navigation button when on the second page
          if (currentPage == 1)
            Positioned(
              left: 20, // Position 20 pixels from the left
              top: MediaQuery.of(context).size.height / 2 - 30, // Vertically center the button
              child: IconButton(
                icon: Icon(Icons.arrow_back_ios, color: Colors.white, size: 30), // Icon for back navigation
                onPressed: () => goToPage(0), // Navigate to the first page when pressed
              ),
            ),
        ],
      ),
    );
  }
}

// Define a stateless widget to display the flow rate chart screen
class FlowRateChartScreen extends StatelessWidget {
  final List<FlSpot> chartData; // List of data points for the chart

  // Constructor with required chart data
  FlowRateChartScreen({required this.chartData});

  // Build the widget tree for the chart screen
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Set the background color to black
      appBar: AppBar(title: Text("Flow Rate Chart")), // App bar with the screen title
      body: Padding(
        padding: const EdgeInsets.all(8.0), // Add padding around the chart
        child: LineChart(
          // Configure the chart data and styling using FL Chart package
          LineChartData(
            minY: 0, // Minimum Y-axis value to ensure proper display of data
            maxY: 10, // Maximum Y-axis value to keep the chart centered
            gridData: FlGridData(show: true), // Enable grid lines on the chart for better readability
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                // Label for the left axis
                axisNameWidget: Text("Flow Rate (L/min)", style: TextStyle(color: Colors.white, fontSize: 14)),
                sideTitles: SideTitles(
                  showTitles: true, 
                  reservedSize: 40, 
                  getTitlesWidget: (value, meta) {
                    // Display each left axis title value
                    return Text(value.toString(), style: TextStyle(color: Colors.white, fontSize: 12));
                  }
                ),
              ),
              bottomTitles: AxisTitles(
                // Label for the bottom axis
                axisNameWidget: Text("Time (seconds)", style: TextStyle(color: Colors.white, fontSize: 14)),
                sideTitles: SideTitles(
                  showTitles: true, 
                  reservedSize: 40, 
                  getTitlesWidget: (value, meta) {
                    // Display each bottom axis title value as an integer
                    return Text(value.toInt().toString(), style: TextStyle(color: Colors.white, fontSize: 12));
                  }
                ),
              ),
            ),
            borderData: FlBorderData(show: true), // Enable border around the chart area
            lineBarsData: [
              LineChartBarData(
                spots: chartData, // Supply the data points for the line chart
                isCurved: true, // Use a curved line to represent the data smoothly
                barWidth: 4, // Set the width of the chart line
                color: Colors.blue, // Color of the chart line
                belowBarData: BarAreaData(show: false), // Do not show the area below the line
              ),
            ],
            backgroundColor: Colors.black, // Set the chart's background color to black
          ),
        ),
      ),
    );
  }
}

// Define a stateless widget to display the current flow rate screen
class CurrentFlowScreen extends StatelessWidget {
  final double currentFlowRate; // Current water flow rate value
  final double previousFlowRate; // Previous water flow rate value
  final double averageFlowRate; // Average water flow rate calculated from the data
  final bool showLeakAlert; // Flag to indicate if a leak alert should be displayed

  // Constructor with required parameters
  CurrentFlowScreen({required this.currentFlowRate, required this.previousFlowRate, required this.averageFlowRate, required this.showLeakAlert});

  // Build the widget tree for the current flow screen
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Set the background color to black
      appBar: AppBar(title: Text("Current Flow Rate")), // App bar with the screen title
      body: Center(
        // Center the content vertically and horizontally
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center the children within the column
          children: [
            // Container to display a leak alert or a stable flow message
            Container(
              padding: EdgeInsets.all(20), // Padding inside the container
              decoration: BoxDecoration(
                // Change the background color based on leak alert status (red for alert, green if stable)
                color: showLeakAlert ? Colors.redAccent : Colors.green,
                borderRadius: BorderRadius.circular(15), // Rounded corners for the container
              ),
              child: Text(
                // Display an alert message if a leak is detected, otherwise indicate stable flow
                showLeakAlert ? "⚠️ Possible Water Leak Detected!" : "✅ Flow Rate Stable",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
            SizedBox(height: 20), // Add vertical spacing
            // Container to display the current flow rate value
            Container(
              padding: EdgeInsets.all(20), // Padding inside the container
              decoration: BoxDecoration(
                color: Colors.blue, // Background color for the container
                borderRadius: BorderRadius.circular(15), // Rounded corners for a smooth appearance
              ),
              child: Column(
                children: [
                  Text(
                    "Current Flow Rate", // Label for the current flow rate
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 10), // Add vertical spacing
                  Text(
                    // Display the current flow rate formatted to two decimal places
                    "${currentFlowRate.toStringAsFixed(2)} L/min",
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20), // Add vertical spacing
            // Container to display the average flow rate value
            Container(
              padding: EdgeInsets.all(20), // Padding inside the container
              decoration: BoxDecoration(
                color: Colors.blue, // Background color for the container
                borderRadius: BorderRadius.circular(15), // Rounded corners for consistency
              ),
              child: Column(
                children: [
                  Text(
                    "Average Flow Rate", // Label for the average flow rate
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 10), // Add vertical spacing
                  Text(
                    // Display the average flow rate formatted to two decimal places
                    "${averageFlowRate.toStringAsFixed(2)} L/min",
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
