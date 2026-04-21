import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const int kLanDiscoveryPort = 43111;
const int kLanGamePort = 43112;
const String _kDiscoverToken = 'POWERMAN_DISCOVER_V1';
const String _kMulticastGroup = '239.255.77.77';

class _AndroidLanBridge {
  static const MethodChannel _channel = MethodChannel('powerman/lan');

  static Future<void> acquireMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('acquireMulticastLock');
    } catch (_) {
      // Best effort: LAN can still work on many networks without the lock.
    }
  }

  static Future<void> releaseMulticastLock() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } catch (_) {
      // Ignore release failures.
    }
  }
}

class LanBootstrapResult {
  final bool isHost;
  final int localPlayerId;
  final LanHostServer? hostServer;
  final LanClientConnection? clientConnection;

  const LanBootstrapResult._({
    required this.isHost,
    required this.localPlayerId,
    this.hostServer,
    this.clientConnection,
  });

  factory LanBootstrapResult.host({required LanHostServer hostServer}) {
    return LanBootstrapResult._(
      isHost: true,
      localPlayerId: hostServer.localPlayerId,
      hostServer: hostServer,
    );
  }

  factory LanBootstrapResult.client({
    required LanClientConnection clientConnection,
  }) {
    return LanBootstrapResult._(
      isHost: false,
      localPlayerId: clientConnection.localPlayerId,
      clientConnection: clientConnection,
    );
  }
}

Future<LanBootstrapResult> joinOrHostLanGame() async {
  final discoveredHost = await discoverLanHost(
    timeout: const Duration(seconds: 3),
  );
  if (discoveredHost != null) {
    try {
      final client = await LanClientConnection.connect(discoveredHost);
      return LanBootstrapResult.client(clientConnection: client);
    } catch (_) {
      // Fallback to hosting if the discovered host is no longer available.
    }
  }

  final host = await LanHostServer.start(localPlayerId: 0);
  return LanBootstrapResult.host(hostServer: host);
}

Future<InternetAddress?> discoverLanHost({required Duration timeout}) async {
  RawDatagramSocket? socket;
  Timer? probeTimer;
  try {
    // Bind to the discovery port so we receive host beacon broadcasts.
    socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kLanDiscoveryPort,
      reuseAddress: true,
      reusePort: true,
    );
    socket.broadcastEnabled = true;
    // Join multicast group to receive host beacons sent there.
    try {
      socket.joinMulticast(InternetAddress(_kMulticastGroup));
    } catch (_) {}
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        try {
          socket.joinMulticast(InternetAddress(_kMulticastGroup), iface);
        } catch (_) {}
      }
    } catch (_) {}

    // Collect local IPs to filter out self-discovery.
    final localAddresses = await _collectLocalAddresses();

    final completer = Completer<InternetAddress?>();
    late StreamSubscription<RawSocketEvent> sub;
    sub = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram;
        while ((datagram = socket!.receive()) != null) {
          // Ignore packets from ourselves.
          if (localAddresses.contains(datagram!.address.address)) continue;
          String text;
          try {
            text = utf8.decode(datagram.data);
          } catch (_) {
            continue;
          }
          dynamic json;
          try {
            json = jsonDecode(text);
          } catch (_) {
            continue;
          }
          if (json is Map<String, dynamic> && json['t'] == 'host') {
            if (!completer.isCompleted) completer.complete(datagram.address);
            return;
          }
        }
      }
    });

    // Also send active probes (belt-and-suspenders: works when host can
    // receive our broadcast even if we can't receive theirs).
    final broadcastTargets = await _collectBroadcastTargets();
    final probe = utf8.encode(_kDiscoverToken);

    void sendProbes() {
      if (completer.isCompleted) return;
      for (final target in broadcastTargets) {
        try {
          socket!.send(probe, target, kLanDiscoveryPort);
        } catch (_) {}
      }
    }

    sendProbes();
    probeTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => sendProbes(),
    );

    final host = await completer.future.timeout(timeout, onTimeout: () => null);
    await sub.cancel();
    return host;
  } finally {
    probeTimer?.cancel();
    socket?.close();
  }
}

Future<InternetAddress?> discoverLanHostWithTcpFallback({
  required Duration udpTimeout,
  required Duration tcpScanTimeout,
}) async {
  final viaUdp = await discoverLanHost(timeout: udpTimeout);
  if (viaUdp != null) return viaUdp;
  return _scanForHostByTcp(timeout: tcpScanTimeout);
}

/// Fast /24 TCP probe fallback for environments where UDP discovery is blocked.
Future<InternetAddress?> _scanForHostByTcp({required Duration timeout}) async {
  final localAddresses = await _collectLocalAddresses();
  final prefixes = <String>{};
  for (final addr in localAddresses) {
    if (addr.startsWith('127.')) continue;
    final parts = addr.split('.');
    if (parts.length == 4) {
      prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
    }
  }

  if (prefixes.isEmpty) return null;

  final candidates = <String>[];
  for (final prefix in prefixes) {
    for (int host = 1; host <= 254; host++) {
      final ip = '$prefix.$host';
      if (localAddresses.contains(ip)) continue;
      candidates.add(ip);
    }
  }

  final deadline = DateTime.now().add(timeout);
  const batchSize = 32;
  for (int i = 0; i < candidates.length; i += batchSize) {
    if (DateTime.now().isAfter(deadline)) return null;
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) return null;

    final batch = candidates.skip(i).take(batchSize);
    final perProbeTimeout =
        remaining < const Duration(milliseconds: 150)
            ? remaining
            : const Duration(milliseconds: 150);

    final probes = batch.map(
      (ip) => _probeHostTcpPort(ip, timeout: perProbeTimeout),
    );
    final results = await Future.wait(probes);
    for (final host in results) {
      if (host != null) return host;
    }
  }

  return null;
}

Future<InternetAddress?> _probeHostTcpPort(
  String ip, {
  required Duration timeout,
}) async {
  if (timeout <= Duration.zero) return null;
  try {
    final socket = await Socket.connect(
      ip,
      kLanGamePort,
      timeout: timeout,
    );
    socket.destroy();
    return InternetAddress(ip);
  } catch (_) {
    return null;
  }
}

/// Collect all local IPv4 addresses (used to filter self-discovery).
Future<Set<String>> _collectLocalAddresses() async {
  final addrs = <String>{'127.0.0.1'};
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        addrs.add(addr.address);
      }
    }
  } catch (_) {}
  return addrs;
}

/// Build the list of addresses to send discovery probes / beacons to.
/// Includes the multicast group and subnet-directed broadcast addresses
/// derived from every active WiFi/ethernet interface.
Future<List<InternetAddress>> _collectBroadcastTargets() async {
  final targets = <InternetAddress>[
    InternetAddress(_kMulticastGroup),
    InternetAddress('255.255.255.255'),
  ];
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        // Derive a /24 subnet broadcast (covers most home/office networks).
        final parts = addr.address.split('.');
        if (parts.length == 4) {
          final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          final target = InternetAddress(subnetBroadcast);
          if (!targets.any((t) => t.address == target.address)) {
            targets.add(target);
          }
        }
      }
    }
  } catch (_) {
    // Fall back to limited broadcast only.
  }
  return targets;
}

class LanHostServer {
  final int localPlayerId;
  final Set<int> connectedPlayerIds = <int>{};

  void Function(int playerId)? onPlayerJoined;
  void Function(int playerId)? onPlayerLeft;
  void Function(int playerId, Offset direction)? onMove;
  void Function(int playerId)? onBomb;
  void Function(int playerId)? onSuper;
  Map<String, dynamic> Function()? snapshotProvider;

  final ServerSocket _serverSocket;
  final RawDatagramSocket _discoverySocket;
  final Map<Socket, int> _socketToPlayer = <Socket, int>{};
  final List<StreamSubscription> _socketSubscriptions = <StreamSubscription>[];
  List<InternetAddress> _broadcastTargets = const [];
  Timer? _beaconTimer;
  bool _closed = false;

  LanHostServer._(
    this._serverSocket,
    this._discoverySocket, {
    required this.localPlayerId,
  }) {
    connectedPlayerIds.add(localPlayerId);
    _listenForDiscovery();
    _listenForClients();
    _startBeacon();
  }

  static Future<LanHostServer> start({
    required int localPlayerId,
  }) async {
    await _AndroidLanBridge.acquireMulticastLock();
    final server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      kLanGamePort,
      shared: true,
    );
    final discovery = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kLanDiscoveryPort,
      reuseAddress: true,
      reusePort: true,
    );
    discovery.broadcastEnabled = true;
    // Join multicast on every available interface for reliable reception.
    try {
      discovery.joinMulticast(InternetAddress(_kMulticastGroup));
    } catch (_) {}
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        try {
          discovery.joinMulticast(
            InternetAddress(_kMulticastGroup),
            iface,
          );
        } catch (_) {}
      }
    } catch (_) {}
    return LanHostServer._(
      server,
      discovery,
      localPlayerId: localPlayerId,
    );
  }

  /// Periodically broadcast a host beacon so clients that cannot send
  /// broadcasts (common on physical iOS) can still discover us passively.
  void _startBeacon() {
    _collectBroadcastTargets().then((targets) {
      _broadcastTargets = targets;
      if (_closed) return;
      // Send first beacon immediately.
      _sendBeacon();
      _beaconTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _sendBeacon(),
      );
    });
  }

  void _sendBeacon() {
    if (_closed) return;
    final payload = utf8.encode(
      jsonEncode({'t': 'host', 'port': kLanGamePort}),
    );
    for (final target in _broadcastTargets) {
      try {
        _discoverySocket.send(payload, target, kLanDiscoveryPort);
      } catch (_) {}
    }
  }

  void _listenForDiscovery() {
    _discoverySocket.listen((event) {
      if (_closed) return;
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = _discoverySocket.receive()) != null) {
        String text;
        try {
          text = utf8.decode(datagram!.data);
        } catch (_) {
          continue;
        }
        if (text != _kDiscoverToken) continue;
        // Reply directly to the client that probed us.
        final reply = jsonEncode({'t': 'host', 'port': kLanGamePort});
        _discoverySocket.send(
          utf8.encode(reply),
          datagram.address,
          datagram.port,
        );
      }
    });
  }

  void _listenForClients() {
    _serverSocket.listen((socket) {
      if (_closed) {
        socket.destroy();
        return;
      }
      final sub = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _handleClientLine(socket, line),
            onDone: () => _removeSocket(socket),
            onError: (_) => _removeSocket(socket),
            cancelOnError: true,
          );
      _socketSubscriptions.add(sub);
    });
  }

  void _handleClientLine(Socket socket, String line) {
    if (_closed) return;

    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return;
    }

    final existingPlayer = _socketToPlayer[socket];
    final type = msg['t'];

    if (type == 'join') {
      if (existingPlayer != null) return;
      final assigned = _assignFreePlayerSlot();
      if (assigned == null) {
        socket.writeln(jsonEncode({'t': 'join_denied'}));
        socket.flush();
        socket.destroy();
        return;
      }
      _socketToPlayer[socket] = assigned;
      connectedPlayerIds.add(assigned);
      socket.writeln(
        jsonEncode({
          't': 'join_ack',
          'playerId': assigned,
          'state': snapshotProvider?.call(),
        }),
      );
      socket.flush();
      onPlayerJoined?.call(assigned);
      return;
    }

    if (existingPlayer == null) return;

    if (type == 'input') {
      final dx = (msg['dx'] as num?)?.toDouble() ?? 0;
      final dy = (msg['dy'] as num?)?.toDouble() ?? 0;
      onMove?.call(existingPlayer, Offset(dx, dy));
      return;
    }

    if (type == 'bomb') {
      onBomb?.call(existingPlayer);
      return;
    }

    if (type == 'super') {
      onSuper?.call(existingPlayer);
      return;
    }
  }

  int? _assignFreePlayerSlot() {
    for (int i = 0; i < 4; i++) {
      if (!connectedPlayerIds.contains(i)) return i;
    }
    return null;
  }

  void _removeSocket(Socket socket) {
    final playerId = _socketToPlayer.remove(socket);
    if (playerId != null) {
      connectedPlayerIds.remove(playerId);
      onPlayerLeft?.call(playerId);
    }
    socket.destroy();
  }

  void broadcastSnapshot(Map<String, dynamic> state) {
    if (_closed) return;
    final payload = '${jsonEncode({'t': 'snapshot', 'state': state})}\n';
    for (final socket in _socketToPlayer.keys.toList()) {
      try {
        socket.write(payload);
      } catch (_) {
        _removeSocket(socket);
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _beaconTimer?.cancel();
    for (final sub in _socketSubscriptions) {
      await sub.cancel();
    }
    for (final socket in _socketToPlayer.keys.toList()) {
      socket.destroy();
    }
    _socketToPlayer.clear();
    connectedPlayerIds.clear();
    await _serverSocket.close();
    _discoverySocket.close();
    await _AndroidLanBridge.releaseMulticastLock();
  }
}

class LanClientConnection {
  final Socket _socket;
  final int localPlayerId;
  final Map<String, dynamic>? initialState;
  final StreamController<Map<String, dynamic>> _snapshotController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<void> _disconnectController =
      StreamController<void>.broadcast();
  StreamSubscription<String>? _lineSub;
  bool _closed = false;

  LanClientConnection._(
    this._socket, {
    required this.localPlayerId,
    required this.initialState,
  });

  Stream<Map<String, dynamic>> get snapshots => _snapshotController.stream;
  Stream<void> get disconnected => _disconnectController.stream;

  static Future<LanClientConnection> connect(
    InternetAddress hostAddress,
  ) async {
    final socket = await Socket.connect(
      hostAddress,
      kLanGamePort,
      timeout: const Duration(seconds: 3),
    );
    final joinCompleter = Completer<Map<String, dynamic>>();
    final snapshotBuffer = <Map<String, dynamic>>[];
    final lineStream = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    bool joined = false;
    late LanClientConnection client;

    final sub = lineStream.listen(
      (line) {
        Map<String, dynamic> msg;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map<String, dynamic>) return;
          msg = decoded;
        } catch (_) {
          return;
        }

        final type = msg['t'];
        if (!joined) {
          if (type == 'join_ack' && !joinCompleter.isCompleted) {
            joinCompleter.complete(msg);
          } else if (type == 'join_denied' && !joinCompleter.isCompleted) {
            joinCompleter.completeError(StateError('LAN host is full'));
          }
          if (type == 'snapshot') {
            final state = msg['state'];
            if (state is Map<String, dynamic>) {
              snapshotBuffer.add(state);
            }
          }
          return;
        }

        if (type == 'snapshot') {
          final state = msg['state'];
          if (state is Map<String, dynamic>) {
            client._snapshotController.add(state);
          }
        }
      },
      onError: (err) {
        if (!joinCompleter.isCompleted) {
          joinCompleter.completeError(err);
          return;
        }
        client._disconnectController.add(null);
      },
      onDone: () {
        if (!joinCompleter.isCompleted) {
          joinCompleter.completeError(
            StateError('Disconnected before join ack'),
          );
          return;
        }
        client._disconnectController.add(null);
      },
      cancelOnError: true,
    );

    socket.writeln(jsonEncode({'t': 'join'}));
    final join = await joinCompleter.future.timeout(const Duration(seconds: 3));

    client = LanClientConnection._(
      socket,
      localPlayerId: (join['playerId'] as num).toInt(),
      initialState: join['state'] as Map<String, dynamic>?,
    );
    client._lineSub = sub;
    joined = true;

    for (final pending in snapshotBuffer) {
      client._snapshotController.add(pending);
    }

    return client;
  }

  void sendMove(Offset direction) {
    _send({'t': 'input', 'dx': direction.dx, 'dy': direction.dy});
  }

  void sendBomb() {
    _send({'t': 'bomb'});
  }

  void sendSuper() {
    _send({'t': 'super'});
  }

  void _send(Map<String, dynamic> message) {
    if (_closed) return;
    _socket.writeln(jsonEncode(message));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _lineSub?.cancel();
    await _snapshotController.close();
    await _disconnectController.close();
    _socket.destroy();
  }
}
