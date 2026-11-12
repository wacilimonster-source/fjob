// 回归：Windows 托盘图标必须是 .ico。tray_manager 在 Windows 用
// LoadImage(IMAGE_ICON, LR_LOADFROMFILE) 加载，PNG 会返回 NULL，任务栏
// 通知区因此显示空白（见本轮修复）。见 docs/23。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tray icon is a multi-size ICO with embeddable PNG frames', () {
    final file = File('assets/tray_icon.ico');
    expect(file.existsSync(), isTrue, reason: '缺少打包的托盘 .ico 资源');
    final bytes = file.readAsBytesSync();
    final data = ByteData.sublistView(bytes);

    expect(data.getUint16(0, Endian.little), 0, reason: 'ICONDIR.reserved');
    expect(data.getUint16(2, Endian.little), 1, reason: 'ICONDIR.type=icon');
    final count = data.getUint16(4, Endian.little);
    expect(count, greaterThanOrEqualTo(4));

    const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    final widths = <int>{};
    for (var i = 0; i < count; i++) {
      final entry = 6 + i * 16;
      final width = bytes[entry];
      expect(bytes[entry + 1], width, reason: '图标宽高不一致');
      expect(data.getUint16(entry + 4, Endian.little), 1, reason: 'planes');
      expect(data.getUint16(entry + 6, Endian.little), 32, reason: 'bpp');
      final length = data.getUint32(entry + 8, Endian.little);
      final offset = data.getUint32(entry + 12, Endian.little);
      expect(length, greaterThan(0));
      expect(offset + length, lessThanOrEqualTo(bytes.length));
      expect(
        bytes.sublist(offset, offset + 8),
        pngSignature,
        reason: '内嵌帧应为 PNG（Vista+ 托盘可直接读取）',
      );
      widths.add(width == 0 ? 256 : width);
    }
    // 100%–200% 缩放分别取 16/20/24/32。
    expect(widths, containsAll(<int>[16, 20, 24, 32]));
  });
}
