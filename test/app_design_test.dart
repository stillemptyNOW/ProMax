import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/config/app_design.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'the new design is default and classic persists across reloads',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppDesign.load(), isFalse);
      await AppDesign.saveClassic(true);
      expect(AppDesign.classic.value, isTrue);
      AppDesign.classic.value = false;
      expect(await AppDesign.load(), isTrue);
      await AppDesign.saveClassic(false);
      expect(await AppDesign.load(), isFalse);
    },
  );
}
