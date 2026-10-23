import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/map_tiles.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// مصدرُ البلاطاتِ موضعٌ واحد (Mapbox) — قرارُ المالك 2026-10-24.
void main() {
  test('برمزٍ: رابطُ Mapbox بالنمطِ المعتمَد والرمز', () {
    final u = mapTileUrlTemplate(token: 'pk.test');
    expect(
        u, startsWith('https://api.mapbox.com/styles/v1/$kMapboxStyle/tiles/'));
    expect(u, contains('{z}/{x}/{y}'));
    expect(u, endsWith('access_token=pk.test'));
  });

  test('بلا رمز: احتياطُ OSM لا رابطٌ مكسور', () {
    expect(mapTileUrlTemplate(token: ''), kOsmTileUrl);
    expect(mapTileUrlTemplate(token: '   '), kOsmTileUrl);
  });

  test('لا رابطَ بلاطاتٍ مكتوبٌ بيدٍ ولا TileLayer محلّيّ في lib/', () {
    final files = sourcesIn('lib', atLeast: 100);
    final offenders = <String>[];
    var users = 0;
    for (final f in files) {
      if (f.path.endsWith('map_tiles.dart')) continue;
      final code = stripComments(File(f.path).readAsStringSync());
      if (code.contains('openstreetmap') ||
          code.contains('api.mapbox.com/styles') ||
          RegExp(r'(?<![A-Za-z_])TileLayer\(').hasMatch(code)) {
        offenders.add(f.path);
      }
      if (RegExp(r'\bzyiarahTileLayer\(').hasMatch(code)) users++;
    }
    expect(offenders, isEmpty,
        reason: 'البلاطاتُ تُطلَبُ من map_tiles.dart وحدَه');
    // الخرائطُ الستّ — انحلالُ المسحِ يَسقطُ لا يَمرُّ أخضر.
    expect(users, greaterThanOrEqualTo(6));
  });
}
