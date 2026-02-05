import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const NfcDebugScreen(),
    );
  }
}

class NfcDebugScreen extends StatefulWidget {
  const NfcDebugScreen({super.key});

  @override
  State createState() => _NfcDebugScreenState();
}

class _NfcDebugScreenState extends State<NfcDebugScreen> {
  NFCAvailability? nfcAvailability;

  String result = "Press the button and scan NFC tag";

  Future<void> startReading() async {
    setState(() => result = "Waiting for NFC tag...");

    try {
      final NFCTag tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 20),
      );
      final buffer = StringBuffer();

      buffer.writeln("===== TAG INFO =====");
      buffer.writeln("ID: ${tag.id}");
      buffer.writeln("Type: ${tag.type}");
      buffer.writeln("Standard: ${tag.standard}");
      buffer.writeln("ATQA: ${tag.atqa}");
      buffer.writeln("SAK: ${tag.sak}");
      buffer.writeln("Historical Bytes: ${tag.historicalBytes}");
      buffer.writeln("Protocol Info: ${tag.protocolInfo}");
      buffer.writeln("NDEF Available: ${tag.ndefAvailable}");
      buffer.writeln("");

      if (tag.ndefAvailable == true) {
        final records = await FlutterNfcKit.readNDEFRecords();

        if (records.isEmpty) {
          buffer.writeln("No NDEF records found.");
        } else {
          buffer.writeln("===== NDEF RECORDS (${records.length}) =====");

          for (int i = 0; i < records.length; i++) {
            final record = records[i];

            final payload = record.payload ?? Uint8List(0);
            final type = record.type ?? Uint8List(0);
            final id = record.id ?? Uint8List(0);

            buffer.writeln("---- Record ${i + 1} ----");
            buffer.writeln("Type: ${utf8.decode(type, allowMalformed: true)}");
            buffer.writeln("ID: ${utf8.decode(id, allowMalformed: true)}");
            buffer.writeln("Payload (raw): $payload");
            buffer.writeln("Payload (hex): ${toHex(payload)}");

            final text = tryDecodeText(payload);
            if (text != null) {
              buffer.writeln("Payload (text): $text");
            }

            buffer.writeln("");
          }
        }
      }

      setState(() => result = buffer.toString());
    } catch (e) {
      setState(() => result = "Error: $e");
    } finally {
      await FlutterNfcKit.finish();
    }
  }

  String toHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(" ");
  }

  String? tryDecodeText(Uint8List payload) {
    try {
      if (payload.isEmpty) return null;

      final int langLength = payload[0] & 0x3F;
      return utf8.decode(payload.sublist(1 + langLength), allowMalformed: true);
    } catch (_) {
      try {
        return utf8.decode(payload, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      FlutterNfcKit.nfcAvailability.then(
        (value) => setState(() {
          nfcAvailability = value;
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("NFC Debug Reader")),
      body: switch (nfcAvailability) {
        null => Center(child: CircularProgressIndicator.adaptive()),
        NFCAvailability.available => Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: startReading,
                  child: const Text("Start NFC Reading"),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      result,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _ => Center(
          child: Text(
            "No NFC In this device!",
            style: const TextStyle(fontSize: 13),
          ),
        ),
      },
    );
  }
}
