import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter NFC APDU Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final availability = await FlutterNfcKit.nfcAvailability;
      setState(() {
        nfcAvailability = availability;
      });
    });
  }

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

      // 1️⃣ Read NDEF records if available
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
            if (text != null) buffer.writeln("Payload (text): $text");
            buffer.writeln("");
          }
        }
      }

      // 2️⃣ APDU mode for ISO 7816 / smart cards
      if (tag.type == NFCTagType.iso7816) {
        buffer.writeln("===== APDU EXPLORER =====");
        // Example APDU commands (you can replace with vendor commands)
        final List<Map<String, dynamic>> apduCommands = [
          {
            "title": "Select Master File (MF)",
            "cmd": Uint8List.fromList([0x00, 0xA4, 0x00, 0x00, 0x00]),
          },
          {
            "title": "Select by AID (NFC Forum / NDEF)",
            "cmd": Uint8List.fromList([
              0x00,
              0xA4,
              0x04,
              0x00,
              0x07,
              0xD2,
              0x76,
              0x00,
              0x00,
              0x85,
              0x01,
              0x01,
            ]),
          },
          {
            "title": "Get Processing Options (EMV style)",
            "cmd": Uint8List.fromList([
              0x80,
              0xA8,
              0x00,
              0x00,
              0x02,
              0x83,
              0x00,
              0x00,
            ]),
          },
          {
            "title": "Get Data (Common EMV Tag)",
            "cmd": Uint8List.fromList([0x00, 0xCA, 0x9F, 0x7F, 0x00]),
          },
          {
            "title": "Read Binary (offset 0)",
            "cmd": Uint8List.fromList([0x00, 0xB0, 0x00, 0x00, 0x10]),
          },
          {
            "title": "Read Binary (offset 16)",
            "cmd": Uint8List.fromList([0x00, 0xB0, 0x00, 0x10, 0x10]),
          },
          {
            "title": "Read Binary (offset 32)",
            "cmd": Uint8List.fromList([0x00, 0xB0, 0x00, 0x20, 0x10]),
          },
          {
            "title": "Get Challenge (Random number)",
            "cmd": Uint8List.fromList([0x00, 0x84, 0x00, 0x00, 0x08]),
          },
          {
            "title": "Get ATR / Historical Bytes",
            "cmd": Uint8List.fromList([0x00, 0xCA, 0x01, 0x00, 0x00]),
          },
          {
            "title": "Get UID (NXP style)",
            "cmd": Uint8List.fromList([0xFF, 0xCA, 0x00, 0x00, 0x00]),
          },
        ];

        for (int i = 0; i < apduCommands.length; i++) {
          final title = apduCommands[i]["title"];
          final Uint8List cmd = apduCommands[i]["cmd"];

          try {
            final resp = await FlutterNfcKit.transceive(cmd);

            buffer.writeln("==== $title ====");
            buffer.writeln("Command : ${toHex(cmd)}");
            buffer.writeln("Response: ${toHex(resp)}");

            final text = tryDecodeText(resp);
            if (text != null) buffer.writeln("Text    : $text");

            buffer.writeln("");
          } catch (e) {
            buffer.writeln("==== $title FAILED ====");
            buffer.writeln("Error: $e\n");
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("NFC APDU Debug Reader")),
      body: switch (nfcAvailability) {
        null => const Center(child: CircularProgressIndicator.adaptive()),
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
                  child: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        result,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _ => const Center(
          child: Text("No NFC on this device!", style: TextStyle(fontSize: 13)),
        ),
      },
    );
  }
}
