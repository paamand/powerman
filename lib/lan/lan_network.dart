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
    timeout: const Duration(milliseconds: 1200),
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
  try {
    socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: true,
    );
    socket.broadcastEnabled = true;

    final completer = Completer<InternetAddress?>();
    late StreamSubscription<RawSocketEvent> sub;
    sub = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket!.receive();
        if (datagram == null) return;
        String text;
        try {
          text = utf8.decode(datagram.data);
        } catch (_) {
          return;
        }
        dynamic json;
        try {
          json = jsonDecode(text);
        } catch (_) {
          return;
        }
        if (json is Map<String, dynamic> && json['t'] == 'host') {
          if (!completer.isCompleted) completer.complete(datagram.address);
        }
      }
    });

    // Send to multicast group (cross-platform) and broadcast (fallback)
    socket.send(
      utf8.encode(_kDiscoverToken),
      InternetAddress(_kMulticastGroup),
      kLanDiscoveryPort,
    );
    socket.send(
      utf8.encode(_kDiscoverToken),
      InternetAddress('255.255.255.255'),
      kLanDiscoveryPort,
    );

    final host = await completer.future.timeout(timeout, onTimeout: () => null);
    await sub.cancel();
    return host;
  } finally {
    socket?.close();
  }
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
  bool _closed = false;

  LanHostServer._(
    this._serverSocket,
    this._discoverySocket, {
    required this.localPlayerId,
  }) {
    connectedPlayerIds.add(localPlayerId);
    _listenForDiscovery();
    _listenForClients();
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
    try {
      discovery.joinMulticast(InternetAddress(_kMulticastGroup));
    } catch (_) {
      // Best effort: multicast join may fail on some networks.
    }
    return LanHostServer._(
      server,
      discovery,
      localPlayerId: localPlayerId,
    );
  }

  void _listenForDiscovery() {
    _discoverySocket.listen((event) {
      if (_closed) return;
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = _discoverySocket.receive()) != null) {
        final text = utf8.decode(datagram!.data);
        if (text != _kDiscoverToken) continue;
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
