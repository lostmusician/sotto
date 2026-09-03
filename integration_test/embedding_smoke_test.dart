import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meno/services/embedding_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Arctic Embed XS runs through the native ONNX runtime', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'meno-embedding-smoke-',
    );
    final service = ArcticEmbeddingService(modelDirectory: directory);
    addTearDown(() async {
      await service.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    await service.downloadModel();
    final vector = await service.embed('A quiet walk beside the river.');
    final second = await service.embed('Walking by calm water.', isQuery: true);

    expect(vector, hasLength(384));
    expect(second, hasLength(384));
    final norm = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + value * value),
    );
    expect(norm, closeTo(1, .001));
    expect(vector, everyElement(isA<double>()));
  });
}
