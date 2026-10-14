plugins { id("com.android.library"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "org.pocketterrain.ar"
    compileSdk = 35
    defaultConfig { minSdk = 26 }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies {
    compileOnly("org.godotengine:godot:4.5.1.stable")
    implementation("com.google.ar:core:1.48.0")
    implementation("com.google.mediapipe:tasks-vision:0.10.21")
}
