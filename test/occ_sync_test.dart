import 'package:autocarnet/core/sync/occ_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('newerRemoteRows (pure)', () {
    test('a remote row with a higher version than local is included', () {
      final result = newerRemoteRows(
        remoteRows: [
          {'id': 'a', 'version': 3},
        ],
        localVersionById: {'a': 2},
      );
      expect(result, hasLength(1));
      expect(result.first['id'], 'a');
    });

    test('a remote row with the same version as local is not re-applied', () {
      final result = newerRemoteRows(
        remoteRows: [
          {'id': 'a', 'version': 2},
        ],
        localVersionById: {'a': 2},
      );
      expect(result, isEmpty);
    });

    test('a remote row this device has never seen locally is always included', () {
      final result = newerRemoteRows(
        remoteRows: [
          {'id': 'brand-new', 'version': 1},
        ],
        localVersionById: {},
      );
      expect(result, hasLength(1));
    });

    test('a row with an unresolved conflict is never silently overwritten by a later pull', () {
      final result = newerRemoteRows(
        remoteRows: [
          {'id': 'a', 'version': 5},
          {'id': 'b', 'version': 2},
        ],
        localVersionById: {'a': 1, 'b': 1},
        skipIds: {'a'},
      );
      expect(result.map((r) => r['id']), ['b']);
    });
  });
}
