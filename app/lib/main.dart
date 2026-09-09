import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'router.dart';
import 'state/demo_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  runApp(VerspaetomatApp(state: DemoState()));
}

class VerspaetomatApp extends StatefulWidget {
  const VerspaetomatApp({super.key, required this.state});
  final DemoState state;

  @override
  State<VerspaetomatApp> createState() => _VerspaetomatAppState();
}

class _VerspaetomatAppState extends State<VerspaetomatApp> {
  late final router = buildRouter(widget.state);

  @override
  Widget build(BuildContext context) {
    return DemoScope(
      state: widget.state,
      child: MaterialApp.router(
        title: 'Verspätomat',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: router,
        color: VColors.paper,
      ),
    );
  }
}
