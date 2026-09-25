package deckers.thibault.aves.channel.calls

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.util.Log
import androidx.core.net.toUri
import com.bumptech.glide.Glide
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import deckers.thibault.aves.channel.calls.Coresult.Companion.safeSuspend
import deckers.thibault.aves.storage.StorageUtils
import deckers.thibault.aves.utils.LogUtils
import java.io.File
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class FaceHandler(private val context: Context) : MethodCallHandler {
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var interpreter: Interpreter? = null
    private var faceDetector: FaceDetector? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "detectFaces" -> ioScope.launch { safeSuspend(call, result, ::detectFaces) }
            "cosineSimilarity" -> safeSuspendSync(call, result, ::cosineSimilarity)
            else -> result.notImplemented()
        }
    }

    private fun safeSuspendSync(call: MethodCall, result: MethodChannel.Result, block: (MethodCall, MethodChannel.Result) -> Unit) {
        try {
            block(call, result)
        } catch (e: Exception) {
            result.error("face-error", e.message, e.stackTraceToString())
        }
    }

    @Synchronized
    private fun getInterpreter(): Interpreter {
        if (interpreter == null) {
            val modelBuffer: ByteBuffer = try {
                val fileDescriptor = context.assets.openFd("mobile_face_net.tflite")
                val inputStream = FileInputStream(fileDescriptor.fileDescriptor)
                val fileChannel = inputStream.channel
                fileChannel.map(FileChannel.MapMode.READ_ONLY, fileDescriptor.startOffset, fileDescriptor.declaredLength)
            } catch (e: Exception) {
                Log.w(LOG_TAG, "openFd failed (${e.message}), fallback to direct asset read")
                context.assets.open("mobile_face_net.tflite").use { inputStream ->
                    val bytes = inputStream.readBytes()
                    val buffer = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
                    buffer.put(bytes)
                    buffer.rewind()
                    buffer
                }
            }
            val options = Interpreter.Options().apply {
                setNumThreads(4)
            }
            interpreter = Interpreter(modelBuffer, options)
            Log.i(LOG_TAG, "MobileFaceNet TFLite interpreter initialized")
        }
        return interpreter!!
    }

    @Synchronized
    private fun getFaceDetector(): FaceDetector {
        if (faceDetector == null) {
            try {
                com.google.mlkit.common.sdkinternal.MlKitContext.initializeIfNeeded(context.applicationContext)
            } catch (e: Throwable) {
                Log.w(LOG_TAG, "MlKitContext.initializeIfNeeded: ${e.message}")
            }
            val options = FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                .setMinFaceSize(0.1f)
                .build()
            faceDetector = FaceDetection.getClient(options)
            Log.i(LOG_TAG, "ML Kit FaceDetector initialized")
        }
        return faceDetector!!
    }

    private suspend fun detectFaces(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        val path = call.argument<String>("path")
        val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
        if (uriStr == null && path == null) {
            result.error("detectFaces-args", "missing uri and path", null)
            return
        }

        Log.i(LOG_TAG, "detectFaces start: uriStr=$uriStr, path=$path, mimeType=$mimeType")

        val bitmap = withContext(Dispatchers.IO) {
            var bmp: Bitmap? = null
            if (uriStr != null) {
                try {
                    val uri = uriStr.toUri()
                    val safeUri = StorageUtils.getGlideSafeUri(context, uri, mimeType)
                    bmp = Glide.with(context)
                        .asBitmap()
                        .load(safeUri)
                        .override(1024, 1024)
                        .fitCenter()
                        .submit()
                        .get()
                } catch (e: Exception) {
                    Log.w(LOG_TAG, "failed to decode bitmap via uri=$uriStr", e)
                }
            }
            if (bmp == null && path != null) {
                try {
                    bmp = Glide.with(context)
                        .asBitmap()
                        .load(File(path))
                        .override(1024, 1024)
                        .fitCenter()
                        .submit()
                        .get()
                } catch (e: Exception) {
                    Log.w(LOG_TAG, "failed to decode bitmap via path=$path", e)
                }
            }
            bmp
        }

        if (bitmap == null) {
            Log.w(LOG_TAG, "detectFaces: bitmap could not be decoded")
            result.success(emptyList<Map<String, Any>>())
            return
        }

        Log.i(LOG_TAG, "detectFaces: bitmap decoded ${bitmap.width}x${bitmap.height}, running ML Kit FaceDetector")

        try {
            val detector = getFaceDetector()
            val inputImage = InputImage.fromBitmap(bitmap, 0)
            val faces: List<Face> = suspendCancellableCoroutine { cont ->
                detector.process(inputImage)
                    .addOnSuccessListener { detectedFaces -> cont.resume(detectedFaces) }
                    .addOnFailureListener { error -> cont.resumeWithException(error) }
            }

            Log.i(LOG_TAG, "detectFaces: ML Kit found ${faces.size} face(s)")

            if (faces.isEmpty()) {
                result.success(emptyList<Map<String, Any>>())
                return
            }

            val tflite = getInterpreter()
            val faceResults = mutableListOf<Map<String, Any>>()

            val imgWidth = bitmap.width.toFloat()
            val imgHeight = bitmap.height.toFloat()

            for (face in faces) {
                val rect = face.boundingBox
                val marginX = (rect.width() * 0.1f).toInt()
                val marginY = (rect.height() * 0.1f).toInt()
                val left = max(0, rect.left - marginX)
                val top = max(0, rect.top - marginY)
                val right = min(bitmap.width, rect.right + marginX)
                val bottom = min(bitmap.height, rect.bottom + marginY)
                val cropW = right - left
                val cropH = bottom - top

                if (cropW <= 0 || cropH <= 0) continue

                val cropped = Bitmap.createBitmap(bitmap, left, top, cropW, cropH)
                val scaled = Bitmap.createScaledBitmap(cropped, 112, 112, true)
                if (cropped != bitmap && cropped != scaled) {
                    cropped.recycle()
                }

                val inputBuffer = ByteBuffer.allocateDirect(1 * 112 * 112 * 3 * 4).apply {
                    order(ByteOrder.nativeOrder())
                }
                val pixels = IntArray(112 * 112)
                scaled.getPixels(pixels, 0, 112, 0, 0, 112, 112)
                var p = 0
                for (i in 0 until 112) {
                    for (j in 0 until 112) {
                        val pixel = pixels[p++]
                        inputBuffer.putFloat(((pixel shr 16 and 0xFF) - 127.5f) / 128.0f)
                        inputBuffer.putFloat(((pixel shr 8 and 0xFF) - 127.5f) / 128.0f)
                        inputBuffer.putFloat(((pixel and 0xFF) - 127.5f) / 128.0f)
                    }
                }
                scaled.recycle()

                val output = Array(1) { FloatArray(192) }
                synchronized(tflite) {
                    tflite.run(inputBuffer, output)
                }
                val embedding = output[0]

                var sumSq = 0.0f
                for (v in embedding) sumSq += v * v
                val norm = sqrt(sumSq)
                if (norm > 0) {
                    for (k in embedding.indices) embedding[k] /= norm
                }

                // Normalized bounding box: [left, top, right, bottom] in [0.0..1.0]
                val normalizedBounds = listOf(
                    (left / imgWidth).toDouble(),
                    (top / imgHeight).toDouble(),
                    (right / imgWidth).toDouble(),
                    (bottom / imgHeight).toDouble(),
                )

                faceResults.add(
                    mapOf(
                        "bounds" to normalizedBounds,
                        "embedding" to embedding.map { it.toDouble() }
                    )
                )
            }

            Log.i(LOG_TAG, "detectFaces done: extracted ${faceResults.size} face(s)")
            result.success(faceResults)
        } catch (e: Exception) {
            Log.e(LOG_TAG, "face detection failed", e)
            result.error("detectFaces-failed", e.message, null)
        }
    }

    private fun cosineSimilarity(call: MethodCall, result: MethodChannel.Result) {
        val v1 = call.argument<List<Number>>("v1")
        val v2 = call.argument<List<Number>>("v2")
        if (v1 == null || v2 == null || v1.size != v2.size) {
            result.error("cosineSimilarity-args", "invalid vector arguments", null)
            return
        }

        var dot = 0.0
        for (i in v1.indices) {
            dot += v1[i].toDouble() * v2[i].toDouble()
        }
        result.success(dot)
    }

    companion object {
        private val LOG_TAG = LogUtils.createTag<FaceHandler>()
        const val CHANNEL = "deckers.thibault/aves/face"
    }
}
