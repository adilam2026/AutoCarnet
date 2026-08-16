package com.autocarnet.autocarnet

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth's biometric prompt requires a FlutterFragmentActivity - plain
// FlutterActivity throws at runtime when authenticate() is called.
class MainActivity : FlutterFragmentActivity()
