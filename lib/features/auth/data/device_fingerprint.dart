import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Bitmask flags for suspicious environment detection.
class EnvFlags {
  static const int emulator = 1;
  static const int root = 2;
  static const int hookFramework = 4;
}

/// Collects hardware fingerprint and detects suspicious environments.
class DeviceFingerprint {
  /// Generate a hardware fingerprint hash from system properties.
  /// Uses fields that are hard to spoof: CPU, memory, screen, OS build.
  static Future<String> getHardwareFingerprint() async {
    final parts = <String>[];
    try {
      if (Platform.isAndroid) {
        parts.addAll(await _androidFingerprint());
      } else if (Platform.isIOS) {
        parts.addAll(await _iosFingerprint());
      } else if (Platform.isWindows) {
        parts.addAll(await _desktopFingerprint('windows'));
      } else if (Platform.isMacOS) {
        parts.addAll(await _desktopFingerprint('macos'));
      } else if (Platform.isLinux) {
        parts.addAll(await _desktopFingerprint('linux'));
      }
    } catch (_) {}

    if (parts.isEmpty) {
      parts.add(Platform.operatingSystem);
      parts.add(Platform.operatingSystemVersion);
    }

    final raw = parts.join('|');
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
  }

  /// Detect suspicious environment. Returns bitmask of EnvFlags.
  static Future<int> detectEnvironment() async {
    int flags = 0;
    try {
      if (Platform.isAndroid) {
        if (await _isAndroidEmulator()) flags |= EnvFlags.emulator;
        if (await _isRooted()) flags |= EnvFlags.root;
        if (await _hasHookFramework()) flags |= EnvFlags.hookFramework;
      }
    } catch (_) {}
    return flags;
  }

  // ── Android fingerprint ──
  static Future<List<String>> _androidFingerprint() async {
    final parts = <String>[];
    try {
      // CPU hardware (stable across reinstalls and OS updates)
      final cpuInfo = await _readFile('/proc/cpuinfo');
      final hwMatch = RegExp(r'Hardware\s*:\s*(.+)').firstMatch(cpuInfo);
      if (hwMatch != null) parts.add(hwMatch.group(1)!.trim());
      final modelMatch = RegExp(r'model name\s*:\s*(.+)').firstMatch(cpuInfo);
      if (modelMatch != null) parts.add(modelMatch.group(1)!.trim());

      // Memory size (rounded to GB — stable)
      final memInfo = await _readFile('/proc/meminfo');
      final memMatch = RegExp(r'MemTotal:\s*(\d+)').firstMatch(memInfo);
      if (memMatch != null) {
        final memGb = (int.parse(memMatch.group(1)!) / 1048576).round();
        parts.add('mem${memGb}g');
      }

      // Device model + brand (stable, doesn't change with OS updates)
      final brand = await _shellCmd('getprop', ['ro.product.brand']);
      if (brand.isNotEmpty) parts.add(brand);
      final model = await _shellCmd('getprop', ['ro.product.model']);
      if (model.isNotEmpty) parts.add(model);
      final device = await _shellCmd('getprop', ['ro.product.device']);
      if (device.isNotEmpty) parts.add(device);

      // Serial number (stable, but may be "unknown" on newer Android)
      final serial = await _shellCmd('getprop', ['ro.serialno']);
      if (serial.isNotEmpty && serial != 'unknown') parts.add(serial);

      // Display density (stable)
      final density = await _shellCmd('getprop', ['ro.sf.lcd_density']);
      if (density.isNotEmpty) parts.add('dpi$density');
    } catch (_) {}
    return parts;
  }

  // ── iOS fingerprint ──
  static Future<List<String>> _iosFingerprint() async {
    // On iOS, use platform info available via dart:io
    return [
      Platform.operatingSystemVersion,
      Platform.localHostname,
    ];
  }

  // ── Desktop fingerprint ──
  static Future<List<String>> _desktopFingerprint(String os) async {
    final parts = <String>[
      Platform.operatingSystemVersion,
      Platform.numberOfProcessors.toString(),
    ];
    try {
      if (os == 'windows') {
        // Use WMIC to get motherboard serial + CPU ID (stable across reinstalls)
        final mbSerial = await _shellCmd('wmic', ['baseboard', 'get', 'serialnumber']);
        if (mbSerial.isNotEmpty) parts.add(mbSerial.split('\n').last.trim());
        final cpuId = await _shellCmd('wmic', ['cpu', 'get', 'processorid']);
        if (cpuId.isNotEmpty) parts.add(cpuId.split('\n').last.trim());
        final diskSerial = await _shellCmd('wmic', ['diskdrive', 'get', 'serialnumber']);
        if (diskSerial.isNotEmpty) {
          final lines = diskSerial.split('\n').where((l) => l.trim().isNotEmpty).toList();
          if (lines.length > 1) parts.add(lines.last.trim());
        }
      } else if (os == 'macos') {
        // macOS hardware UUID (stable)
        final hwUuid = await _shellCmd('system_profiler', ['SPHardwareDataType']);
        final match = RegExp(r'Hardware UUID:\s*(.+)').firstMatch(hwUuid);
        if (match != null) parts.add(match.group(1)!.trim());
      } else if (os == 'linux') {
        // Machine ID (stable across reinstalls on same OS install)
        final machineId = await _readFile('/etc/machine-id');
        if (machineId.isNotEmpty) parts.add(machineId.trim());
        // Also try DMI product UUID
        final dmiUuid = await _readFile('/sys/class/dmi/id/product_uuid');
        if (dmiUuid.isNotEmpty) parts.add(dmiUuid.trim());
      }
    } catch (_) {}
    // Always include hostname as fallback
    parts.add(Platform.localHostname);
    return parts;
  }

  // ── Emulator detection ──
  static Future<bool> _isAndroidEmulator() async {
    try {
      final checks = <String>[
        await _shellCmd('getprop', ['ro.hardware']),
        await _shellCmd('getprop', ['ro.product.model']),
        await _shellCmd('getprop', ['ro.build.characteristics']),
        await _shellCmd('getprop', ['ro.kernel.qemu']),
      ];
      final joined = checks.join(' ').toLowerCase();
      const emulatorHints = [
        'goldfish', 'ranchu', 'sdk', 'emulator', 'genymotion',
        'bluestacks', 'nox', 'andy', 'vbox', 'qemu', 'ttvm',
      ];
      for (final hint in emulatorHints) {
        if (joined.contains(hint)) return true;
      }
      // Check for emulator-specific files
      const emuFiles = [
        '/dev/socket/qemud',
        '/dev/qemu_pipe',
        '/system/lib/libc_malloc_debug_qemu.so',
        '/sys/qemu_trace',
      ];
      for (final f in emuFiles) {
        if (await File(f).exists()) return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Root detection ──
  static Future<bool> _isRooted() async {
    try {
      const suPaths = [
        '/system/bin/su', '/system/xbin/su', '/sbin/su',
        '/data/local/xbin/su', '/data/local/bin/su',
        '/system/sd/xbin/su', '/system/app/Superuser.apk',
        '/data/adb/magisk',
      ];
      for (final p in suPaths) {
        if (await File(p).exists()) return true;
      }
      // Check su command
      final result = await Process.run('which', ['su']);
      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ── Hook framework detection (Xposed, Frida, etc.) ──
  static Future<bool> _hasHookFramework() async {
    try {
      // Check for Xposed
      const xposedPaths = [
        '/system/framework/XposedBridge.jar',
        '/system/lib/libxposed_art.so',
        '/data/data/de.robv.android.xposed.installer',
        '/data/adb/lspd',
      ];
      for (final p in xposedPaths) {
        if (await File(p).exists()) return true;
      }
      // Check for Frida
      final maps = await _readFile('/proc/self/maps');
      if (maps.contains('frida') || maps.contains('gadget')) return true;
      // Check for common hook libs
      if (maps.contains('substrate') || maps.contains('xhook')) return true;
    } catch (_) {}
    return false;
  }

  // ── Helpers ──
  static Future<String> _readFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<String> _shellCmd(String cmd, List<String> args) async {
    try {
      final result = await Process.run(cmd, args);
      return result.stdout.toString().trim();
    } catch (_) {
      return '';
    }
  }
}
