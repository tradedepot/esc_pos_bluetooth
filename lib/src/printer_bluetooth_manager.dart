/*
 * esc_pos_bluetooth
 * Created by Andrey Ushakov
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:flutter_scan_bluetooth/flutter_scan_bluetooth.dart';
import 'package:rxdart/rxdart.dart';
// import 'package:flutter_bluetooth_basic/flutter_bluetooth_basic.dart';
import './enums.dart';

/// Bluetooth printer
// class PrinterBluetooth {
//   PrinterBluetooth(this._device);
//   final BluetoothDevice _device;

//   String? get name => _device.name;
//   String? get address => _device.address;
//   int? get type => _device.type;
// }

/// Printer Bluetooth Manager
class PrinterBluetoothManager {
  // final FlutterBluePlus _bluetoothManager = FlutterBluePlus;
  bool _isPrinting = false;
  bool _isConnected = false;
  StreamSubscription? _scanResultsSubscription;
  StreamSubscription? _isScanningSubscription;
  BluetoothDevice? _selectedPrinter;

  final BehaviorSubject<bool> _isScanning = BehaviorSubject.seeded(false);
  Stream<bool> get isScanningStream => _isScanning.stream;

  final BehaviorSubject<List<ScanResult>> _scanResults =
      BehaviorSubject.seeded([]);
  Stream<List<ScanResult>> get scanResults => _scanResults.stream;

  Future _runDelayed(int seconds) {
    return Future<dynamic>.delayed(Duration(seconds: seconds));
  }

  void startScan(Duration timeout) async {
    _scanResults.add(<ScanResult>[]);

    FlutterBluePlus.startScan(timeout: timeout);

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((devices) {
      _scanResults.add(devices.map((d) => d).toList());
    });

    _isScanningSubscription =
        FlutterBluePlus.isScanning.listen((isScanningCurrent) async {
      // If isScanning value changed (scan just stopped)
      if (_isScanning.value! && !isScanningCurrent) {
        _scanResultsSubscription!.cancel();
        _isScanningSubscription!.cancel();
      }
      _isScanning.add(isScanningCurrent);
    });
  }

  void stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  void selectPrinter(BluetoothDevice printer) {
    _selectedPrinter = printer;
  }

  Future<PosPrintResult> writeBytes(
    List<int> bytes, {
    int chunkSizeBytes = 20,
    int queueSleepTimeMs = 20,
  }) async {
    final Completer<PosPrintResult> completer = Completer();

    const int timeout = 5;
    if (_selectedPrinter == null) {
      return Future<PosPrintResult>.value(PosPrintResult.printerNotSelected);
    } else if (_isScanning.value!) {
      return Future<PosPrintResult>.value(PosPrintResult.scanInProgress);
    } else if (_isPrinting) {
      return Future<PosPrintResult>.value(PosPrintResult.printInProgress);
    }

    _isPrinting = true;

    // We have to rescan before connecting, otherwise we can connect only once
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 1));
    await FlutterBluePlus.stopScan();

    // Connect
    await _selectedPrinter!.connect();
    final services = await _selectedPrinter?.discoverServices();

    // await FlutterBluePlus.connect(_selectedPrinter!);

    // Subscribe to the events
    FlutterBluePlus.adapterState.listen((state) async {
      switch (state) {
        case BluetoothAdapterState.on:
          // To avoid double call
          if (!_isConnected) {
            final len = bytes.length;
            List<List<int>> chunks = [];
            for (var i = 0; i < len; i += chunkSizeBytes) {
              var end = (i + chunkSizeBytes < len) ? i + chunkSizeBytes : len;
              chunks.add(bytes.sublist(i, end));
            }

            for (var i = 0; i < chunks.length; i += 1) {
              services?.forEach((service) async {
                // do something with service
                var characteristics = service.characteristics;
                for (BluetoothCharacteristic c in characteristics) {
                  if (c.properties.read) {
                    await c.write(chunks[i]);
                    // print(value);
                  }
                }
              });
              // await _bluetoothManager.writeData();
              sleep(Duration(milliseconds: queueSleepTimeMs));
            }

            completer.complete(PosPrintResult.success);
          }
          // TODO sending disconnect signal should be event-based
          _runDelayed(3).then((dynamic v) async {
            _selectedPrinter!.disconnect();
            _isPrinting = false;
          });
          _isConnected = true;
          break;
        case BluetoothAdapterState.off:
          _isConnected = false;
          break;
        default:
          break;
      }
    });

    // Printing timeout
    _runDelayed(timeout).then((dynamic v) async {
      if (_isPrinting) {
        _isPrinting = false;
        completer.complete(PosPrintResult.timeout);
      }
    });

    return completer.future;
  }

  Future<PosPrintResult> printTicket(
    List<int> bytes, {
    int chunkSizeBytes = 20,
    int queueSleepTimeMs = 20,
  }) async {
    if (bytes.isEmpty) {
      return Future<PosPrintResult>.value(PosPrintResult.ticketEmpty);
    }
    return writeBytes(
      bytes,
      chunkSizeBytes: chunkSizeBytes,
      queueSleepTimeMs: queueSleepTimeMs,
    );
  }
}
