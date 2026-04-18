import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const PowermanApp());
}

class PowermanApp extends StatelessWidget {
  const PowermanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Powerman',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
      ),
      home: const MenuScreen(),
    );
  }
}

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'POWERMAN',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'iPad Multiplayer Battle',
              style: TextStyle(fontSize: 14, color: Color(0xFF666666), letterSpacing: 2),
            ),
            const SizedBox(height: 48),
            _MenuButton(label: '2 Players', onTap: () => _startGame(context, 2)),
            const SizedBox(height: 16),
            _MenuButton(label: '4 Players', onTap: () => _startGame(context, 4)),
            const SizedBox(height: 48),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFAAAAAA), width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HOW TO PLAY',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 2)),
                  SizedBox(height: 8),
                  Text('DRAG  →  Move your powerman', style: TextStyle(fontSize: 12)),
                  Text('TAP   →  Drop bomb', style: TextStyle(fontSize: 12)),
                  Text('HOLD  →  Trigger super weapon', style: TextStyle(fontSize: 12)),
                  SizedBox(height: 4),
                  Text('Collect crates for power-ups!',
                      style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startGame(BuildContext context, int numPlayers) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GameScreen(numPlayers: numPlayers)),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MenuButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF1A1A1A), width: 2.5),
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
