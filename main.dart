import 'package:flutter/material.dart'; //imports UI
import 'package:fl_chart/fl_chart.dart'; //imports charts
import 'dart:async'; //imports timer
import 'dart:math'; //imports math
import 'package:firebase_core/firebase_core.dart'; //importns firebase
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; //imports notifications
import 'package:permission_handler/permission_handler.dart'; //importns permission packages


void main() async {
  WidgetsFlutterBinding.ensureInitialized(); //widget binding initialized
  await Firebase.initializeApp(); //initializes firebase
  runApp(const MyApp()); //runs main app widget
}

//root
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, //disable debug banner
      title: 'Leak Detection App', 
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), //theme of app set to blue
        scaffoldBackgroundColor: Colors.black,
      ),
      home: FlowMonitoringApp(), //home widget
    );
  }
}

//main app is stateful which allows for states
class FlowMonitoringApp extends StatefulWidget {
  @override
  _FlowMonitoringAppState createState() => _FlowMonitoringAppState();
}


//establishes state for flow monitoring, valve controls, and navigating the UI
class _FlowMonitoringAppState extends State<FlowMonitoringApp> {
  int _selectedIndex = 1;  //initial bottom navigate state
  List<Map<String, dynamic>> leakHistory = [];  //stores leak data
  Timer? flowRateTimer; //controls simuation

  PageController _pageController = PageController(); 
  int currentPage = 0; 
  double currentFlowRate = 0.0; 
  double previousFlowRate = 0.0; 
  List<FlSpot> chartData = <FlSpot>[]; //data points for chart
  int time = 0; 
  double totalFlow = 0.0; 
  int decreasingTrend = 0; 
  bool showLeakAlert = false; 


 
  bool isValveOpen = true; //valve starts open
  bool isButtonDisabled = false; //for cool down of closing and opening valve





  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();


  @override
  void initState() {
    super.initState();
    initializeNotifications(); //asks device for persmission to send notifications
    startFlowRateSimulation(); //starts simulation
  }


  //sets up notifcations and permissions
  void initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(initSettings);

    if (await Permission.notification.isDenied) {
    await Permission.notification.request(); //if permission currently denied requests permission 
  }
  }

  // leak notification that is set as high priority for customer
  void showLeakNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'leak_alert_channel', //channel ID
      'Leak Alerts', //channel name
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.red,
      enableLights: true,
      playSound: true,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0, //noti ID
      'Leak Detected', //noti title
      '⚠️ A water leak has been detected in the system!', //noti body
      notificationDetails,
    );
  }

  //starts simualtion flow periodically
  void startFlowRateSimulation() {

    flowRateTimer = Timer.periodic(Duration(milliseconds: 100), (timer) { //periodic timer that triggers every 100 ms
      setState(() {
        previousFlowRate = currentFlowRate; //stores current flow before updating


        if (time < 150) { //simulation stable for first 15 seconds
          currentFlowRate = 8.0; //flow rate set at 8
        } else {
          currentFlowRate = max(2.0, currentFlowRate - (Random().nextDouble() * 0.05)); //reduces flow rate by a random amount (up to 0.05) but not lower than 2.0
        }

        totalFlow += currentFlowRate; //total flow
        chartData.add(FlSpot(time.toDouble() * 0.1 , currentFlowRate)); //adds new data point for chart
        time++; //increments time counter


       // if (chartData.length > 20) {
     //    chartData.removeAt(0);
        //}

  
        if (currentFlowRate < previousFlowRate) { //checks if flow rate is decreasing compared to previous value
          decreasingTrend++; //increments counter for decreasing trend
        } else {
          decreasingTrend = 0; //reset counter if flow rate in not decreasing
        }

    
        if (decreasingTrend >= 5) { //if flow rate decreasing for 5 consecutive intervals, show leak alert
          if (!showLeakAlert) {
            showLeakNotification(); //sends leak notification to user
          }
          showLeakAlert = true;
        } else {
          showLeakAlert = false;
        }

        leakHistory.add({ //add current flow data to the leak history log
          'time': DateTime.now(), //stores time
          'flowRate': currentFlowRate, //stores flow rate
          'leak': showLeakAlert, //shows if there was an alert or not
        });
      });
    });
  }

  void stopFlowRateSimulation() { //pauses the flow rate simulation
    flowRateTimer?.cancel();
  }


  double getAverageFlowRate() { //calculates average flow rate
    if (chartData.isEmpty) return 0.0; 
    return totalFlow / chartData.length; 
  }




  void goToPage(int page) { //naviagates to specific page
    _pageController.animateToPage( //transition to selected page
      page,
      duration: Duration(milliseconds: 300), //animate for 300 ms
      curve: Curves.easeInOut, //smooth curve effect
    );
    setState(() {
      currentPage = page; //updates current page index
    });
  }
  
  int cooldownSecondsLeft = 5; //cool down timer for button

  void toggleValve() { //opening and closing of valve
    if (!isButtonDisabled) {
      setState(() {
        isValveOpen = !isValveOpen; //switches state
        isButtonDisabled = true;// disables button after toggling
        cooldownSecondsLeft = 5; //resets cool down timer
      });

      if (isValveOpen) {
        startFlowRateSimulation();  //resumes simulation if valve is open
      } else {
        stopFlowRateSimulation();   //pauses simulation if valve is closed
      }

      Timer.periodic(Duration(seconds: 1), (timer) { //count down timer for cool down of button
        if (cooldownSecondsLeft == 1) {
          timer.cancel();
          setState(() {
            isButtonDisabled = false;
          });
        } else {
          setState(() {
            cooldownSecondsLeft--;
          });
        }
      });
    }
  }

  void _onItemTapped(int index) { //handles bottom navigation bar
    setState(() {
      _selectedIndex = index; //updates page
    });
  }

//////////////////////////////////////////////////////////////////////////////     Bottom Navigation      //////////////////////////////////////////////////////////////////////////
   @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedIndex == 0 //index for leak history page
          ? LeakHistoryScreen(leakHistory: leakHistory) //if index is 0, display leak history page
          : _selectedIndex == 1 //index for flow rate chart page
              ? FlowRateChartScreen(chartData: chartData, currentFlowRate: currentFlowRate) //if index is 1, display flow rate chart page
              : CurrentFlowScreen( //if index is 2, display current flow page
                  currentFlowRate: currentFlowRate,
                  previousFlowRate: previousFlowRate,
                  averageFlowRate: getAverageFlowRate(),
                  showLeakAlert: showLeakAlert,
                  isValveOpen: isValveOpen,
                  isButtonDisabled: isButtonDisabled,
                  cooldownSecondsLeft: cooldownSecondsLeft,
                  onToggleValve: toggleValve,
                ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black, //background color
        selectedItemColor: Colors.blueAccent, //selected page icon is blue
        unselectedItemColor: Colors.grey, //unselected page icon is grey
        currentIndex: _selectedIndex, //indicator for which page is selected
        onTap: _onItemTapped, //tap event
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Leak History'), //history icon for leak history
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Chart'), //chart icon for chart page
          BottomNavigationBarItem(icon: Icon(Icons.water), label: 'Status'), //water icon for status page
        ],
      ),
    );
  }
}


//////////////////////////////////////////////////////////////////////////////     Leak History Screen      //////////////////////////////////////////////////////////////////////////

class LeakHistoryScreen extends StatelessWidget {
  final List<Map<String, dynamic>> leakHistory; //list for leak history data

  LeakHistoryScreen({required this.leakHistory});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, //main backgruond color
      appBar: AppBar(
        backgroundColor: Colors.black, //app bar background color
        title: Text('Leak History', style: TextStyle(color: Colors.white)), //title UI
      ),

      //body 
      body: ListView.builder(  //scrollable list based on leak history length
        itemCount: leakHistory.length,  //number of data points recorded 
        itemBuilder: (context, index) { //builds each list item 
          final item = leakHistory[index]; //access to current leak history item at a given index
          return ListTile(
            leading: Icon( //icon for whether the data was changing or not
              item['leak'] ? Icons.warning : Icons.check_circle,
              color: item['leak'] ? Colors.red : Colors.green,
            ),
            title: Text( //flow rate value (rounded to 2 decimal places)
              'Flow: ${item['flowRate'].toStringAsFixed(2)} L/min',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text( //timestamp value
              'Time: ${item['time'].toString()}',
              style: TextStyle(color: Colors.grey),
            ),
          );
        },
      ),
    );
  }
}

//////////////////////////////////////////////////////////////////////////////     Flow Rate Chart Screen      //////////////////////////////////////////////////////////////////////////


class FlowRateChartScreen extends StatelessWidget {
  final List<FlSpot> chartData; //list for point of (time vs. flow rate) 
  final double currentFlowRate; //most recent flow rate value

  FlowRateChartScreen({required this.chartData, required this.currentFlowRate});  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, //main background color
      appBar: AppBar(  
        backgroundColor: Colors.black,  //app bar background color
        title: Text(
          'Flow Rate Chart | Current: ${currentFlowRate.toStringAsFixed(2)} L/min', //displayed current flow rate at the top of page
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        centerTitle: true,
      ),

      //body
      body: Padding(
        padding: const EdgeInsets.all(8.0), // 8 pixel padding on all sides
        child: LineChart(
          LineChartData(
            minY: 0, //minimum (no negative flow rate)
            maxY: 10, //maximum (max flow rate is 10 L/min)
             gridData: FlGridData(
              show: true, //show grid lines
              drawVerticalLine: true, //vertical lines
              drawHorizontalLine: true, //horizontal lines
              getDrawingHorizontalLine: (value) => FlLine( //grey lines
                color: Colors.grey.withOpacity(0.3),
                strokeWidth: 1,
              ),
              getDrawingVerticalLine: (value) => FlLine( //grey lines
                color: Colors.grey.withOpacity(0.3),
                strokeWidth: 1,
              ),
            ),
     
            extraLinesData: ExtraLinesData( //origin point reference
              horizontalLines: [
                HorizontalLine(y: 0, color: Colors.grey, strokeWidth: 1),
              ],
              verticalLines: [
                VerticalLine(x: 0, color: Colors.grey, strokeWidth: 1),
              ],
            ),

            lineTouchData: LineTouchData( //allows user to interact with graph
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                tooltipBgColor: const Color.fromARGB(255, 128, 128, 128),
                getTooltipItems: (touchedSpots) { //tool tip content
                  return touchedSpots.map((spot) {
                    return LineTooltipItem(
                      '${spot.y.toStringAsFixed(2)} L/min',  //show flow rate with 2 decimal places
                      TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    );
                  }).toList();
                },
              ),
            ),



            titlesData: FlTitlesData( //axis labels
              leftTitles: AxisTitles( //y-axis 
                axisNameWidget: Text("Flow Rate (L/min)", style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) { //shows flow rate numbers
                    return Text(
                      value.toStringAsFixed(1),
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles( //x-axis
                axisNameWidget: Text("Time (seconds)", style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: chartData.isNotEmpty ? (chartData.last.x / 6).clamp(1, 30) : 5, 
                  getTitlesWidget: (value, meta) { //shows time
                    return Text(
                      value.toStringAsFixed(0),
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), //hides top titles (they are meant for bottom side only)
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), //hides right titles (they are meant for left side only)
            ),


            borderData: FlBorderData( //creates border around graph
              show: true,
              border: Border.all(color: Colors.grey.withOpacity(0.5), width: 1),
            ),

            lineBarsData: [ //line that appears on chart
              LineChartBarData(
                spots: chartData, //data points 
                isCurved: true, //allows for smooth curved lines
                curveSmoothness: 0.25,
                barWidth: 2,
                color: Colors.greenAccent,
                belowBarData: BarAreaData( //fills area below line for aesthetic
                  show: true,
               
                ),
                dotData: FlDotData(show: false), //hides dots and just shows line
              ),
            ],

            backgroundColor: Colors.black, //background color
          ),
        ),
      ),
    );
  }
}



//////////////////////////////////////////////////////////////////////////////     Current Flow Screen      //////////////////////////////////////////////////////////////////////////


class CurrentFlowScreen extends StatelessWidget {
  final double currentFlowRate;
  final double previousFlowRate;
  final double averageFlowRate;
  final bool showLeakAlert;


  final bool isValveOpen;
  final bool isButtonDisabled;
  final VoidCallback onToggleValve;
  final int cooldownSecondsLeft;


  CurrentFlowScreen({
    required this.currentFlowRate,
    required this.previousFlowRate,
    required this.averageFlowRate,
    required this.showLeakAlert,
    required this.isValveOpen,
    required this.isButtonDisabled,
    required this.cooldownSecondsLeft,
    required this.onToggleValve,
  });


  


  
 @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, //background color
      appBar: AppBar(
        backgroundColor: Colors.black, //app bar background color
        title: Text('Status', style: TextStyle(color: Colors.white)), //page title
      ),

      //body
      body: SafeArea( //safeArea prevents overlap of UI compononets
        child: Padding(
          padding: const EdgeInsets.all(20.0), //padding aroudn screen
          child: Column(
            children: [
              Expanded( //make display take up availible space
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, //content is vertically centered
                  children: [
                    Text('Current Flow Rate', style: TextStyle(color: Colors.grey, fontSize: 18)), //current flow rate label
                    SizedBox(height: 10), //gap for text and value
                    Text(
                      '${currentFlowRate.toStringAsFixed(2)} L/min', //current flow rate value displayed
                      style: TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.bold),
                    ),

                    SizedBox(height: 30), //spacing

                    Row( //creates a row for displaying current and average side by side
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('Average', style: TextStyle(color: Colors.grey, fontSize: 16)), //average flow rate label
                            SizedBox(height: 5),
                            Text('${averageFlowRate.toStringAsFixed(2)}', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), //average flow rate value displayed
                          ],
                        ),
                        Column(
                          children: [
                            Text('Previous', style: TextStyle(color: Colors.grey, fontSize: 16)), //previous flow rate label
                            SizedBox(height: 5),
                            Text('${previousFlowRate.toStringAsFixed(2)}', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), //previous flow rate value displayed
                          ],
                        ),
                      ],
                    ),

                    SizedBox(height: 40), //spacing

                    Container( //container for status (leak or stable)
                      padding: EdgeInsets.symmetric(vertical: 20),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: showLeakAlert ? Colors.redAccent : Colors.green, //red for leak and green for stable
                        borderRadius: BorderRadius.circular(12), //rounded border
                      ),
                      child: Center(
                        child: Text(
                          showLeakAlert ? '⚠️ Leak Detected' : 'Flow Stable', //displays either leak or stable
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 20), //spacing

              SizedBox( //button for opening and closing valve
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isButtonDisabled ? null : onToggleValve, //disable when button is cooling down
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isButtonDisabled ? Colors.grey : (isValveOpen ? Colors.red : Colors.green), //grey for disabled, green for closed, red for open
                    padding: EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), //rounded border
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        isValveOpen ? 'Close Valve' : 'Open Valve', //displays either open or close
                        style: TextStyle(fontSize: 20, color: Colors.white),
                      ),
                      if (isButtonDisabled) ...[ //timer displayed when button is cooling down
                        SizedBox(width: 10),
                        Text(
                          '(${cooldownSecondsLeft}s)', //cool down timer display
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}