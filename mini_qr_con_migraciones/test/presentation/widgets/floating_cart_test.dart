import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mini_app_qr/domain/entities/product.dart';
import 'package:mini_app_qr/presentation/widgets/floating_cart.dart';

void main() {
  Product product(int id) => Product(
        id: id,
        merchantId: 53,
        name: 'Producto $id',
        description: '',
        price: 10,
        urlImage: '',
      );

  Future<void> pumpCart(
    WidgetTester tester, {
    required List<Product> products,
    VoidCallback? onPay,
  }) {
    final total = products.length; // 1 unidad de cada producto
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FloatingCart(
              products: products,
              quantityFor: (_) => 1,
              totalItems: total,
              totalAmount: total * 10.0,
              onPay: onPay ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('vacío: muestra la ayuda y PAGAR está apagado', (tester) async {
    await pumpCart(tester, products: const []);

    expect(find.text('Toca + para agregar'), findsOneWidget);
    expect(find.text('0.00 Bs'), findsOneWidget);
    final pay = tester.widget<FilledButton>(
      find.byKey(const ValueKey('cart-pay-button')),
    );
    expect(pay.onPressed, isNull);
  });

  testWidgets('con productos: muestra el total y PAGAR llama a onPay',
      (tester) async {
    var paid = 0;
    await pumpCart(
      tester,
      products: [product(1), product(2)],
      onPay: () => paid++,
    );

    expect(find.text('Toca + para agregar'), findsNothing);
    expect(find.text('20.00 Bs'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cart-pay-button')));
    expect(paid, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('más de 8 productos: la última miniatura dice +N',
      (tester) async {
    await pumpCart(
      tester,
      products: [for (var i = 1; i <= 11; i++) product(i)],
    );

    // 7 miniaturas + "+4"
    expect(find.text('+4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
