allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        // Android app and library modules only. `CommonExtension` is AGP's public
        // DSL interface; the `BaseExtension` type used here before is deprecated in
        // AGP 9 and is not available under its new DSL, which this build now uses.
        (extensions.findByName("android") as? com.android.build.api.dsl.CommonExtension)?.apply {
            // Force compileSdk to 36 (required by image_picker → androidx.activity:1.12.4+)
            compileSdk = 36
        }
    }
}

// Evaluate the app first: android_file_picker reads Flutter's `flutter`
// extension while it is configured, and the app is what adds it.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
