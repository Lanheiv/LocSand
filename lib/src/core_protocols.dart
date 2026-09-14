import 'dart:developer';
import 'dart:io';
import 'package:locsand/src/tasks/udp_connection.dart';
import 'package:locsand/src/tasks/tcp_server.dart';
import 'package:locsand/src/data/session_data.dart';
import 'package:locsand/src/helpers/load_config.dart';

UdpPeerSearch? search; // variable that can hold an object
TcpPeerServer? tcpServer;

Future<void> coreProtocols() async { // background functions run (UDP serch and request)
  final config = await loadConfig();

  final node = config['node'] as Map<String, dynamic>;
  final network = config['network'] as Map<String, dynamic>;
  final discovery = config['discovery'] as Map<String, dynamic>;

  final nodeName = node['name'] as String;
  final nodeID = node['id'] as String;
  final tcpPort = network['tcp_port'] as int;
  final udpPort = network['udp_port'] as int;
  final broadcastAddress = InternetAddress((discovery['broadcast_address'] as String));
  final broadcastEnabled = discovery['enabled'] as bool;

  SessionData().userId = nodeID;
  SessionData().userName = nodeName;
  SessionData().userOnlineTime = DateTime.now();

  tcpServer = TcpPeerServer(port: tcpPort);
  try {
    await tcpServer!.start();
  } catch (e) {
    log("TCP server errore: $e");
  }

  search = UdpPeerSearch(
    deviceId: nodeID,
    deviceName: nodeName,
    tcpPort: tcpPort,
    udpPort: udpPort,
    broadcastAddress: broadcastAddress,
    broadcastEnabled: broadcastEnabled,
    onPeerFound: (peer) {
      log("Found peer: ${peer.name} at ${peer.ip}");
      
      SessionData().addOrUpdatePeer(peer);
    },
  );

  try {
    await search!.start();
  } catch (e) {
    log("UDP discovery errore: $e");
  }
}