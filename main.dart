import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Firebase self-test
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _selfTestFirebase() async {
  try {
    final app = Firebase.app();
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.setLanguageCode('en');
    debugPrint('[FIREBASE] project=${app.options.projectId} appId=${app.options.appId}');
  } catch (e, st) {
    debugPrint('[FIREBASE SELF-TEST FAILED] $e\n$st');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _selfTestFirebase();
  runApp(const MyApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// Root
// ─────────────────────────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Leak Detection App',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(primary: Colors.blueAccent),
      ),
      home: const AuthGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth gate
// ─────────────────────────────────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData) return const LoginScreen();
        return const FlowMonitoringApp();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Login screen
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  String? _validateEmail(String? v) {
  final value = (v ?? '').trim();
  if (value.isEmpty) return 'Enter your email';
  // simpler regex: one "@" and at least one "."
  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
  return null;
}

  String? _validatePassword(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Enter password';
    if (value.length < 6) return 'At least 6 characters';
    return null;
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Sign in failed')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created')));
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Sign up failed')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextFormField(
                controller: _email,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Email'),
                validator: _validateEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Password'),
                validator: _validatePassword,
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _busy ? null : _signIn, child: const Text('Sign In')),
              TextButton(onPressed: _busy ? null : _register, child: const Text('Create Account')),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SensorState (per sensor)
// ─────────────────────────────────────────────────────────────────────────────
class SensorState {
  final List<Map<String, dynamic>> leakHistory = [];
  final List<FlSpot> chartData = [];
  double currentFlowRate = 0.0;
  double previousFlowRate = 0.0;
  double totalFlow = 0.0;
  int ticks = 0;
  int decreasingTrend = 0;
  bool showLeakAlert = false;
  Timer? simTimer;

  double get avgFlow => chartData.isEmpty ? 0.0 : totalFlow / chartData.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// App shell: 3 sensors, bottom nav + tab bar
// ─────────────────────────────────────────────────────────────────────────────
class FlowMonitoringApp extends StatefulWidget {
  const FlowMonitoringApp({super.key});
  @override
  State<FlowMonitoringApp> createState() => _FlowMonitoringAppState();
}

class _FlowMonitoringAppState extends State<FlowMonitoringApp> with SingleTickerProviderStateMixin {
  int _pageIndex = 1; // history=0, chart=1, status=2
  late TabController _tab;
  int get sensorIndex => _tab.index;

  final List<SensorState> sensors = [SensorState(), SensorState(), SensorState()];
  final List<bool> isValveOpen = [true, true, true];
  final List<bool> isButtonDisabled = [false, false, false];
  final List<int> cooldownLeft = [5, 5, 5];

  final FlutterLocalNotificationsPlugin notifier = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
    _initNotifications();
    _startAllSimulations();
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await notifier.initialize(init);
    if (await Permission.notification.isDenied) await Permission.notification.request();
  }

  void _showLeakNotification(int idx) async {
    const android = AndroidNotificationDetails('leak', 'Leak Alerts',
        importance: Importance.max, priority: Priority.high, playSound: true);
    await notifier.show(idx + 1, 'Leak Detected (Sensor ${idx + 1})',
        '⚠️ Water leak detected on Sensor ${idx + 1}', const NotificationDetails(android: android));
  }

  // Simulation start/stop per sensor
  void _startAllSimulations() { for (var i = 0; i < sensors.length; i++) _startSimulation(i); }
  void _startSimulation(int idx) {
    final s = sensors[idx];
    s.simTimer?.cancel();
    s.simTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {
        s.previousFlowRate = s.currentFlowRate;
        if (s.ticks < 120) {
          s.currentFlowRate = 8.0 - idx * 0.3;
        } else {
          s.currentFlowRate = max(1.5, s.currentFlowRate - Random().nextDouble() * 0.05);
        }
        s.totalFlow += s.currentFlowRate;
        s.chartData.add(FlSpot(s.ticks * 0.1, s.currentFlowRate));
        s.ticks++;
        if (s.currentFlowRate < s.previousFlowRate) s.decreasingTrend++; else s.decreasingTrend = 0;
        if (s.decreasingTrend >= 5) { if (!s.showLeakAlert) _showLeakNotification(idx); s.showLeakAlert = true; }
        else { s.showLeakAlert = false; }
        s.leakHistory.add({'time': DateTime.now(), 'flowRate': s.currentFlowRate, 'leak': s.showLeakAlert});
      });
    });
  }
  void _stopSimulation(int idx) { sensors[idx].simTimer?.cancel(); sensors[idx].simTimer = null; }

  // ─────────────────────────────────────────────────────────────────────────────
// 3-sensor UI: build + pages
// ─────────────────────────────────────────────────────────────────────────────

  void _toggleValve(int idx) {
    if (isButtonDisabled[idx]) return;
    setState(() {
      isValveOpen[idx] = !isValveOpen[idx];
      isButtonDisabled[idx] = true;
      cooldownLeft[idx] = 5;
    });

    if (isValveOpen[idx]) {
      _startSimulation(idx);
    } else {
      _stopSimulation(idx);
    }

    Timer.periodic(const Duration(seconds: 1), (t) {
      if (cooldownLeft[idx] <= 1) {
        t.cancel();
        setState(() => isButtonDisabled[idx] = false);
      } else {
        setState(() => cooldownLeft[idx]--);
      }
    });
  }

  @override
  void dispose() {
    for (final s in sensors) {
      s.simTimer?.cancel();
    }
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = sensors[sensorIndex];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Leak Monitor', style: TextStyle(color: Colors.white)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Sensor 1'),
            Tab(text: 'Sensor 2'),
            Tab(text: 'Sensor 3'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: [
        LeakHistoryScreen(leakHistory: s.leakHistory),
        FlowRateChartScreen(
          chartData: s.chartData,
          currentFlowRate: s.currentFlowRate,
          sensorLabel: 'Sensor ${sensorIndex + 1}',
        ),
        CurrentFlowScreen(
          sensorLabel: 'Sensor ${sensorIndex + 1}',
          currentFlowRate: s.currentFlowRate,
          previousFlowRate: s.previousFlowRate,
          averageFlowRate: s.avgFlow,
          showLeakAlert: s.showLeakAlert,
          isValveOpen: isValveOpen[sensorIndex],
          isButtonDisabled: isButtonDisabled[sensorIndex],
          cooldownSecondsLeft: cooldownLeft[sensorIndex],
          onToggleValve: () => _toggleValve(sensorIndex),
        ),
      ][_pageIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        currentIndex: _pageIndex,
        onTap: (i) => setState(() => _pageIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Leak History'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Chart'),
          BottomNavigationBarItem(icon: Icon(Icons.water), label: 'Status'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Leak History Screen
// ─────────────────────────────────────────────────────────────────────────────
class LeakHistoryScreen extends StatelessWidget {
  final List<Map<String, dynamic>> leakHistory;
  const LeakHistoryScreen({super.key, required this.leakHistory});

  @override
  Widget build(BuildContext context) {
    if (leakHistory.isEmpty) {
      return const Center(
        child: Text('No readings yet', style: TextStyle(color: Colors.white70)),
      );
    }
    return ListView.builder(
      itemCount: leakHistory.length,
      itemBuilder: (context, index) {
        final item = leakHistory[index];
        final leak = item['leak'] == true;
        final flow = (item['flowRate'] ?? 0.0) as double;
        final time = item['time'];
        return ListTile(
          leading: Icon(leak ? Icons.warning : Icons.check_circle,
              color: leak ? Colors.red : Colors.green),
          title: Text('Flow: ${flow.toStringAsFixed(2)} L/min',
              style: const TextStyle(color: Colors.white)),
          subtitle: Text('Time: $time',
              style: const TextStyle(color: Colors.grey)),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flow Rate Chart Screen (full vs last 30s toggle)
// ─────────────────────────────────────────────────────────────────────────────
class FlowRateChartScreen extends StatefulWidget {
  final List<FlSpot> chartData;
  final double currentFlowRate;
  final String sensorLabel;

  const FlowRateChartScreen({
    super.key,
    required this.chartData,
    required this.currentFlowRate,
    required this.sensorLabel,
  });

  @override
  State<FlowRateChartScreen> createState() => _FlowRateChartScreenState();
}

class _FlowRateChartScreenState extends State<FlowRateChartScreen> {
  bool showFullRange = false;

  @override
  Widget build(BuildContext context) {
    final latest = widget.chartData.isNotEmpty ? widget.chartData.last.x : 0.0;
    final cutoff = latest - 30.0;
    final data = showFullRange
        ? widget.chartData
        : widget.chartData.where((p) => p.x >= cutoff).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          '${widget.sensorLabel} – Flow: ${widget.currentFlowRate.toStringAsFixed(2)} L/min',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          Row(children: [
            const Text('Full', style: TextStyle(color: Colors.white70)),
            Switch(
              value: showFullRange,
              onChanged: (v) => setState(() => showFullRange = v),
              activeColor: Colors.greenAccent,
            ),
          ]),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LineChart(
          LineChartData(
            backgroundColor: Colors.black,
            gridData: FlGridData(show: true),
            borderData: FlBorderData(show: true),
            titlesData: const FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 40),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 22),
              ),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                isCurved: true,
                spots: data,
                dotData: FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Current Flow Screen
// ─────────────────────────────────────────────────────────────────────────────
class CurrentFlowScreen extends StatelessWidget {
  final String sensorLabel;
  final double currentFlowRate;
  final double previousFlowRate;
  final double averageFlowRate;
  final bool showLeakAlert;
  final bool isValveOpen;
  final bool isButtonDisabled;
  final VoidCallback onToggleValve;
  final int cooldownSecondsLeft;

  const CurrentFlowScreen({
    super.key,
    required this.sensorLabel,
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Status • $sensorLabel',
            style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Current Flow Rate',
                        style: TextStyle(color: Colors.grey, fontSize: 18)),
                    const SizedBox(height: 10),
                    Text(
                      '${currentFlowRate.toStringAsFixed(2)} L/min',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 60,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text('Average',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 16)),
                            const SizedBox(height: 5),
                            Text(averageFlowRate.toStringAsFixed(2),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text('Previous',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 16)),
                            const SizedBox(height: 5),
                            Text(previousFlowRate.toStringAsFixed(2),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color:
                            showLeakAlert ? Colors.redAccent : Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          showLeakAlert ? '⚠️ Leak Detected' : 'Flow Stable',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isButtonDisabled ? null : onToggleValve,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isButtonDisabled ? Colors.grey : (isValveOpen ? Colors.red : Colors.green),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(isValveOpen ? 'Close Valve' : 'Open Valve',
                          style: const TextStyle(
                              fontSize: 20, color: Colors.white)),
                      if (isButtonDisabled) ...[
                        const SizedBox(width: 10),
                        Text('(${cooldownSecondsLeft}s)',
                            style: const TextStyle(
                                fontSize: 18, color: Colors.white)),
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


