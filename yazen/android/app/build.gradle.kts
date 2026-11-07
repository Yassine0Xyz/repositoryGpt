import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}
val productionBuild =
    providers.gradleProperty("production").map { it.toBoolean() }.getOrElse(false)
if (productionBuild) {
    if (!keyPropertiesFile.exists()) {
        throw GradleException(
            "Production builds require android/key.properties and a private keystore."
        )
    }
    val requiredSigningProperties =
        listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    val missingSigningProperties =
        requiredSigningProperties.filter { keyProperties.getProperty(it).isNullOrBlank() }
    if (missingSigningProperties.isNotEmpty()) {
        throw GradleException(
            "Production signing configuration is missing: ${missingSigningProperties.joinToString()}."
        )
    }
    val keystore = file(keyProperties.getProperty("storeFile"))
    if (!keystore.isFile) {
        throw GradleException("Production keystore does not exist: ${keystore.absolutePath}")
    }
}

val applicationProject = project
gradle.taskGraph.whenReady {
    val releaseTasks =
        allTasks.filter {
            it.project == applicationProject &&
                it.name.contains("Release", ignoreCase = true)
        }
    if (releaseTasks.isNotEmpty() && !productionBuild) {
        throw GradleException(
            "Release builds require production signing. Configure android/key.properties " +
                "and build with -Pproduction=true."
        )
    }
}

android {
    namespace = "com.yassine.yazen"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Keep this ID stable once the first public release is shipped.
        applicationId = "com.yassine.yazen"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. With split APKs, Flutter
        // adds the ABI suffix automatically.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += setOf("arm64-v8a")
        }
    }

    buildTypes {
        if (productionBuild) {
            signingConfigs.create("production") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.findByName("production")
        }
    }

    packaging {
        jniLibs {
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86_64/**")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
