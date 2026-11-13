import 'package:couchplay/catalog/details_view.dart';
import 'package:couchplay/server/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("image de fond : fondu sans calque de masque, qui coûte un "
      "saveLayer par image pendant le défilement", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DetailsHeader(
              details: Details(
                name: 'Horizon',
                backdrop: Uri.https('example.com', '/fond.jpg').toString(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Horizon'), findsOneWidget);
    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
  });
}
