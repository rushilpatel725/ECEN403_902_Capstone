import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import 'firebase_options.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THEME & CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────
class AppTheme {
  static const Color bg = Colors.black;
  static const Color primary = Colors.blueAccent;
  static const Color ok = Colors.greenAccent;
  static const Color warn = Colors.amberAccent;
  static const Color danger = Colors.redAccent;
  static const Color card = Color(0xFF121212);
  static const text = Colors.white;
  static const subtle = Colors.white70;

  static Color severityColor(LeakSeverity s) {
    switch (s) {
      case LeakSeverity.none:
        return ok;
      case LeakSeverity.minor:
        return Colors.lightGreenAccent;
      case LeakSeverity.moderate:
        return warn;
      case LeakSeverity.major:
        return danger;
    }
  }

  static ThemeData theme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(primary: primary),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    appBarTheme: const AppBarTheme(backgroundColor: bg, foregroundColor: text),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(color: Colors.white70),
      enabledBorder:
          UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
      focusedBorder:
          UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
    ),
  );
}

// SECONDARY (partner) Firebase options (unchanged)
const FirebaseOptions partnerOptions = FirebaseOptions(
  apiKey: 'AIzaSyC9DQc4P7SJd6LWbv2XNLT-lKw3AB2kawk',
  appId: '1:577379118014:android:36fe0fa781e217a056e7ef',
  messagingSenderId: '577379118014',
  projectId: 'iot-water-leak',
  databaseURL: 'https://iot-water-leak-default-rtdb.firebaseio.com',
  storageBucket: 'iot-water-leak.firebasestorage.app',
);

// Performance / memory caps & MA window
class AppLimits {
  static const int maxChartPoints = 3000; // ~5 min @ 10 Hz
  static const int maxHistoryItems = 2000;
  static const int maWindow = 20; // ~2s @ 10 Hz
}

// Severity model
enum LeakSeverity { none, minor, moderate, major }
class SeverityResult {
  final LeakSeverity level;
  final String label;
  const SeverityResult(this.level, this.label);
}
SeverityResult assessSeverity({
  required double current,
  required double previous,
  required int decreasingTrend,
}) {
  // New logic:
  // < 1 L/min  -> Minor leak
  // > 7 L/min  -> Major leak
  // 1–7 L/min  -> Normal (None)
  if (current == 0.0) {
    return const SeverityResult(LeakSeverity.minor, 'None');
  }else if (current < 1.0) {
    return const SeverityResult(LeakSeverity.minor, 'Minor');
  } else if (current > 9) {
    return const SeverityResult(LeakSeverity.major, 'Major');
  }else {
    return const SeverityResult(LeakSeverity.none, 'Moderate');
  }
}

// Firebase self-test
Future<void> _selfTestFirebase() async {
  try {
    final app = Firebase.app();
    final auth = FirebaseAuth.instanceFor(app: app);
    await auth.setLanguageCode('en');
    debugPrint(
        '[PRIMARY APP] project=${app.options.projectId} appId=${app.options.appId}');
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Leak Detection App',
      theme: AppTheme.theme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData) return const LoginScreen();
        return const FlowMonitoringApp();
      },
    );
  }
}

// Login screen with Forgot Password
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Sign in failed')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Account created. Check your email to verify (if enabled).')),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Sign up failed')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email above first')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email')),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Failed to send reset email')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                  Row(children: [
                    Expanded(
                        child: ElevatedButton(
                            onPressed: _busy ? null : _signIn,
                            child: const Text('Sign In'))),
                  ]), 
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _register,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Create Account'),
                      ),
                    ),
                  ]),
                  TextButton(
                      onPressed: _busy ? null : _forgotPassword,
                      child: const Text('Forgot password?',
                          style: TextStyle(color: Colors.white70))),
                ]),
          ),
        ),
      ),
    );
  }
}

// Per-sensor runtime model (simulation removed)
class SensorState {
  final List<Map<String, dynamic>> leakHistory = [];
  final List<FlSpot> chartData = [];
  final List<FlSpot> maData = [];
  double currentFlowRate = 0.0;
  double previousFlowRate = 0.0;
  double totalFlow = 0.0;
  int ticks = 0;
  int decreasingTrend = 0;
  bool showLeakAlert = false;

  double get avgFlow =>
      chartData.isEmpty ? 0.0 : totalFlow / chartData.length;

  void addPoint(FlSpot p) {
    chartData.add(p);
    if (chartData.length > AppLimits.maxChartPoints) chartData.removeAt(0);

    final n = (AppLimits.maWindow < chartData.length)
        ? AppLimits.maWindow
        : chartData.length;
    double sum = 0;
    for (int i = chartData.length - n; i < chartData.length; i++) {
      sum += chartData[i].y;
    }
    final ma = sum / n;
    maData.add(FlSpot(p.x, ma));
    if (maData.length > AppLimits.maxChartPoints) maData.removeAt(0);
  }

  void addHistory(Map<String, dynamic> row) {
    leakHistory.add(row);
    if (leakHistory.length > AppLimits.maxHistoryItems) leakHistory.removeAt(0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App shell WITH Dashboard + global valve
// ─────────────────────────────────────────────────────────────────────────────
class FlowMonitoringApp extends StatefulWidget {
  const FlowMonitoringApp({super.key});
  @override
  State<FlowMonitoringApp> createState() => _FlowMonitoringAppState();
}

class _FlowMonitoringAppState extends State<FlowMonitoringApp>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _pageIndex = 0; // 0: Dashboard, 1: History, 2: Chart, 3: Status
  late TabController _tab;
  int get sensorIndex => _tab.index;

  final List<SensorState> sensors = [SensorState(), SensorState(), SensorState()];

  // Global valve state + cooldown
  bool isMainValveOpen = true;
  bool isValveButtonDisabled = false;
  int mainCooldownLeft = 5;

  // Notifications
  final FlutterLocalNotificationsPlugin notifier =
      FlutterLocalNotificationsPlugin();

  // Partner Firebase
  late FirebaseApp _partnerApp;
  late FirebaseDatabase _partnerDb;
  StreamSubscription<DatabaseEvent>? _rtdbSubscription;

  bool _isInBackground = false;
  final _uuid = const Uuid(); // kept for future use if you re-add nonce logic

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tab = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
    _initNotifications();
    _initPartnerFirebase();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInBackground = (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached);
    if (_isInBackground) {
      _maybeScheduleBackgroundAlerts();
    } else {
      _cancelBackgroundAlerts();
    }
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    await notifier.initialize(init);
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> _initPartnerFirebase() async {
    try {
      _partnerApp = Firebase.app('partner');
    } catch (_) {
      _partnerApp =
          await Firebase.initializeApp(name: 'partner', options: partnerOptions);
    }
    _partnerDb = FirebaseDatabase.instanceFor(
        app: _partnerApp, databaseURL: partnerOptions.databaseURL);

    try {
      await FirebaseAuth.instanceFor(app: _partnerApp).signInAnonymously();
      debugPrint('[PartnerAuth] signed in anonymously');
    } catch (e) {
      debugPrint('[PartnerAuth] anonymous sign-in failed: $e');
    }

    try {
      final snap = await _partnerDb.ref('leak_reading').get();
      debugPrint('[Partner RTDB] initial snapshot: ${snap.value}');
    } catch (e) {
      debugPrint('[Partner RTDB] initial get() failed: $e');
    }

    _listenToSensorsFirebase(); // multi-sensor live listener
    _listenForMainValveAck();   // ACK listener (string OPEN/CLOSE or map {state})
  }

  // ── Helpers for multi-sensor realtime updates
  static double _toDoubleSafe(dynamic x) {
    if (x is num) return x.toDouble();
    if (x is String) return double.tryParse(x) ?? 0.0;
    return 0.0;
  }

  static DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    if (v is int) {
      if (v > 2000000000000) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v > 2000000000) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
      return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        final fixed = v.contains(' ') ? v.replaceFirst(' ', 'T') : v;
        try {
          return DateTime.parse(fixed);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  void _applyRealtimeToSensor({
    required int idx,
    required double value,
    required String timestamp,
  }) {
    final s = sensors[idx];

    s.previousFlowRate = s.currentFlowRate;
    s.currentFlowRate = value;
    s.totalFlow += value;

    final x = s.ticks * 0.1;
    s.addPoint(FlSpot(x, value));
    s.ticks++;

    if (s.currentFlowRate < s.previousFlowRate) {
      s.decreasingTrend++;
    } else {
      s.decreasingTrend = 0;
    }

    final sev = assessSeverity(
      current: s.currentFlowRate,
      previous: s.previousFlowRate,
      decreasingTrend: s.decreasingTrend,
    );
    final wasAlert = s.showLeakAlert;
    s.showLeakAlert = (sev.level != LeakSeverity.none);
    if (!wasAlert && s.showLeakAlert) {
      _showLeakNotification(idx, sev);
    }

    s.addHistory({
      'time': timestamp,
      'flowRate': s.currentFlowRate,
      'severity': sev.label,
    });
  }

  // ── Unified Firebase listener reading: /leak_reading
  // Reads: local_sensor, remote1_sensor, remote2_sensor (plus time)
  void _listenToSensorsFirebase() {
    final ref = _partnerDb.ref('leak_reading');

    _rtdbSubscription?.cancel();
    _rtdbSubscription = ref.onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null) {
        debugPrint('[RTDB] /leak_reading is empty.');
        return;
      }

      Map<String, dynamic>? latestObj;

      try {
        if (raw is Map) {
          // Case A: single object with expected keys
          final hasKeys = raw.containsKey('local_sensor') ||
              raw.containsKey('remote_sensor_1') ||
              raw.containsKey('remote_sensor_2');

          if (hasKeys) {
            latestObj = {
              'local_sensor': _toDoubleSafe(raw['local_sensor']),
              'remote_sensor_1': _toDoubleSafe(raw['remote_sensor_1']),
              'remote_sensor_2': _toDoubleSafe(raw['remote_sensor_2']),
              'time': raw['time']?.toString() ?? DateTime.now().toString(),
            };
          } else {
            // Case B: map of child objects → pick newest by time
            final Map<dynamic, dynamic> m = raw;
            Map<String, dynamic>? best;
            DateTime? bestTs;

            for (final entry in m.entries) {
              final v = entry.value;
              if (v is Map) {
                final obj = {
                  'local_sensor': _toDoubleSafe(v['local_sensor']),
                  'remote_sensor_1': _toDoubleSafe(v['remote_sensor_1']),
                  'remote_sensor_2': _toDoubleSafe(v['remote_sensor_2']),
                  'time': v['time']?.toString(),
                };
                final ts = _parseTime(obj['time']);
                if (best == null ||
                    (ts != null && (bestTs == null || ts.isAfter(bestTs)))) {
                  best = obj;
                  bestTs = ts ?? bestTs;
                }
              }
            }
            latestObj = best;
          }
        } else {
          debugPrint('[RTDB] Unexpected data type: ${raw.runtimeType}');
          return;
        }

        if (latestObj == null) return;

        final timeStr =
            (latestObj['time'] ?? DateTime.now().toString()).toString();

        // Map new fields → sensors 0,1,2
        final vLocal = _toDoubleSafe(latestObj['local_sensor']);
        final vR1 = _toDoubleSafe(latestObj['remote_sensor_1']);
        final vR2 = _toDoubleSafe(latestObj['remote_sensor_2']);

        setState(() {
          _applyRealtimeToSensor(
              idx: 0, value: vLocal, timestamp: timeStr); // Sensor 1
          _applyRealtimeToSensor(
              idx: 1, value: vR1, timestamp: timeStr); // Sensor 2
          _applyRealtimeToSensor(
              idx: 2, value: vR2, timestamp: timeStr); // Sensor 3
        });
      } catch (e) {
        debugPrint('[RTDB] Parse error: $e');
      }
    }, onError: (e) {
      debugPrint('[RTDB] onValue error: $e');
    });
  }

  // Notifications
  void _showLeakNotification(int idx, SeverityResult sev) async {
    final android = AndroidNotificationDetails(
      'leak',
      'Leak Alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      color: AppTheme.severityColor(sev.level),
    );
    await notifier.show(
      100 + idx,
      'Leak (${sev.label}) • Sensor ${idx + 1}',
      'Flow: ${sensors[idx].currentFlowRate.toStringAsFixed(2)} L/min',
      NotificationDetails(android: android),
    );
  }

  Future<void> _maybeScheduleBackgroundAlerts() async {
  for (int i = 0; i < sensors.length; i++) {
    final s = sensors[i];
    final sev = assessSeverity(
      current: s.currentFlowRate,
      previous: s.previousFlowRate,
      decreasingTrend: s.decreasingTrend,
    );

    // Now matches leak logic: any leak (Minor or Major) gets alerts
    if (sev.level != LeakSeverity.none) {
      final android = AndroidNotificationDetails(
        'leak_bg',
        'Leak Alerts (Background)',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        color: AppTheme.severityColor(sev.level),
      );
      await notifier.periodicallyShow(
        1000 + i,
        'Background Leak (${sev.label}) • Sensor ${i + 1}',
        'Flow: ${s.currentFlowRate.toStringAsFixed(2)} L/min',
        RepeatInterval.everyMinute,
        NotificationDetails(android: android),
        androidScheduleMode: AndroidScheduleMode.inexact,
      );
    }
  }
}

  Future<void> _cancelBackgroundAlerts() async {
    for (int i = 0; i < sensors.length; i++) {
      await notifier.cancel(1000 + i);
    }
  }

  // ── Valve command → /cmd/main_valve  (string-only version)
  Future<void> _sendMainValveCommand({required bool closeValve}) async {
    final ref = _partnerDb.ref('cmd/main_valve');
    // Write just "CLOSE" or "OPEN"
    await ref.set(closeValve ? 'CLOSE' : 'OPEN');
  }

  // ── ACK listener ← /ack/main_valve  (no nonce matching)
  void _listenForMainValveAck() {
    final ref = _partnerDb.ref('ack/main_valve');
    ref.onValue.listen((event) {
      final v = event.snapshot.value;
      String? state;

      if (v is String) {
        state = v.toUpperCase();
      } else if (v is Map) {
        state = (v['state'] ?? '').toString().toUpperCase();
      }

      if (state == 'OPEN' || state == 'CLOSE') {
        final isOpen = state == 'OPEN';
        if (mounted) {
          setState(() {
            isMainValveOpen = isOpen;
            isValveButtonDisabled = false; // re-enable button on ACK
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Valve ACK: $state')),
          );
        }
      }
    });
  }

  // GLOBAL VALVE CONTROL (optimistic; cooldown only)
  void _toggleMainValve() {
    if (isValveButtonDisabled) return;

    final willOpen = !isMainValveOpen;

    // Optimistic UI + cooldown
    setState(() {
      isMainValveOpen = willOpen;
      isValveButtonDisabled = true;
      mainCooldownLeft = 5;
    });

    // Send simple string command
    unawaited(_sendMainValveCommand(closeValve: !willOpen));

    // Cooldown visual
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (mainCooldownLeft <= 1) {
        t.cancel();
        if (mounted) setState(() => isValveButtonDisabled = false);
      } else {
        if (mounted) setState(() => mainCooldownLeft--);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rtdbSubscription?.cancel();
    _tab.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Chart helpers (bug-fixed _niceBounds: avoid mutating params)
  // ───────────────────────────────────────────────────────────────────────────
  ({double min, double max}) _niceBounds(double rawMin, double rawMax) {
    var lo = rawMin;
    var hi = rawMax;

    if (lo == hi) {
      final pad = hi.abs() * 0.2 + 1.0;
      return (min: lo - pad, max: hi + pad);
    }
    if (lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    final range = (hi - lo);
    final pad = range * 0.1;
    final minVal = (0.0 > lo - pad) ? 0.0 : lo - pad;
    final maxVal = hi + pad;
    double roundToHalf(double v) => (v * 2).floorToDouble() / 2;
    double ceilToHalf(double v) => (v * 2).ceilToDouble() / 2;
    return (min: roundToHalf(minVal), max: ceilToHalf(maxVal));
  }

  double _niceYInterval(double range) {
    if (range <= 1) return 0.2;
    if (range <= 2) return 0.5;
    if (range <= 5) return 1.0;
    if (range <= 10) return 2.0;
    if (range <= 20) return 5.0;
    return 10.0;
  }

  double _niceXInterval(double range) {
    if (range <= 10) return 2;
    if (range <= 30) return 5;
    if (range <= 60) return 10;
    if (range <= 300) return 60;
    return 120;
  }

  @override
  Widget build(BuildContext context) {
    final s = sensors[sensorIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leak Monitor'),
        bottom: _pageIndex == 0
            ? null
            : TabBar(
                controller: _tab,
                indicatorColor: AppTheme.primary,
                labelColor: AppTheme.text,
                unselectedLabelColor: AppTheme.subtle,
                tabs: const [
                  Tab(text: 'Sensor 1'),
                  Tab(text: 'Sensor 2'),
                  Tab(text: 'Sensor 3')
                ],
              ),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: [
        // 0. Dashboard
        DashboardScreen(
          sensors: sensors,
          isMainValveOpen: isMainValveOpen,
          isValveButtonDisabled: isValveButtonDisabled,
          mainCooldownLeft: mainCooldownLeft,
          onToggleMainValve: _toggleMainValve,
          onOpenSensor: (i) {
            _tab.index = i;
            setState(() => _pageIndex = 3);
          },
        ),
        // 1. History
        LeakHistoryScreen(leakHistory: s.leakHistory),
        // 2. Chart
        FlowRateChartScreen(
          chartData: s.chartData,
          maData: s.maData,
          currentFlowRate: s.currentFlowRate,
          sensorLabel: 'Sensor ${sensorIndex + 1}',
        ),
        // 3. Status
        CurrentFlowScreen(
          sensorLabel: 'Sensor ${sensorIndex + 1}',
          currentFlowRate: s.currentFlowRate,
          previousFlowRate: s.previousFlowRate,
          averageFlowRate: s.avgFlow,
          severity: assessSeverity(
              current: s.currentFlowRate,
              previous: s.previousFlowRate,
              decreasingTrend: s.decreasingTrend),
          isMainValveOpen: isMainValveOpen,
          isValveButtonDisabled: isValveButtonDisabled,
          mainCooldownLeft: mainCooldownLeft,
          onToggleMainValve: _toggleMainValve,
        ),
      ][_pageIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppTheme.bg,
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: Colors.grey,
        currentIndex: _pageIndex,
        onTap: (i) => setState(() => _pageIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Chart'),
          BottomNavigationBarItem(icon: Icon(Icons.water), label: 'Status'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Screen (global valve button + sensor cards)
// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends StatelessWidget {
  final List<SensorState> sensors;
  final bool isMainValveOpen;
  final bool isValveButtonDisabled;
  final int mainCooldownLeft;
  final VoidCallback onToggleMainValve;
  final void Function(int idx) onOpenSensor;

  const DashboardScreen({
    super.key,
    required this.sensors,
    required this.isMainValveOpen,
    required this.isValveButtonDisabled,
    required this.mainCooldownLeft,
    required this.onToggleMainValve,
    required this.onOpenSensor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Global button up top
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isValveButtonDisabled ? null : onToggleMainValve,
              style: ElevatedButton.styleFrom(
                backgroundColor: isValveButtonDisabled
                    ? Colors.grey
                    : (isMainValveOpen ? AppTheme.danger : AppTheme.ok),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isMainValveOpen ? Icons.lock_open : Icons.lock),
                  const SizedBox(width: 8),
                  Text(isMainValveOpen ? 'Close Main Valve' : 'Open Main Valve'),
                  if (isValveButtonDisabled) ...[
                    const SizedBox(width: 10),
                    Text('(${mainCooldownLeft}s)'),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Sensors grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sensors.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.8,
            ),
            itemBuilder: (context, i) {
              final s = sensors[i];
              final sev = assessSeverity(
                  current: s.currentFlowRate,
                  previous: s.previousFlowRate,
                  decreasingTrend: s.decreasingTrend);
              final color = AppTheme.severityColor(sev.level);

              return InkWell(
                onTap: () => onOpenSensor(i),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 8)
                    ],
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sensor ',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700))
                            .buildWithNumber(i + 1),
                        const SizedBox(height: 8),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              border: Border.all(color: color, width: 1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Severity: ${sev.label}',
                                style: TextStyle(
                                    color: color, fontWeight: FontWeight.bold)),
                          ),
                          const Spacer(),
                          Text('${s.currentFlowRate.toStringAsFixed(2)} L/min',
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Avg: ${s.avgFlow.toStringAsFixed(2)}  •  Prev: ${s.previousFlowRate.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// Tiny helper to keep "Sensor X" clean without string interpolation clutter
extension _SensorLabel on Text {
  Text buildWithNumber(int n) =>
      Text('$data$n', style: style, textAlign: textAlign, key: key);
}

// ─────────────────────────────────────────────────────────────────────────────
// Leak History Screen (newest first + severity chip)
// ─────────────────────────────────────────────────────────────────────────────
class LeakHistoryScreen extends StatelessWidget {
  final List<Map<String, dynamic>> leakHistory;
  const LeakHistoryScreen({super.key, required this.leakHistory});

  @override
  Widget build(BuildContext context) {
    if (leakHistory.isEmpty) {
      return const Center(
          child:
              Text('No readings yet', style: TextStyle(color: Colors.white70)));
    }
    final items = leakHistory.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final flow = (item['flowRate'] ?? 0.0) as double;
        final time = item['time'];
        final sevLabel = (item['severity'] ?? 'None') as String;
        final level = {
              'None': LeakSeverity.none,
              'Minor': LeakSeverity.minor,
              'Moderate': LeakSeverity.moderate,
              'Major': LeakSeverity.major
            }[sevLabel] ??
            LeakSeverity.none;
        final color = AppTheme.severityColor(level);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            dense: false,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            tileColor: AppTheme.card,
            leading: Icon(Icons.water_damage, color: color),
            title: Text('Flow: ${flow.toStringAsFixed(2)} L/min',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            subtitle:
                Text('Time: $time', style: const TextStyle(color: Colors.white70)),
            trailing: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                border: Border.all(color: color, width: 1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(sevLabel,
                  style:
                      TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flow Rate Chart Screen (axes + moving average + legend)
// ─────────────────────────────────────────────────────────────────────────────
class FlowRateChartScreen extends StatefulWidget {
  final List<FlSpot> chartData;
  final List<FlSpot> maData;
  final double currentFlowRate;
  final String sensorLabel;

  const FlowRateChartScreen({
    super.key,
    required this.chartData,
    required this.maData,
    required this.currentFlowRate,
    required this.sensorLabel,
  });

  @override
  State<FlowRateChartScreen> createState() => _FlowRateChartScreenState();
}

class _FlowRateChartScreenState extends State<FlowRateChartScreen> {
  bool showFullRange = false;
  bool showMA = true;

  static const Color maColor = Colors.orangeAccent;
  static const Color mainColor = AppTheme.primary;

  double _niceYInterval(double range) {
    if (range <= 1) return 0.2;
    if (range <= 2) return 0.5;
    if (range <= 5) return 1.0;
    if (range <= 10) return 2.0;
    if (range <= 20) return 5.0;
    return 10.0;
  }

  double _niceXInterval(double range) {
    if (range <= 10) return 2;
    if (range <= 30) return 5;
    if (range <= 60) return 10;
    if (range <= 300) return 60;
    return 120;
  }

  ({double min, double max}) _niceBounds(double rawMin, double rawMax) {
    var lo = rawMin;
    var hi = rawMax;
    if (lo == hi) {
      final pad = hi.abs() * 0.2 + 1.0;
      return (min: lo - pad, max: hi + pad);
    }
    if (lo > hi) {
      final t = lo; lo = hi; hi = t;
    }
    final range = (hi - lo);
    final pad = range * 0.1;
    final minVal = (0.0 > lo - pad) ? 0.0 : lo - pad;
    final maxVal = hi + pad;
    double roundToHalf(double v) => (v * 2).floorToDouble() / 2;
    double ceilToHalf(double v) => (v * 2).ceilToDouble() / 2;
    return (min: roundToHalf(minVal), max: ceilToHalf(maxVal));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chartData.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          title: Text(
              '${widget.sensorLabel} – Flow: ${widget.currentFlowRate.toStringAsFixed(2)} L/min'),
          actions: [
            Row(children: [
              const Text('Full', style: TextStyle(color: Colors.white70)),
              Switch(
                  value: showFullRange,
                  onChanged: (v) => setState(() => showFullRange = v),
                  activeColor: AppTheme.ok),
              const SizedBox(width: 6),
              const Text('MA', style: TextStyle(color: Colors.white70)),
              Switch(
                  value: showMA,
                  onChanged: (v) => setState(() => showMA = v),
                  activeColor: AppTheme.ok),
            ]),
          ],
        ),
        body: const Center(
            child:
                Text('Waiting for data…', style: TextStyle(color: Colors.white70))),
      );
    }

    final latestX = widget.chartData.last.x;
    final windowStart = latestX - 30.0;
    final sliced = showFullRange
        ? widget.chartData
        : widget.chartData.where((p) => p.x >= windowStart).toList();
    final slicedMA =
        showFullRange ? widget.maData : widget.maData.where((p) => p.x >= windowStart).toList();

    double minX = sliced.first.x, maxX = sliced.last.x;
    for (final s in sliced) {
      if (s.x < minX) minX = s.x;
      if (s.x > maxX) maxX = s.x;
    }
    final xPad = (maxX - minX).abs() * 0.04 + 0.5;
    minX = (0 > minX - xPad) ? 0 : minX - xPad;
    maxX += xPad;

    double minY = sliced.first.y, maxY = sliced.first.y;
    for (final s in sliced) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    final yBounds = _niceBounds(minY, maxY);
    minY = yBounds.min;
    maxY = yBounds.max;

    final xRange = (maxX - minX).clamp(1e-6, double.infinity);
    final yRange = (maxY - minY).clamp(1e-6, double.infinity);
    final xStep = _niceXInterval(xRange);
    final yStep = _niceYInterval(yRange);

    Widget _bottomTitle(double value, TitleMeta meta) {
      if ((value - minX) % xStep > 1e-6 && (minX - value) % xStep > 1e-6) {
        return const SizedBox.shrink();
      }
      return SideTitleWidget(
          axisSide: meta.axisSide,
          space: 8,
          child: Text('${value.toStringAsFixed(0)}s',
              style: const TextStyle(color: Colors.white70, fontSize: 12)));
    }

    Widget _leftTitle(double value, TitleMeta meta) {
      double remainder = (value - minY) % yStep;
      if (remainder.abs() > 1e-6 && (yStep - remainder).abs() > 1e-6) {
        return const SizedBox.shrink();
      }
      return SideTitleWidget(
          axisSide: meta.axisSide,
          space: 8,
          child: Text(value.toStringAsFixed(1),
              style: const TextStyle(color: Colors.white70, fontSize: 12)));
    }

    Widget legend() {
      Widget item(Color c, String label) {
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 14,
              height: 14,
              decoration:
                  BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]);
      }

      final children = <Widget>[
        item(mainColor, 'Flow'),
        if (showMA) ...[const SizedBox(width: 12), item(maColor, 'Moving Avg')],
      ];
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24, width: 1)),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
    }

    final chart = LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        backgroundColor: AppTheme.bg,
        borderData: FlBorderData(
            show: true,
            border: const Border.fromBorderSide(
                BorderSide(color: Colors.white24, width: 1))),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          drawHorizontalLine: true,
          verticalInterval: xStep,
          horizontalInterval: yStep,
          getDrawingVerticalLine: (_) =>
              const FlLine(color: Colors.white12, strokeWidth: 1),
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Colors.white12, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Text('Flow (L/min)',
                    style:
                        TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            axisNameSize: 28,
            sideTitles: SideTitles(
                showTitles: true, reservedSize: 48, getTitlesWidget: _leftTitle),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Padding(
                padding: EdgeInsets.only(top: 6.0),
                child: Text('Time (s)',
                    style:
                        TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
            axisNameSize: 24,
            sideTitles: SideTitles(
                showTitles: true, reservedSize: 28, getTitlesWidget: _bottomTitle),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        clipData:
            const FlClipData(left: false, right: false, top: false, bottom: false),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            barWidth: 3,
            color: mainColor,
            spots: sliced,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  mainColor.withOpacity(0.22),
                  mainColor.withOpacity(0.04)
                ],
              ),
            ),
          ),
          if (showMA)
            LineChartBarData(
                isCurved: true,
                barWidth: 2,
                color: maColor,
                spots: slicedMA,
                dotData: FlDotData(show: false)),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.black87,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touchedSpots) => touchedSpots
                .map((s) => LineTooltipItem(
                      't=${s.x.toStringAsFixed(1)}s\n${s.y.toStringAsFixed(2)} L/min',
                      const TextStyle(color: Colors.white),
                    ))
                .toList(),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(
            '${widget.sensorLabel} – Flow: ${widget.currentFlowRate.toStringAsFixed(2)} L/min'),
        actions: [
          Row(children: [
            const Text('Full', style: TextStyle(color: Colors.white70)),
            Switch(
                value: showFullRange,
                onChanged: (v) => setState(() => showFullRange = v),
                activeColor: AppTheme.ok),
            const SizedBox(width: 6),
            const Text('MA', style: TextStyle(color: Colors.white70)),
            Switch(
                value: showMA,
                onChanged: (v) => setState(() => showMA = v),
                activeColor: AppTheme.ok),
          ]),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 22, 18),
        child: Stack(children: [
          Positioned.fill(child: chart),
          Positioned(top: 6, right: 6, child: legend()),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Screen (GLOBAL valve button)
// ─────────────────────────────────────────────────────────────────────────────
class CurrentFlowScreen extends StatelessWidget {
  final String sensorLabel;
  final double currentFlowRate;
  final double previousFlowRate;
  final double averageFlowRate;
  final SeverityResult severity;

  final bool isMainValveOpen;
  final bool isValveButtonDisabled;
  final int mainCooldownLeft;
  final VoidCallback onToggleMainValve;

  const CurrentFlowScreen({
    super.key,
    required this.sensorLabel,
    required this.currentFlowRate,
    required this.previousFlowRate,
    required this.averageFlowRate,
    required this.severity,
    required this.isMainValveOpen,
    required this.isValveButtonDisabled,
    required this.mainCooldownLeft,
    required this.onToggleMainValve,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.severityColor(severity.level);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('Status • $sensorLabel'),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Expanded(
              child:
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Current Flow Rate',
                    style: TextStyle(color: Colors.white70, fontSize: 18)),
                const SizedBox(height: 10),
                Text('${currentFlowRate.toStringAsFixed(2)} L/min',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [
                        const Text('Average',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 5),
                        Text(averageFlowRate.toStringAsFixed(2),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                      ]),
                      Column(children: [
                        const Text('Previous',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 16)),
                        const SizedBox(height: 5),
                        Text(previousFlowRate.toStringAsFixed(2),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ]),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(12)),
                  child: Center(
                      child: Text('Severity: ${severity.label}',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.bold))),
                ),
              ]), 
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isValveButtonDisabled ? null : onToggleMainValve,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isValveButtonDisabled
                      ? Colors.grey
                      : (isMainValveOpen ? AppTheme.danger : AppTheme.ok),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isMainValveOpen ? Icons.lock_open : Icons.lock),
                      const SizedBox(width: 8),
                      Text(
                          isMainValveOpen
                              ? 'Close Main Valve'
                              : 'Open Main Valve',
                          style: const TextStyle(
                              fontSize: 20, color: Colors.white)),
                      if (isValveButtonDisabled) ...[
                        const SizedBox(width: 10),
                        Text('(${mainCooldownLeft}s)',
                            style: const TextStyle(
                                fontSize: 18, color: Colors.white)),
                      ],
                    ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}