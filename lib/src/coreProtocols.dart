import 'dart:developer';
import 'package:locsand/src/tasks/connection.dart';

UdpPeerSearch? search; // variable that can hold an object

Future<void> coreProtocols() async { // background functions run (UDP serch and request)
  search = UdpPeerSearch(
    deviceId: 'device-1',
    deviceName: 'test',
    port: 0,
    onPeerFound: (peer) {
      log("Found peer: ${peer.name} at ${peer.ip}");
      // Save all devices in network. If new add in sessionData, if alredy in update las time active if it is not active for 30 secend delete from array
    },
  );

  search!.start();
}