import 'package:couchplay/television.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.arrowUp,
    logicalKey: key,
    timeStamp: Duration.zero,
  );

  test('arrowDirection : le sens de chaque flèche appuyée', () {
    expect(
      arrowDirection(down(LogicalKeyboardKey.arrowUp)),
      TraversalDirection.up,
    );
    expect(
      arrowDirection(down(LogicalKeyboardKey.arrowDown)),
      TraversalDirection.down,
    );
    expect(
      arrowDirection(down(LogicalKeyboardKey.arrowLeft)),
      TraversalDirection.left,
    );
    expect(
      arrowDirection(
        KeyRepeatEvent(
          physicalKey: PhysicalKeyboardKey.arrowRight,
          logicalKey: LogicalKeyboardKey.arrowRight,
          timeStamp: Duration.zero,
        ),
      ),
      TraversalDirection.right,
    );
  });

  test('arrowDirection : rien pour un relâchement ou une autre touche', () {
    expect(
      arrowDirection(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.arrowUp,
          logicalKey: LogicalKeyboardKey.arrowUp,
          timeStamp: Duration.zero,
        ),
      ),
      isNull,
    );
    expect(arrowDirection(down(LogicalKeyboardKey.enter)), isNull);
  });
}
