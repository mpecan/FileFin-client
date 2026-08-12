package dev.filefin.filefin_mobile

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
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

        // Which of the two shells the app builds — see
        // lib/src/shell/form_factor.dart. UiModeManager rather than a screen
        // size: the difference the layouts turn on is the INPUT DEVICE, and a
        // 10-inch tablet and a 32-inch television can report the same width in
        // density-independent pixels while agreeing about nothing else.
        //
        // Deliberately NOT a check for the `android.software.leanback` FEATURE.
        // That feature is declared by this app's own manifest as
        // `required="false"`, so PackageManager reports it present on a phone
        // as well and the answer would always be "television".
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.filefin.filefin_mobile/form_factor"
        ).setMethodCallHandler { call, result ->
            if (call.method == "isTelevision") {
                val uiMode =
                    applicationContext.getSystemService(Context.UI_MODE_SERVICE)
                        as UiModeManager
                result.success(
                    uiMode.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                )
            } else {
                result.notImplemented()
            }
        }
    }
}
