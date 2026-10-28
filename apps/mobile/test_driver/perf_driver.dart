// Saves the frame times map_perf_test.dart reports, to build/map_perf.json.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) => writeResponseData(
    data,
    testOutputFilename: 'map_perf',
    destinationDirectory: 'build',
  ),
);
