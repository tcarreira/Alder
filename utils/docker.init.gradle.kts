// Gradle setup for Docker builds (build.sh passes it with --init-script).
val appId = System.getenv("APP_ID").orEmpty()
// A res folder with only app_name in it, written by build.sh when APP_NAME is set.
val appNameRes = System.getenv("APP_NAME_RES").orEmpty()

allprojects {
    // Keeps every project's build/ out of the source tree, which is mounted read-only at /src.
    layout.buildDirectory.set(file("/utils/cache/build/$name"))

    // Changed in finalizeDsl: after build.gradle.kts has set its own values, before the Android plugin locks them. The
    // plugin's types aren't on an init script's classpath, hence the Groovy-style calls.
    if (appId.isNotEmpty() || appNameRes.isNotEmpty()) pluginManager.withPlugin("com.android.application") {
        extensions.getByName("androidComponents").withGroovyBuilder {
            "finalizeDsl"(object : Action<Any> {
                override fun execute(android: Any) {
                    // APP_ID replaces applicationId, so this build installs beside the official app instead of over it.
                    if (appId.isNotEmpty()) android.withGroovyBuilder {
                        getProperty("defaultConfig").withGroovyBuilder { setProperty("applicationId", appId) }
                    }
                    // APP_NAME: a build type's res folders outrank main's, so its app_name wins over strings.xml's.
                    if (appNameRes.isNotEmpty()) {
                        val buildTypes = android.withGroovyBuilder { getProperty("buildTypes") } as NamedDomainObjectCollection<*>
                        val sourceSets = android.withGroovyBuilder { getProperty("sourceSets") } as NamedDomainObjectCollection<*>
                        for (type in buildTypes.names) sourceSets.getByName(type).withGroovyBuilder {
                            getProperty("res").withGroovyBuilder { "srcDir"(appNameRes) }
                        }
                    }
                }
            })
        }
    }
}
