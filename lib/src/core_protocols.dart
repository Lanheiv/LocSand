import 'dart:developer';
import 'package:locsand/src/tasks/connection.dart';
import 'package:locsand/data/session_data.dart';

UdpPeerSearch? search; // variable that can hold an object

Future<void> coreProtocols() async { // background functions run (UDP serch and request)
  search = UdpPeerSearch(
    deviceId: 'device-1',
    deviceName: 'test',
    port: 0,
    onPeerFound: (peer) {
      log("Found peer: ${peer.name} at ${peer.ip}");
      
      SessionData().addOrUpdatePeer(peer);
    },
  );

  search!.start();
}