// Runs every integration test file in one build, which is faster than
// building and installing the app once per file:
//
//   flutter test integration_test/all_test.dart --reporter expanded -d <device>

import 'it01_wrist_measurement_test.dart' as it01;
import 'it02_outfit_recommendation_test.dart' as it02;
import 'it03_catalog_listing_test.dart' as it03;
import 'it05_chat_grounding_test.dart' as it05;
import 'it06_watch_media_ar_ready_test.dart' as it06;
import 'it07_engagement_test.dart' as it07;
import 'it08_security_rules_test.dart' as it08;
import 'it09_accounts_admin_test.dart' as it09;

void main() {
  it01.main();
  it02.main();
  it03.main();
  it05.main();
  it06.main();
  it07.main();
  it08.main();
  it09.main();
}
