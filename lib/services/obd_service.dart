import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// OBD-II Mode 01 PIDs
const String _pidRpm      = '010C';
const String _pidSpeed    = '010D';
const String _pidCoolant  = '0105';
const String _pidThrottle = '0111';
const String _pidLoad     = '0104';

class ObdData {
  final double rpm;
  final double speedKmh;
  final double coolantTemp;
  final double throttlePct;
  final double engineLoadPct;

  const ObdData({
    this.rpm = 0,
    this.speedKmh = 0,
    this.coolantTemp = 0,
    this.throttlePct = 0,
    this.engineLoadPct = 0,
  });

  ObdData copyWith({
    double? rpm,
    double? speedKmh,
    double? coolantTemp,
    double? throttlePct,
    double? engineLoadPct,
  }) => ObdData(
    rpm: rpm ?? this.rpm,
    speedKmh: speedKmh ?? this.speedKmh,
    coolantTemp: coolantTemp ?? this.coolantTemp,
    throttlePct: throttlePct ?? this.throttlePct,
    engineLoadPct: engineLoadPct ?? this.engineLoadPct,
  );
}

class ObdService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  final _dataController = StreamController<ObdData>.broadcast();
  Stream<ObdData> get dataStream => _dataController.stream;

  ObdData _current = const ObdData();
  String _rxBuffer = '';
  Timer? _pollTimer;

  bool get isConnected => _device != null;

  Future<void> connect(BluetoothDevice device) async {
    await device.connect(license: License.free, autoConnect: false);
    _device = device;

    final services = await device.discoverServices();
    for (final svc in services) {
      if (svc.uuid.toString().toLowerCase().contains('fff0') ||
          svc.uuid.toString().toLowerCase().contains('18f0')) {
        for (final char in svc.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid.contains('fff1') || uuid.contains('18f2')) {
            _notifyChar = char;
          }
          if (uuid.contains('fff2') || uuid.contains('18f1')) {
            _writeChar = char;
          }
        }
      }
    }

    // Fallback: buscar por propiedades si los UUIDs no coinciden
    if (_writeChar == null || _notifyChar == null) {
      for (final svc in services) {
        for (final char in svc.characteristics) {
          if (char.properties.notify && _notifyChar == null) {
            _notifyChar = char;
          }
          if (char.properties.writeWithoutResponse && _writeChar == null) {
            _writeChar = char;
          }
        }
      }
    }

    if (_notifyChar == null || _writeChar == null) {
      throw Exception('No se encontraron características OBD en el dispositivo');
    }

    await _notifyChar!.setNotifyValue(true);
    _notifyChar!.lastValueStream.listen(_onData);

    await _initElm327();
    _startPolling();
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    await _device?.disconnect();
    _device = null;
    _writeChar = null;
    _notifyChar = null;
    _rxBuffer = '';
  }

  Future<void> _initElm327() async {
    await _send('ATZ');    // reset
    await Future.delayed(const Duration(milliseconds: 1000));
    await _send('ATE0');   // echo off
    await Future.delayed(const Duration(milliseconds: 200));
    await _send('ATL0');   // linefeed off
    await Future.delayed(const Duration(milliseconds: 200));
    await _send('ATS0');   // spaces off
    await Future.delayed(const Duration(milliseconds: 200));
    await _send('ATSP0');  // auto protocolo
    await Future.delayed(const Duration(milliseconds: 200));
  }

  void _startPolling() {
    final pids = [_pidRpm, _pidSpeed, _pidCoolant, _pidThrottle, _pidLoad];
    int idx = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      await _send(pids[idx % pids.length]);
      idx++;
    });
  }

  Future<void> _send(String cmd) async {
    if (_writeChar == null) return;
    final bytes = utf8.encode('$cmd\r');
    await _writeChar!.write(bytes, withoutResponse: true);
  }

  void _onData(List<int> bytes) {
    _rxBuffer += utf8.decode(bytes, allowMalformed: true);
    if (!_rxBuffer.contains('>')) return;

    final response = _rxBuffer.replaceAll('>', '').trim();
    _rxBuffer = '';
    _parseResponse(response);
  }

  void _parseResponse(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^0-9A-Fa-f\n]'), '').toUpperCase();
    for (final line in clean.split('\n')) {
      if (line.length < 6) continue;
      _parseLine(line.trim());
    }
  }

  void _parseLine(String line) {
    if (!line.startsWith('41')) return;
    if (line.length < 6) return;

    final pid = line.substring(2, 4);
    final data = line.substring(4);

    try {
      switch (pid) {
        case '0C': // RPM: ((A*256)+B)/4
          if (data.length >= 4) {
            final a = int.parse(data.substring(0, 2), radix: 16);
            final b = int.parse(data.substring(2, 4), radix: 16);
            _current = _current.copyWith(rpm: ((a * 256) + b) / 4.0);
          }
        case '0D': // Speed: A km/h
          if (data.length >= 2) {
            final a = int.parse(data.substring(0, 2), radix: 16);
            _current = _current.copyWith(speedKmh: a.toDouble());
          }
        case '05': // Coolant temp: A - 40 °C
          if (data.length >= 2) {
            final a = int.parse(data.substring(0, 2), radix: 16);
            _current = _current.copyWith(coolantTemp: (a - 40).toDouble());
          }
        case '11': // Throttle: A*100/255 %
          if (data.length >= 2) {
            final a = int.parse(data.substring(0, 2), radix: 16);
            _current = _current.copyWith(throttlePct: a * 100 / 255);
          }
        case '04': // Engine load: A*100/255 %
          if (data.length >= 2) {
            final a = int.parse(data.substring(0, 2), radix: 16);
            _current = _current.copyWith(engineLoadPct: a * 100 / 255);
          }
      }
      _dataController.add(_current);
    } catch (_) {}
  }

  void dispose() {
    _pollTimer?.cancel();
    _dataController.close();
  }
}
