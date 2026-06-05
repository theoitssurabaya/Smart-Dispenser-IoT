import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import 'package:mobile_scanner/mobile_scanner.dart' hide Address; 

import 'package:mailer/mailer.dart'; 
import 'package:mailer/smtp_server.dart'; 
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Dispenser',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.light),
        cardTheme: CardThemeData(elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// --- GATEWAY AUTH ---
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: snapshot.hasData ? const QRScanPage() : const LoginPage(),
        );
      },
    );
  }
}

// --- HALAMAN SCAN QR ---
class QRScanPage extends StatefulWidget {
  const QRScanPage({super.key});
  @override
  State<QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<QRScanPage> {
  bool _isScanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        setState(() => _isScanned = true);
        String dispenserId = barcode.rawValue!;
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => DashboardPage(dispenserId: dispenserId))
        );
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan QR Dispenser"), 
        backgroundColor: Colors.teal, 
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(flex: 5, child: MobileScanner(onDetect: _onDetect)),
          Expanded(
            flex: 1,
            child: Container(
              alignment: Alignment.center,
              color: Colors.white,
              child: const Text("Arahkan kamera ke QR Code di Dispenser", style: TextStyle(fontSize: 16, color: Colors.grey)),
            ),
          )
        ],
      ),
    );
  }
}

// --- HALAMAN LOGIN ---
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = false;

  Future<void> _processAuth(bool isRegister) async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      String email = "${_userController.text.trim()}@dispenser.app";
      String dateNow = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (isRegister) {
        UserCredential uc = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email, password: _passController.text.trim()
        );
        await FirebaseFirestore.instance.collection('users').doc(uc.user!.uid).set({
          'username': _userController.text.trim(),
          'quota': 1000, 
          'last_reset': dateNow,
        });
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: _passController.text.trim()
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: ${e.toString()}"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Hero(tag: 'logo', child: Icon(Icons.water_drop_rounded, size: 80, color: Colors.teal)),
              const SizedBox(height: 20),
              const Text("Dispenser Pintar", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 40),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      TextField(controller: _userController, decoration: const InputDecoration(labelText: "Username", prefixIcon: Icon(Icons.person))),
                      const SizedBox(height: 16),
                      TextField(controller: _passController, decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock)), obscureText: true),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                          onPressed: _isLoading ? null : () => _processAuth(false),
                          child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("MASUK"),
                        ),
                      ),
                      TextButton(onPressed: () => _processAuth(true), child: const Text("Belum punya akun? Daftar"))
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

// --- DASHBOARD PAGE ---
class DashboardPage extends StatefulWidget {
  final String dispenserId;
  const DashboardPage({super.key, required this.dispenserId});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _amountController = TextEditingController();
  late MqttServerClient client;
  String statusMqtt = "Connecting...";
  bool isProcessing = false;
  int _lastRequestAmount = 0;

  @override
  void initState() {
    super.initState();
    _checkDailyReset();
    _setupMqtt();
  }

  // --- LOGIC RESET HARIAN ---
  Future<void> _checkDailyReset() async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userSnap = await userRef.get();
      if (userSnap.exists) {
        if (userSnap.data()?['last_reset'] != today) {
          await userRef.update({'quota': 1000, 'last_reset': today});
        }
      }
    }
  }

  Future<void> _sendEmailAlert(int currentLevel) async {
    // Ganti dengan kredensial email Admin
    String username = 'xxx@gmail.com'; 
    String password = 'xxxx xxxx xxxx xxxx'; 

    final smtpServer = gmail(username, password);
    final message = Message()
      ..from = Address(username, 'Smart Dispenser System')
      //Ganti dengan email tujuan Admin
      ..recipients.add('xxx@gmail.com')
      ..subject = 'PERINGATAN: Air Dispenser Menipis!'
      ..text = 'Halo Admin,\n\nDispenser ID: ${widget.dispenserId} sisa air tinggal $currentLevel ml.\n\nTerima Kasih.';

    try {
      await send(message, smtpServer);
    } catch (e) {
      debugPrint("Gagal kirim email: $e");
    }
  }

  Future<void> _setupMqtt() async {
    String broker = 'c7d3b91c59cf4959bae2182f1523052e.s1.eu.hivemq.cloud';
    String clientId = 'flutter_disp_${DateTime.now().millisecondsSinceEpoch}';
    client = MqttServerClient.withPort(broker, clientId, 8883);
    client.secure = true;
    client.setProtocolV311();
    client.onBadCertificate = (dynamic cert) => true;
    client.autoReconnect = true;

    client.onConnected = () { if (mounted) setState(() => statusMqtt = "Siap ✓"); };
    client.onDisconnected = () { if (mounted) setState(() => statusMqtt = "Offline ✗"); };

    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs('theoo', 'Theo12345')
        .startClean();

    try {
      await client.connect();
      client.subscribe("dispenser/report", MqttQos.atMostOnce);
      client.updates?.listen(_onReportReceived);
    } catch (e) {
      if (mounted) setState(() => statusMqtt = "Offline ✗");
    }
  }

  void _onReportReceived(List<MqttReceivedMessage<MqttMessage?>>? c) async {
    final recMess = c![0].payload as MqttPublishMessage;
    final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    final data = jsonDecode(pt);
    
    String status = data['status'] ?? "";

    if (status == "LEVEL_UPDATE") {
      int realRemaining = data['remaining_ml'] ?? 0;
      await FirebaseFirestore.instance
          .collection('dispensers')
          .doc(widget.dispenserId)
          .update({'current_level': realRemaining});
      return; 
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (data['uid'] == user.uid) { 
      int actualUsed = data['used_ml'] ?? 0;
      int realRemaining = data['remaining_ml'] ?? -1; 
      
      int difference = _lastRequestAmount - actualUsed;

      if (difference > 0) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'quota': FieldValue.increment(difference)});
      }

      if (realRemaining >= 0) {
        await FirebaseFirestore.instance.collection('dispensers').doc(widget.dispenserId).update({
          'current_level': realRemaining 
        });
      }

      if (mounted) {
        setState(() => isProcessing = false);
        
        if (status == "ABORTED") {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("PENGISIAN BERHENTI: Gelas tidak terdeteksi!"),
            backgroundColor: Colors.orange));
        }

        _showResultDialog(actualUsed, difference);
      }
    }
  }

  void _showResultDialog(int used, int refund) {
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), SizedBox(width: 10), Text("Selesai")]),
      content: Text("Air keluar: ${used}ml\n${refund > 0 ? 'Sisa ${refund}ml dikembalikan ke saldo.' : ''}"),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData || !userSnap.data!.exists) return const Center(child: CircularProgressIndicator());
        var userData = userSnap.data!.data() as Map<String, dynamic>;
        int userQuota = userData['quota'] ?? 0;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('dispensers').doc(widget.dispenserId).snapshots(),
          builder: (context, dispSnap) {
            int dispenserLevel = 0;
            if (dispSnap.hasData && dispSnap.data!.exists) {
               var dispData = dispSnap.data!.data() as Map<String, dynamic>;
               dispenserLevel = dispData['current_level'] ?? 0;
            }

            return Scaffold(
              backgroundColor: Colors.grey.shade50,
              body: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 120.0, pinned: true, backgroundColor: Colors.teal,
                    flexibleSpace: FlexibleSpaceBar(
                      centerTitle: false, titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                      title: Text("Hai, ${userData['username']}", style: const TextStyle(color: Colors.white)),
                    ),
                    actions: [IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileConfigPage())))],
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: statusMqtt.contains("Siap") ? Colors.green.shade100 : Colors.red.shade100, borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.wifi, size: 16, color: statusMqtt.contains("Siap") ? Colors.green : Colors.red),
                            const SizedBox(width: 8),
                            Text(statusMqtt, style: TextStyle(color: statusMqtt.contains("Siap") ? Colors.green.shade800 : Colors.red.shade800))
                          ]),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 250,
                          child: SfRadialGauge(
                            title: const GaugeTitle(text: "Kuota Harian Anda", textStyle: TextStyle(fontWeight: FontWeight.bold)),
                            axes: <RadialAxis>[
                              RadialAxis(
                                minimum: 0, maximum: 1000, 
                                showLabels: false, showTicks: false,
                                axisLineStyle: AxisLineStyle(thickness: 0.2, cornerStyle: CornerStyle.bothCurve, color: Colors.teal.withOpacity(0.1), thicknessUnit: GaugeSizeUnit.factor),
                                pointers: <GaugePointer>[
                                  RangePointer(
                                    value: userQuota.toDouble(), width: 0.2, sizeUnit: GaugeSizeUnit.factor, cornerStyle: CornerStyle.bothCurve,
                                    gradient: const SweepGradient(colors: <Color>[Colors.tealAccent, Colors.teal], stops: <double>[0.25, 0.75]),
                                  )
                                ],
                                annotations: <GaugeAnnotation>[
                                  GaugeAnnotation(
                                    positionFactor: 0.1, angle: 90,
                                    widget: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Text("$userQuota", style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.teal)),
                                      const Text("ml Sisa", style: TextStyle(color: Colors.grey, fontSize: 16)),
                                    ]),
                                  )
                                ],
                              )
                            ],
                          ),
                        ),
                        Card(
                          color: dispenserLevel < 500 ? Colors.red.shade50 : Colors.blue.shade50,
                          child: ListTile(
                            leading: Icon(Icons.water_damage, color: dispenserLevel < 500 ? Colors.red : Colors.blue),
                            title: const Text("Sisa Air di Galon"),
                            subtitle: Text(dispenserLevel < 500 ? "Segera isi ulang!" : "Kondisi Aman"),
                            trailing: Text("$dispenserLevel / 19000 ml", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(controller: _amountController, keyboardType: TextInputType.number, enabled: !isProcessing, decoration: const InputDecoration(labelText: "Isi berapa ml?", suffixText: "ml", prefixIcon: Icon(Icons.water_drop))),
                        const SizedBox(height: 20),
                        SizedBox(width: double.infinity, height: 55, child: ElevatedButton(
                          onPressed: isProcessing ? null : () async {
                            int req = int.tryParse(_amountController.text) ?? 0;
                            if (req > 0 && req <= userQuota && req <= dispenserLevel && statusMqtt.contains("Siap")) {
                              setState(() => isProcessing = true);
                              _lastRequestAmount = req;
                              
                              // Kurangi dulu kuota user & dispenser (Optimistic UI)
                              await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'quota': FieldValue.increment(-req)});
                              await FirebaseFirestore.instance.collection('dispensers').doc(widget.dispenserId).update({'current_level': FieldValue.increment(-req)});
                              
                              if (dispenserLevel - req < 500) _sendEmailAlert(dispenserLevel - req);
                              
                              final b = MqttClientPayloadBuilder();
                              b.addString(jsonEncode({"action": "START", "target": req, "uid": user.uid}));
                              client.publishMessage("dispenser/cmd", MqttQos.atMostOnce, b.payload!);
                              _amountController.clear();
                            }
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, elevation: 5),
                          child: isProcessing ? const CircularProgressIndicator(color: Colors.white) : const Text("MULAI ISI AIR", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        )),
                      ]),
                    ),
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }
}

// --- PROFILE CONFIG PAGE ---
class ProfileConfigPage extends StatefulWidget {
  const ProfileConfigPage({super.key});
  @override
  State<ProfileConfigPage> createState() => _ProfileConfigPageState();
}

class _ProfileConfigPageState extends State<ProfileConfigPage> {
  
  Future<bool> _reauthenticate(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    String? password = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, top: 20, left: 20, right: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Konfirmasi Keamanan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text("Masukkan password Anda saat ini."),
          const SizedBox(height: 20),
          TextField(obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: "Password"), onSubmitted: (val) => Navigator.pop(context, val)),
        ]),
      ),
    );
    if (password == null || password.isEmpty) return false;
    try {
      await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: password));
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password salah!"), backgroundColor: Colors.red));
      return false;
    }
  }

  Future<void> _sendComplaintEmail(String issue) async {
    // Ganti dengan kredensial email Admin
    String username = 'xxx@gmail.com'; 
    String password = 'xxxx xxxx xxxx xxxx'; 
    final smtpServer = gmail(username, password);
    final user = FirebaseAuth.instance.currentUser;
    
    final message = Message()
      ..from = Address(username, 'Smart Dispenser App')
      //Ganti dengan email tujuan Admin
      ..recipients.add('xxx@gmail.com') 
      ..subject = 'MASUKAN USER: ${user?.email ?? "Unknown"}'
      ..text = 'Pesan dari User:\n\n$issue\n\n- Dikirim dari Aplikasi Dispenser';
    
    try {
      await send(message, smtpServer);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Laporan terkirim ke Admin!"), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal kirim: $e"), backgroundColor: Colors.red));
    }
  }

  void _showComplaintDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Kirim Masukan"),
      content: TextField(
        controller: ctrl,
        maxLines: 4,
        decoration: const InputDecoration(hintText: "Tulis masalah atau saran Anda di sini...", border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BATAL")),
        ElevatedButton(onPressed: () async {
          if (ctrl.text.isNotEmpty) {
            Navigator.pop(ctx);
            await _sendComplaintEmail(ctrl.text);
          }
        }, child: const Text("KIRIM")),
      ],
    ));
  }
  // ----------------------------------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text("Pengaturan Akun"), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.person, color: Colors.blue),
            title: const Text("Ganti Username"),
            onTap: () {
              final ctrl = TextEditingController();
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text("Username Baru"),
                content: TextField(controller: ctrl),
                actions: [TextButton(onPressed: () async {
                  if (ctrl.text.isNotEmpty && await _reauthenticate(context)) {
                    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'username': ctrl.text});
                    if (mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Username diperbarui!"), backgroundColor: Colors.green)); }
                  }
                }, child: const Text("SIMPAN"))],
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.key, color: Colors.orange),
            title: const Text("Ganti Password"),
            onTap: () async {
              if (await _reauthenticate(context)) {
                final ctrl = TextEditingController();
                if (!mounted) return;
                showDialog(context: context, builder: (ctx) => AlertDialog(
                  title: const Text("Password Baru"),
                  content: TextField(controller: ctrl, obscureText: true),
                  actions: [TextButton(onPressed: () async {
                    if (ctrl.text.length >= 6) {
                      await user.updatePassword(ctrl.text);
                      if (mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password diperbarui!"), backgroundColor: Colors.green)); }
                    }
                  }, child: const Text("UPDATE"))],
                ));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.feedback, color: Colors.purple),
            title: const Text("Kirim Masukan"),
            onTap: () => _showComplaintDialog(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red), 
            title: const Text("Hapus Akun Permanen", style: TextStyle(color: Colors.red)), 
            onTap: () async {
              if (await _reauthenticate(context)) {
                await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
                await user.delete();
                if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
              }
            }
          ),
          ListTile(
            leading: const Icon(Icons.logout), 
            title: const Text("Logout"), 
            onTap: () async { 
              await FirebaseAuth.instance.signOut(); 
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AuthGate()),
                  (route) => false,
                );
              }
            }
          ),
        ],
      ),
    );
  }
}