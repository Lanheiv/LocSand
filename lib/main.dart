import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:locsand/src/tasks/connection.dart';

UdpPeerSearch? search; // variable that can hold an object

Future<void> coreProtocols() async { // background functions run (UDP serch and request)
  search = UdpPeerSearch(
    deviceId: 'device-1',
    deviceName: 'test',
    port: 0,
    onPeerFound: (peer) {
      log("Found peer: ${peer.name} at ${peer.ip}");
    },
  );

  search!.start();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await coreProtocols();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home page',
      // home: HomePage(),
    );
  }
}