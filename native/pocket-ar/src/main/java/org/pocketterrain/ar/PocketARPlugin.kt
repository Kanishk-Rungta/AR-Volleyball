package org.pocketterrain.ar

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.SystemClock
import android.os.PowerManager
import android.util.Log
import android.view.Surface
import com.google.ar.core.*
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import java.util.EnumSet
import java.util.concurrent.atomic.AtomicBoolean
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit


/** ARCore runs on a dedicated EGL pbuffer, independent of Godot's Vulkan renderer.
 * Raw YUV feeds a Godot shader; optional MediaPipe runs on a separate bounded worker.
 * All session/anchor/EGL operations are serialized on one worker.
 */
class PocketARPlugin(godot: Godot) : GodotPlugin(godot) {
    private val worker = Executors.newSingleThreadScheduledExecutor()
    private val handWorker = Executors.newSingleThreadExecutor()
    private val previewWorker = Executors.newSingleThreadExecutor()
    private val previewBusy = AtomicBoolean(false)
    @Volatile private var safePreview = true
    @Volatile private var previewSequence = -1L
    @Volatile private var previewError = ""
    private var lastPreviewRequest = 0L
    private val handBusy = AtomicBoolean(false)
    @Volatile private var handsEnabled = false
    @Volatile private var handGeneration = 0
    private data class HandResult(val points: FloatArray, val timestamp: Long)
    @Volatile private var handResult: HandResult? = null
    @Volatile private var cameraYuv = ByteArray(0)
    private var lastCameraTimestamp = -1L
    private var lastHandRequest = 0L
    private var session: Session? = null
    private var anchor: Anchor? = null
    private var detector: HandLandmarker? = null
    private var eglDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface = EGL14.EGL_NO_SURFACE
    private var cameraTexture = 0
    @Volatile private var requested = false
    @Volatile private var resumed = false
    @Volatile private var width = 1080
    @Volatile private var height = 1920
    @Volatile private var rotation = Surface.ROTATION_0
    @Volatile private var state = "Tap Allow for camera permission"
    @Volatile private var frameJson = "{\"status\":\"Starting ARCore\"}"
    @Volatile private var jpeg = ByteArray(0)
    @Volatile private var placement: Pair<Float, Float>? = null
    private var sequence = 0L
    private var jpegSequence = -1L
    private var lastImageTime = 0L
    private var lastTrackingDiagnostic = 0L
    private var permissionAsked = false
    private var installAsked = false
    private var hand = JSONArray()
    private var pinch = false
    private var handTimestamp = 0L
    @Volatile private var handError = ""
    private var modelAttempted = false
    private var loopStarted = false
    private var sessionRunning = false

    override fun getPluginName() = "PocketAR"

    @UsedByGodot
    fun startSession(viewWidth: Int, viewHeight: Int) {
        width = viewWidth.coerceAtLeast(1)
        height = viewHeight.coerceAtLeast(1)
        requested = true
        activity?.runOnUiThread { checkRequirements() }
    }

    @UsedByGodot fun getFrame(): String = frameJson
    @UsedByGodot fun updateDisplayGeometry(viewWidth: Int, viewHeight: Int) {
        width = viewWidth.coerceAtLeast(1)
        height = viewHeight.coerceAtLeast(1)
        activity?.runOnUiThread {
            @Suppress("DEPRECATION")
            rotation = activity?.windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        }
    }
    @UsedByGodot fun getCameraJpeg(): ByteArray = jpeg
    @UsedByGodot fun setSafePreviewEnabled(enabled: Boolean) { safePreview = enabled }
    @UsedByGodot fun getCameraYuv(): ByteArray = cameraYuv
    @UsedByGodot fun setHandTrackingEnabled(enabled: Boolean) {
        handsEnabled = enabled
        handGeneration++
        handResult = null
        handError = ""
    }
    @UsedByGodot fun placeAnchor(x: Double, y: Double) {
        placement = Pair(x.toFloat().coerceIn(0f, 1f), y.toFloat().coerceIn(0f, 1f))
    }
    @UsedByGodot fun cancelPlacement() { placement = null }

    override fun onMainResume() {
        resumed = true
        if (requested) checkRequirements()
    }

    override fun onMainPause() {
        resumed = false
        worker.execute {
            sessionRunning = false
            try { session?.pause() } catch (_: Exception) { }
        }
    }

    override fun onMainRequestPermissionsResult(code: Int, permissions: Array<out String>?, results: IntArray?) {
        super.onMainRequestPermissionsResult(code, permissions, results)
        if (code == 7042) {
            if (results?.firstOrNull() == PackageManager.PERMISSION_GRANTED) checkRequirements()
            else publishStatus("Camera permission denied. Enable it in Android Settings, then reopen.")
        }
    }

    private fun publishStatus(message: String) {
        state = message
        frameJson = JSONObject().put("status", message).toString()
    }

    private fun checkRequirements() {
        val host = activity ?: return
        if (!requested || !resumed) return
        if (host.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            if (!permissionAsked) {
                permissionAsked = true
                host.requestPermissions(arrayOf(Manifest.permission.CAMERA), 7042)
            }
            return
        }
        try {
            if (ArCoreApk.getInstance().requestInstall(host, !installAsked) == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                installAsked = true
                publishStatus("Install Google Play Services for AR, then return")
                return
            }
        } catch (error: Exception) {
            publishStatus("ARCore unavailable: ${error.message}")
            return
        }
        @Suppress("DEPRECATION")
        rotation = host.windowManager.defaultDisplay.rotation
        worker.execute {
            try {
                if (session == null) {
                    createEgl()
                    session = Session(host)
                    val cameraFilter = CameraConfigFilter(session).setTargetFps(EnumSet.of(CameraConfig.TargetFps.TARGET_FPS_30))
                    session!!.getSupportedCameraConfigs(cameraFilter).minByOrNull { it.imageSize.width * it.imageSize.height }?.let {
                        session!!.cameraConfig = it
                    }
                    val config = Config(session).apply {
                        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                        updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                        lightEstimationMode = Config.LightEstimationMode.DISABLED
                        focusMode = Config.FocusMode.AUTO
                    }
                    session!!.configure(config)
                    session!!.setCameraTextureName(cameraTexture)
                }
                session!!.resume()
                sessionRunning = true
                state = "Scan a textured surface · aim center reticle · Place"
                if (!loopStarted) {
                    loopStarted = true
                    worker.scheduleWithFixedDelay({ tick() }, 0, 16, TimeUnit.MILLISECONDS)
                }
            } catch (error: Exception) {
                publishStatus("AR startup failed: ${error.javaClass.simpleName}: ${error.message}")
            }
        }
    }

    private fun createDetector(host: Activity) {
        if (modelAttempted) return
        modelAttempted = true
        try {
            detector = HandLandmarker.createFromOptions(host,
                HandLandmarker.HandLandmarkerOptions.builder()
                    .setBaseOptions(BaseOptions.builder().setModelAssetPath("hand_landmarker.task").build())
                    .setRunningMode(RunningMode.VIDEO)
                    .setNumHands(1)
                    .setMinHandDetectionConfidence(0.55f)
                    .setMinTrackingConfidence(0.55f)
                    .build())
        } catch (error: Exception) {
            handError = "Hand model failed: ${error.message}"
        }
    }

    private fun createEgl() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(eglDisplay != EGL14.EGL_NO_DISPLAY)
        check(EGL14.eglInitialize(eglDisplay, IntArray(2), 0, IntArray(2), 0))
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        val attributes = intArrayOf(EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT, EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_NONE)
        check(EGL14.eglChooseConfig(eglDisplay, attributes, 0, configs, 0, 1, count, 0))
        check(count[0] > 0)
        eglContext = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
        eglSurface = EGL14.eglCreatePbufferSurface(eglDisplay, configs[0],
            intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0)
        check(EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext))
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        cameraTexture = textures[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTexture)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    }

    private fun tick() {
        if (!resumed || !sessionRunning || session == null) return
        try {
            val current = session!!
            current.setDisplayGeometry(rotation, width, height)
            val frame = current.update()
            val tracking = frame.camera.trackingState == TrackingState.TRACKING
            var message = if (tracking) state else "Tracking paused · ${frame.camera.trackingFailureReason}"
            fun surfaceAt(x: Float, y: Float): HitResult? = if (!tracking) null else
                frame.hitTest(x * width, y * height).firstOrNull {
                    val plane = it.trackable
                    plane is Plane && plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                        plane.trackingState == TrackingState.TRACKING &&
                        (plane.isPoseInPolygon(it.hitPose) || plane.isPoseInExtents(it.hitPose))
                }
            val centerHit = if (anchor == null || placement != null) surfaceAt(0.5f, 0.5f) else null
            placement?.let { tap ->
                val hit = if (tap.first == 0.5f && tap.second == 0.5f) centerHit else surfaceAt(tap.first, tap.second)
                if (hit != null) {
                    anchor?.detach()
                    anchor = hit.createAnchor()
                    placement = null
                    state = "COURT PLACED / use HIT to serve"
                } else {
                    state = "Placement queued / scan a textured surface under the aim ring"
                }
                message = state
            }
            if (anchor == null && placement == null && tracking) {
                message = if (centerHit != null) "Surface ready / tap Place court" else "Scan a textured table slowly / aim at its surface"
            }
            val uv = FloatBuffer.allocate(8)
            frame.transformCoordinates2d(Coordinates2d.VIEW_NORMALIZED,
                FloatBuffer.wrap(floatArrayOf(0f,0f, 1f,0f, 0f,1f, 1f,1f)), Coordinates2d.IMAGE_NORMALIZED, uv)
            val now = SystemClock.uptimeMillis()
            val planeCount = current.getAllTrackables(Plane::class.java).count {
                it.trackingState == TrackingState.TRACKING && it.type == Plane.Type.HORIZONTAL_UPWARD_FACING && it.subsumedBy == null
            }
            val powerSaving = (activity?.getSystemService(Activity.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode == true
            if (anchor == null && powerSaving) message = "Turn off phone Power saving / then reopen AR"
            if (now - lastTrackingDiagnostic >= 3000) {
                lastTrackingDiagnostic = now
                Log.i("PocketAR", "tracking=${frame.camera.trackingState} reason=${frame.camera.trackingFailureReason} planes=$planeCount center_hit=${centerHit != null} anchored=${anchor != null} power_saving=$powerSaving")
            }
            if (frame.timestamp != lastCameraTimestamp && now - lastImageTime >= 15) {
                try {
                    frame.acquireCameraImage().use { image ->
                        cameraYuv = copyYuv(image)
                        jpegSequence = sequence
                        lastCameraTimestamp = frame.timestamp
                        lastImageTime = now
                        if (safePreview && now - lastPreviewRequest >= 60 && previewBusy.compareAndSet(false, true)) {
                            lastPreviewRequest = now
                            val packet = cameraYuv
                            val id = sequence
                            previewWorker.execute {
                                try {
                                    val header = ByteBuffer.wrap(packet).order(ByteOrder.LITTLE_ENDIAN)
                                    val w = header.int; val h = header.int
                                    val ySize = w*h; val uvSize = ySize/4
                                    val nv21 = ByteArray(ySize + uvSize*2)
                                    System.arraycopy(packet, 8, nv21, 0, ySize)
                                    for (i in 0 until uvSize) {
                                        nv21[ySize + i*2] = packet[8 + ySize + uvSize + i]
                                        nv21[ySize + i*2 + 1] = packet[8 + ySize + i]
                                    }
                                    val stream = ByteArrayOutputStream()
                                    check(YuvImage(nv21, ImageFormat.NV21, w, h, null).compressToJpeg(Rect(0, 0, w, h), 65, stream))
                                    jpeg = stream.toByteArray()
                                    previewSequence = id
                                    previewError = ""
                                } catch (error: Exception) {
                                    previewError = "Preview error: ${error.message}"
                                } finally { previewBusy.set(false) }
                            }
                        }
                        if (handsEnabled && now - lastHandRequest >= 180 && handBusy.compareAndSet(false, true)) {
                            lastHandRequest = now
                            val packet = cameraYuv
                            val generation = handGeneration
                            handWorker.execute {
                                try {
                                    val host = activity
                                    if (host != null && handsEnabled && generation == handGeneration) {
                                        createDetector(host)
                                        detectHand(packet, now, generation)
                                    }
                                } catch (error: Exception) {
                                    handError = "Hands unavailable: ${error.message}"
                                } finally { handBusy.set(false) }
                            }
                        }
                    }
                } catch (_: NotYetAvailableException) { }
            }
            val result = handResult
            hand = JSONArray()
            if (handsEnabled && result != null && now - result.timestamp < 750) {
                val imagePoints = FloatArray(42) { index -> result.points[(index / 2) * 3 + index % 2] }
                val viewPoints = FloatBuffer.allocate(42)
                frame.transformCoordinates2d(Coordinates2d.IMAGE_NORMALIZED, FloatBuffer.wrap(imagePoints), Coordinates2d.VIEW_NORMALIZED, viewPoints)
                val mapped = viewPoints.array()
                for (i in 0 until 21) hand.put(JSONArray(listOf(mapped[i*2], mapped[i*2+1], result.points[i*3+2])))
            }
            val projection = FloatArray(16)
            frame.camera.getProjectionMatrix(projection, 0, 0.02f, 100f)
            val payload = JSONObject().put("id", sequence++)
                .put("status", message).put("tracking", tracking)
                .put("pose", poseArray(frame.camera.displayOrientedPose))
                .put("projection", JSONArray(projection.toList()))
                .put("uv", JSONArray(uv.array().toList()))
                .put("jpeg_id", jpegSequence).put("hand", hand).put("pinch", false)
                .put("hand_id", result?.timestamp ?: -1L).put("hands_enabled", handsEnabled)
                .put("can_place", centerHit != null).put("pending_placement", placement != null)
                .put("plane_count", planeCount).put("power_saving", powerSaving)
                .put("camera_age_ms", if (lastImageTime == 0L) -1L else now - lastImageTime)
                .put("preview_id", previewSequence).put("preview_error", previewError)
                .put("camera_bytes", cameraYuv.size).put("preview_bytes", jpeg.size)
                .put("hand_error", handError)
            anchor?.let {
                payload.put("anchor", poseArray(it.pose))
                payload.put("anchor_tracking", it.trackingState == TrackingState.TRACKING)
            }
            frameJson = payload.toString()
        } catch (error: Exception) {
            publishStatus("AR frame error: ${error.javaClass.simpleName}: ${error.message}")
        }
    }

    // Copy Y/U/V bytes, not RGB or JPEG. Bulk row copies cover ordinary 640x480 images.
    // One immutable latest packet replaces its predecessor; there is no camera frame queue.
    private fun copyYuv(image: Image): ByteArray {
        val step = maxOf(1, (image.width + 639) / 640)
        val w = (image.width / step) and -2
        val h = (image.height / step) and -2
        val packet = ByteArray(8 + w*h*3/2)
        ByteBuffer.wrap(packet).order(ByteOrder.LITTLE_ENDIAN).putInt(w).putInt(h)
        var destination = 8
        for (channel in 0..2) {
            val plane = image.planes[channel]
            val buffer = plane.buffer.duplicate()
            val origin = buffer.position()
            val pw = if (channel == 0) w else w/2
            val ph = if (channel == 0) h else h/2
            for (row in 0 until ph) {
                val offset = origin + row * step * plane.rowStride
                if (step == 1 && plane.pixelStride == 1) {
                    buffer.position(offset)
                    buffer.get(packet, destination, pw)
                    destination += pw
                } else {
                    for (column in 0 until pw) packet[destination++] = buffer.get(offset + column * step * plane.pixelStride)
                }
            }
        }
        return packet
    }

    // Optional inference owns its bitmap/model on another worker and never blocks ARCore.
    private fun detectHand(packet: ByteArray, timestamp: Long, generation: Int) {
        val model = detector ?: return
        val header = ByteBuffer.wrap(packet).order(ByteOrder.LITTLE_ENDIAN)
        val sourceW = header.int; val sourceH = header.int
        val step = maxOf(1, sourceW / 320)
        val w = sourceW / step; val h = sourceH / step
        val pixels = IntArray(w*h)
        val ySize = sourceW * sourceH
        val uvSize = ySize / 4
        for (row in 0 until h) for (column in 0 until w) {
            val sx = column * step; val sy = row * step
            val luminance = (packet[8 + sy*sourceW + sx].toInt() and 255) - 16
            val chroma = (sy/2)*(sourceW/2) + sx/2
            val blue = (packet[8 + ySize + chroma].toInt() and 255) - 128
            val red = (packet[8 + ySize + uvSize + chroma].toInt() and 255) - 128
            val r = ((298*luminance + 409*red + 128) shr 8).coerceIn(0,255)
            val g = ((298*luminance - 100*blue - 208*red + 128) shr 8).coerceIn(0,255)
            val b = ((298*luminance + 516*blue + 128) shr 8).coerceIn(0,255)
            pixels[row*w+column] = (255 shl 24) or (r shl 16) or (g shl 8) or b
        }
        val bitmap = Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888)
        val mpImage = BitmapImageBuilder(bitmap).build()
        try {
            val result = model.detectForVideo(mpImage, timestamp)
            val landmarks = result.landmarks().firstOrNull()
            if (handsEnabled && generation == handGeneration) {
                handError = ""
                handResult = if (landmarks == null) null else HandResult(FloatArray(63) { index ->
                    val point = landmarks[index / 3]
                    when (index % 3) { 0 -> point.x(); 1 -> point.y(); else -> point.z() }
                }, timestamp)
            }
        } finally { mpImage.close(); bitmap.recycle() }
    }

    private fun poseArray(pose: Pose) = JSONArray(listOf(pose.tx(),pose.ty(),pose.tz(),pose.qx(),pose.qy(),pose.qz(),pose.qw()))

    override fun onMainDestroy() {
        resumed = false
        worker.execute {
            anchor?.detach()
            session?.close()
            if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                GLES20.glDeleteTextures(1, intArrayOf(cameraTexture), 0)
                EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                EGL14.eglDestroySurface(eglDisplay, eglSurface)
                EGL14.eglDestroyContext(eglDisplay, eglContext)
                EGL14.eglTerminate(eglDisplay)
            }
        }
        handsEnabled = false
        handGeneration++
        handWorker.execute { detector?.close() }
        handWorker.shutdown()
        safePreview = false
        previewWorker.shutdown()
        worker.shutdown()
        super.onMainDestroy()
    }
}
