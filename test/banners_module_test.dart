import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/api.dart';
import 'package:promax/backend/modules/banners.dart';
import 'package:promax/models/informer_banner.dart';

void main() {
  test('a pinned banner records one presentation', () async {
    final api = Api();
    addTearDown(api.dispose);
    final module = BannersModule(api);
    const banner = InformerBanner(
      id: 'synthetic-banner',
      title: 'Synthetic title',
      repeat: 3,
    );

    await module.markShown(banner);
    await module.markShown(banner);

    expect(module.stateOf(banner.id).showCounter, 1);

    await module.close(banner);
    await module.markShown(banner);

    expect(module.stateOf(banner.id).showCounter, 2);
  });
}
