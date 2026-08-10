package dev.filefin.filefin_mobile

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.filefin.filefin_mobile/ca_bundle"
        ).setMethodCallHandler { call, result ->
            if (call.method == "exportCaBundle") {
                val path = CaBundleHelper.export(applicationContext)
                result.success(path)
            } else {
                result.notImplemented()
            }
        }
    }
}
