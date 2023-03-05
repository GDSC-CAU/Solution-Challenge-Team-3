import 'package:app/providers/providers.dart';
import 'package:app/screens/test/ocr/ocr_screen.dart';
import 'package:flutter/material.dart';

Future<void> setupPackages() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initTts();
  await initializeCameraInstance(
    resolution: ResolutionPreset.max,
  );
  appCameraController.destroyController();
}

Future<void> main() async {
  await setupPackages();

  runApp(const Blinder());
}

class Blinder extends StatelessWidget {
  const Blinder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Providers(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "Blinder",
        // routes: AppRouter.routes,
        // home: AppRouter.initialScreen,
        // initialRoute: AppRouter.mainVoicePath,
        home: OcrScreen(),
      ),
    );
  }
}
