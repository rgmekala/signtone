import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';

Future<void> main() async {
  // 1. Ensure Flutter engine is ready before any plugin calls
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Lock to portrait - Signtone is a portrait-only app
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 3. Style the system UI chrome
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // 4. Load .env before any widget reads AppConstants.baseUrl
  await dotenv.load(fileName: '.env');

  // 5. Launch
  runApp(const SigntoneApp());
}
