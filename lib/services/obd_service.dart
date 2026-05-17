import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const String _pidRpm      = '010C';
const String _pidSpeed    = '010D';
const String _pidCoolant  = '0105';
const String _pidThrottle = '0111';
const String _pidLoad     = '0104';
const String _pidVoltage  = '0142';
const String _pidDtcCount = '0101';
const String _cmdReadDtc  = '03';
const String _cmdClearDtc = '04';

// Relaciones de marcha aproximadas Kawasaki Versys 650 (rpm/kmh)
const List<double> _gearRatios = [0, 113.0, 68.0, 49.5, 38.5, 32.0, 27.5];

class ObdData {
  final double rpm;
  final double speedKmh;
  final double coolantTemp;
  final double throttlePct;
  final double engineLoadPct;
  final double batteryVoltage;
  final int dtcCount;
  final int gear;

  const ObdData({
    this.rpm = 0,
    this.speedKmh = 0,
    this.coolantTemp = 0,
    this.throttlePct = 0,
    this.engineLoadPct = 0,
    this.batteryVoltage = 0,
    this.dtcCount = 0,
    this.gear = 0,
  });

  ObdData copyWith({
    double? rpm,
    double? speedKmh,
    double? coolantTemp,
    double? throttlePct,
    double? engineLoadPct,
    double? batteryVoltage,
    int? dtcCount,
  }) {
    final newRpm   = rpm ?? this.rpm;
    final newSpeed = speedKmh ?? this.speedKmh;
    return ObdData(
      rpm: newRpm,
      speedKmh: newSpeed,
      coolantTemp: coolantTemp ?? this.coolantTemp,
      throttlePct: throttlePct ?? this.throttlePct,
      engineLoadPct: engineLoadPct ?? this.engineLoadPct,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      dtcCount: dtcCount ?? this.dtcCount,
      gear: _estimateGear(newRpm, newSpeed),
    );
  }

  static int _estimateGear(double rpm, double speed) {
    if (rpm < 500 || speed < 5) return 0;
    final ratio = rpm / speed;
    int best = 0;
    double minDiff = double.infinity;
    for (int g = 1; g < _gearRatios.length; g++) {
      final diff = (ratio - _gearRatios[g]).abs();
      if (diff < minDiff) {
        minDiff = diff;
        best = g;
      }
    }
    return (minDiff / _gearRatios[best] < 0.25) ? best : 0;
  }
}

class ObdService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  final _dataController = StreamController<ObdData>.broadcast();
  final _dtcController  = StreamController<List<String>>.broadcast();

  Stream<ObdData>    get dataStream => _dataController.stream;
  Stream<List<String>> get dtcStream  => _dtcController.stream;

  ObdData _current = const ObdData();
  String _rxBuffer = '';
  Timer? _pollTimer;
  bool _awaitingDtc = false;

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
          if (uuid.contains('fff1') || uuid.contains('18f2')) _notifyChar = char;
          if (uuid.contains('fff2') || uuid.contains('18f1')) _writeChar  = char;
        }
      }
    }

    if (_writeChar == null || _notifyChar == null) {
      for (final svc in services) {
        for (final char in svc.characteristics) {
          if (char.properties.notify && _notifyChar == null)               _notifyChar = char;
          if (char.properties.writeWithoutResponse && _writeChar == null)  _writeChar  = char;
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
    _awaitingDtc = false;
  }

  Future<void> requestDtc() async {
    _pollTimer?.cancel();
    _awaitingDtc = true;
    await Future.delayed(const Duration(milliseconds: 300));
    await _send(_cmdReadDtc);
    await Future.delayed(const Duration(milliseconds: 2000));
    _awaitingDtc = false;
    _startPolling();
  }

  Future<void> clearDtc() async {
    _pollTimer?.cancel();
    await Future.delayed(const Duration(milliseconds: 300));
    await _send(_cmdClearDtc);
    await Future.delayed(const Duration(milliseconds: 1500));
    _current = _current.copyWith(dtcCount: 0);
    _dataController.add(_current);
    _startPolling();
  }

  Future<void> _initElm327() async {
    await _send('ATZ');
    await Future.delayed(const Duration(milliseconds: 1000));
    await _send('ATE0');
    await Future.delayed(const Duration(milliseconds: 200));
    await _send('ATL0');
    await Future.delayed(const Duration(milliseconds: 200));
    await _send('ATS0');
    await Future.delayed(const Duration(milliseconds: 200));
    await _send('ATSP0');
    await Future.delayed(const Duration(milliseconds: 200));
  }

  void _startPolling() {
    final pids = [_pidRpm, _pidSpeed, _pidCoolant, _pidThrottle, _pidLoad, _pidVoltage, _pidDtcCount];
    int idx = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (!_awaitingDtc) {
        await _send(pids[idx % pids.length]);
        idx++;
      }
    });
  }

  Future<void> _send(String cmd) async {
    if (_writeChar == null) return;
    await _writeChar!.write(utf8.encode('$cmd\r'), withoutResponse: true);
  }

  void _onData(List<int> bytes) {
    _rxBuffer += utf8.decode(bytes, allowMalformed: true);
    if (!_rxBuffer.contains('>')) return;

    final response = _rxBuffer.replaceAll('>', '').trim();
    _rxBuffer = '';

    if (_awaitingDtc) {
      _parseDtcResponse(response);
    } else {
      _parseResponse(response);
    }
  }

  void _parseResponse(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^0-9A-Fa-f\n]'), '').toUpperCase();
    for (final line in clean.split('\n')) {
      if (line.length >= 6) _parseLine(line.trim());
    }
  }

  void _parseLine(String line) {
    if (!line.startsWith('41')) return;
    if (line.length < 6) return;

    final pid  = line.substring(2, 4);
    final data = line.substring(4);

    try {
      switch (pid) {
        case '0C':
          if (data.length >= 4) {
            final a = int.parse(data.substring(0, 2), radix: 16);
            final b = int.parse(data.substring(2, 4), radix: 16);
            _current = _current.copyWith(rpm: ((a * 256) + b) / 4.0);
          }
        case '0D':
          if (data.length >= 2) {
            _current = _current.copyWith(
              speedKmh: int.parse(data.substring(0, 2), radix: 16).toDouble(),
            );
          }
        case '05':
          if (data.length >= 2) {
            _current = _current.copyWith(
              coolantTemp: (int.parse(data.substring(0, 2), radix: 16) - 40).toDouble(),
            );
          }
        case '11':
          if (data.length >= 2) {
            _current = _current.copyWith(
              throttlePct: int.parse(data.substring(0, 2), radix: 16) * 100 / 255,
            );
          }
        case '04':
          if (data.length >= 2) {
            _current = _current.copyWith(
              engineLoadPct: int.parse(data.substring(0, 2), radix: 16) * 100 / 255,
            );
          }
        case '42':
          if (data.length >= 4) {
            final a = int.parse(data.substring(0, 2), radix: 16);
            final b = int.parse(data.substring(2, 4), radix: 16);
            _current = _current.copyWith(batteryVoltage: ((a * 256) + b) / 1000.0);
          }
        case '01':
          if (data.length >= 6) {
            final b = int.parse(data.substring(2, 4), radix: 16);
            _current = _current.copyWith(dtcCount: b & 0x7F);
          }
      }
      _dataController.add(_current);
    } catch (_) {}
  }

  void _parseDtcResponse(String raw) {
    final clean = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final dtcs  = <String>[];

    // Respuesta modo 03: 43 XX YY XX YY...  (2 bytes por código)
    if (clean.startsWith('43') && clean.length > 2) {
      final payload = clean.substring(2);
      for (int i = 0; i + 3 < payload.length; i += 4) {
        final word = payload.substring(i, i + 4);
        if (word == '0000') continue;
        final first = int.tryParse(word[0], radix: 16) ?? 0;
        final prefix = ['P', 'C', 'B', 'U'][first >> 2];
        final code   = '${prefix}${(first & 0x03)}${word.substring(1)}';
        dtcs.add(code);
      }
    }

    _dtcController.add(dtcs);
  }

  void dispose() {
    _pollTimer?.cancel();
    _dataController.close();
    _dtcController.close();
  }
}
