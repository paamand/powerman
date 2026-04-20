import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'game/game_screen.dart';
import 'lan/lan_network.dart';

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

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  bool _lanBusy = false;
  String? _lanStatus;
  Timer? _discoveryTimer;
  InternetAddress? _discoveredHost;
  bool _discovering = false;

  @override
  void initState() {
    super.initState();
    _startDiscoveryLoop();
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    super.dispose();
  }

  void _startDiscoveryLoop() {
    _runDiscoveryScan();
    _discoveryTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _runDiscoveryScan(),
    );
  }

  Future<void> _runDiscoveryScan() async {
    if (_discovering || _lanBusy) return;
    _discovering = true;
    try {
      final host = await discoverLanHost(
        timeout: const Duration(milliseconds: 1500),
      );
      if (!mounted) return;
      if (host != _discoveredHost) {
        setState(() {
          _discoveredHost = host;
        });
      }
    } catch (_) {
      // Ignore discovery errors.
    } finally {
      _discovering = false;
    }
  }

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
              'Vibe-coded by Paamand',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 48),
            _MenuButton(label: '2 Players', onTap: () => _startGame(2)),
            const SizedBox(height: 16),
            _MenuButton(label: '4 Players', onTap: () => _startGame(4)),
            const SizedBox(height: 16),
            _MenuButton(
              label: _lanBusy ? '...' : (_discoveredHost != null ? 'JOIN' : 'LAN'),
              onTap: _lanBusy ? () {} : _onLanTap,
            ),
            if (_lanStatus != null) ...[
              const SizedBox(height: 8),
              Text(
                _lanStatus!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
              ),
            ],
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
                  Text(
                    'HOW TO PLAY',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'DRAG  →  Move your powerman',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text('TAP   →  Drop bomb', style: TextStyle(fontSize: 12)),
                  Text(
                    'HOLD  →  Trigger super weapon',
                    style: TextStyle(fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Collect crates for power-ups!',
                    style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startGame(int numPlayers) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GameScreen(numPlayers: numPlayers)),
    );
  }

  void _onLanTap() {
    if (_discoveredHost != null) {
      _joinLanGame(_discoveredHost!);
    } else {
      _hostLanGame();
    }
  }

  Future<void> _hostLanGame() async {
    _discoveryTimer?.cancel();
    setState(() {
      _lanBusy = true;
      _lanStatus = 'Hosting LAN game...';
    });

    try {
      final host = await LanHostServer.start(localPlayerId: 0);
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(
            numPlayers: 4,
            lanHost: host,
            localPlayerId: 0,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lanStatus = 'LAN failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _lanBusy = false;
        });
        _startDiscoveryLoop();
      }
    }
  }

  Future<void> _joinLanGame(InternetAddress hostAddress) async {
    _discoveryTimer?.cancel();
    setState(() {
      _lanBusy = true;
      _lanStatus = 'Joining LAN game...';
    });

    try {
      final client = await LanClientConnection.connect(hostAddress);
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(
            numPlayers: 4,
            lanClient: client,
            localPlayerId: client.localPlayerId,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lanStatus = 'Host unavailable. Try again.';
        _discoveredHost = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _lanBusy = false;
        });
        _startDiscoveryLoop();
      }
    }
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
