import 'package:animeflux/core/utils/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.compareVersions', () {
    test('versi lebih baru terdeteksi', () {
      expect(UpdateService.compareVersions('v1.0.2', '1.0.1') > 0, isTrue);
      expect(UpdateService.compareVersions('1.1.0', '1.0.9') > 0, isTrue);
      expect(UpdateService.compareVersions('2.0', '1.9.9') > 0, isTrue);
    });
    test('versi sama / lebih lama', () {
      expect(UpdateService.compareVersions('v1.0.1', '1.0.1+2'), 0);
      expect(UpdateService.compareVersions('1.0.0', '1.0.1') < 0, isTrue);
    });
  });
}
