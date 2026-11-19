# Android build environment for Alder: JDK 17 (as in CI) plus the Android SDK. The source isn't baked in; it's
# mounted read-only at /src when the container runs, and build.sh puts the APKs in /utils/output.
FROM eclipse-temurin:17-jdk-jammy

ARG CMDLINE_TOOLS_VERSION=13114758
ARG ANDROID_PLATFORM=android-36
ARG BUILD_TOOLS_VERSION=36.0.0
# Builds run as a user with the host's UID/GID, so what lands in the mounted folders is the host user's.
ARG UID=1000
ARG GID=1000

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip wget \
    && rm -rf /var/lib/apt/lists/*

COPY docker.init.gradle.kts /usr/local/share/
COPY build.sh /usr/local/bin/build-apk
RUN chmod +x /usr/local/bin/build-apk

# The build user owns the SDK, so the Android Gradle plugin can still download a build-tools version it needs.
RUN groupadd -o -g ${GID} builder \
    && useradd -o -m -u ${UID} -g ${GID} builder \
    && mkdir -p ${ANDROID_HOME} \
    && chown builder:builder ${ANDROID_HOME}
USER builder

RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip -O /tmp/tools.zip \
    && unzip -q /tmp/tools.zip -d ${ANDROID_HOME}/cmdline-tools \
    && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm /tmp/tools.zip

# Licenses accepted here also let the Android Gradle plugin fetch any other build-tools version it asks for.
RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager "platforms;${ANDROID_PLATFORM}" "build-tools;${BUILD_TOOLS_VERSION}"

ENTRYPOINT ["build-apk"]
