import 'package:app/common/widgets/bottom_button.dart';
import 'package:flutter/material.dart';

class RouteLayout extends StatelessWidget {
  const RouteLayout({
    super.key,
    required this.children,
    required this.onPressed,
    required this.routeText,
  });

  final List<Widget> children;
  final String routeText;
  final void Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        ...children,
        BottomButton(
          text: routeText,
          onPressed: onPressed,
        ),
      ],
    );
  }
}
