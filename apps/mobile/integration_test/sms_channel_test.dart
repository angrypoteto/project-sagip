// Runs on an Android device or emulator:
//   adb shell pm grant ph.sagip.sagip_mobile android.permission.SEND_SMS
//   flutter test integration_test/sms_channel_test.dart -d <device>
// The emulator's modem accepts outgoing texts, so this checks the Tier 2
// channel in MainActivity.kt end to end without a real SIM.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sagip_mobile/src/device/device_sms_sender.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the phone sends a Tier 2 SOS text', (tester) async {
    const sender = DeviceSmsSender();
    expect(await sender.canSend(), isTrue, reason: 'SEND_SMS granted');
    final text = SosSms.encode(
      SosRequest(
        clientId: '3f2a9c1e-7b4d-4e0a-9c2f-1a2b3c4d5e6f',
        capturedAt: DateTime.now(),
        delivery: DeliveryState.savedOnPhone,
        location: const GeoPoint(14.6091, 120.9925),
        accuracyMeters: 8,
      ),
    );
    // 5554 is the emulator's own number.
    expect(await sender.send('5554', text), isTrue);
  });
}
