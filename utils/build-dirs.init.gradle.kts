// Keeps every project's build/ out of the source tree, which is mounted read-only at /src.
allprojects {
    layout.buildDirectory.set(file("/utils/cache/build/$name"))
}
