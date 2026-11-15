package dev.dphotowatchlab.d_photo_watch_lab

import android.graphics.BitmapFactory
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.components.containers.NormalizedKeypoint
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.interactivesegmenter.InteractiveSegmenter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.util.concurrent.Executors

/**
 * "Tocca il quadrante": MediaPipe Interactive Segmenter (modello MagicTouch
 * di Google) eseguito sul telefono. Il modello lo scarica la parte Flutter.
 */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var segmenter: InteractiveSegmenter? = null
    private var segmenterModel: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dphotowatch/magictouch")
            .setMethodCallHandler { call, result ->
                if (call.method != "segment") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val model = call.argument<String>("model")
                val image = call.argument<String>("image")
                val x = call.argument<Double>("x")
                val y = call.argument<Double>("y")
                if (model == null || image == null || x == null || y == null) {
                    result.error("magictouch", "argomenti mancanti", null)
                    return@setMethodCallHandler
                }
                executor.execute {
                    try {
                        val seg = getSegmenter(model)
                        val bmp = BitmapFactory.decodeFile(image)
                            ?: throw IllegalArgumentException("immagine non leggibile")
                        val mpImage = BitmapImageBuilder(bmp).build()
                        val roi = InteractiveSegmenter.RegionOfInterest.create(
                            NormalizedKeypoint.create(x.toFloat(), y.toFloat())
                        )
                        val res = seg.segment(mpImage, roi)
                        val masks = res.confidenceMasks().orElse(emptyList())
                        val out = ArrayList<FloatArray>()
                        var w = 0
                        var h = 0
                        for (m in masks) {
                            w = m.width
                            h = m.height
                            val fb = ByteBufferExtractor.extract(m)
                                .order(ByteOrder.nativeOrder())
                                .asFloatBuffer()
                            val arr = FloatArray(fb.remaining())
                            fb.get(arr)
                            out.add(arr)
                        }
                        bmp.recycle()
                        runOnUiThread {
                            result.success(mapOf("width" to w, "height" to h, "masks" to out))
                        }
                    } catch (e: Throwable) {
                        runOnUiThread {
                            result.error("magictouch", e.message ?: e.toString(), null)
                        }
                    }
                }
            }
    }

    @Synchronized
    private fun getSegmenter(path: String): InteractiveSegmenter {
        val current = segmenter
        if (current != null && segmenterModel == path) return current
        val channel = RandomAccessFile(File(path), "r").channel
        val buffer = channel.map(FileChannel.MapMode.READ_ONLY, 0, channel.size())
        channel.close()
        val options = InteractiveSegmenter.InteractiveSegmenterOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetBuffer(buffer).build())
            .setOutputConfidenceMasks(true)
            .setOutputCategoryMask(false)
            .build()
        val created = InteractiveSegmenter.createFromOptions(this, options)
        segmenter?.close()
        segmenter = created
        segmenterModel = path
        return created
    }

    override fun onDestroy() {
        segmenter?.close()
        segmenter = null
        executor.shutdown()
        super.onDestroy()
    }
}
