# Building the APK with Docker

Everything here runs from the repository root. Nothing needs to be installed on the host but Docker with Compose v2.

| Folder in `utils/` | What it holds | In git |
|---|---|---|
| `output/` | the built APKs | no |
| `cache/` | Gradle, dependencies, build output, the debug key. Delete it to start clean (~1–2 GB) | no |
| `keys/` | your release key (optional) | no |

The container runs as UID:GID 1000:1000. If `id -u` / `id -g` say otherwise, put
`HOST_UID=$(id -u) HOST_GID=$(id -g)` in front of the commands below and add `--build` once.

## Debug build

```bash
docker compose -f utils/docker-compose.yaml run --rm apk
```

`utils/output/app-debug.apk`: quick to build, not optimised. Every debug build is signed with the same debug key
(kept in `utils/cache/android/`), so each one installs over the last.

## Release build

```bash
GRADLE_TASK=assembleRelease docker compose -f utils/docker-compose.yaml run --rm apk
```

`utils/output/app-release.apk`: minified and shrunk by R8, which makes it smaller and faster. It's signed with:

- your release key, if `utils/keys/release.jks` exists (below);
- otherwise the debug key. Gradle warns `keystore.properties not found`, and the build logs
  `No /utils/keys/release.jks: signing with the debug key`. That APK installs fine, and installs over a debug build.

## Overrides

Set in front of the command, e.g. `APP_NAME="Alder (Docker)" GRADLE_TASK=assembleRelease docker compose -f
utils/docker-compose.yaml run --rm apk`, or kept in `utils/.env`: copy `utils/.env.example`, which lists them all.
Compose reads `utils/.env` on every run (it's git-ignored); a variable set in the shell wins over it.

| Variable | Default | What it changes |
|---|---|---|
| `GRADLE_TASK` | `assembleDebug` | The Gradle tasks, space-separated. `assembleRelease` for a release build; `"testDebugUnitTest assembleRelease"` runs the unit tests first, as CI does |
| `APP_ID` | `dev.alder.dockerbuilt` | The application ID. `APP_ID=` (empty) builds the official `dev.alder` |
| `APP_NAME` | unset: "Alder" | The name on the TV's home screen and app list |
| `HOST_UID`, `HOST_GID` | `1000`, `1000` | The user the build runs as, which owns everything in `output/` and `cache/`. Set them to `$(id -u)` / `$(id -g)` if those differ. Needs `--build` once |
| `ANDROID_PLATFORM`, `BUILD_TOOLS_VERSION`, `CMDLINE_TOOLS_VERSION` | `android-36`, `36.0.0`, `13114758` | The SDK in the image, for when the Android Gradle plugin asks for other versions. Needs `--build` once |
| `SIGNING_STORE_PASSWORD`, `SIGNING_KEY_ALIAS`, `SIGNING_KEY_PASSWORD`, `SIGNING_KEYSTORE` | none, `alder`, the store password, `/utils/keys/release.jks` | The release key: see [Signing](#signing-with-your-own-key-optional) |

"Needs `--build` once": they change the image, so add `--build` to the next `run` (`... run --rm --build apk`).

### `APP_ID`

The default makes Docker builds install **beside** the official app instead of replacing it: no uninstall, no key
clash, separate data (profiles and the Stremio sign-in are set up again). Both show as "Alder" on the TV unless
`APP_NAME` is set.

Changing the ID makes a different app to Android: data doesn't carry over, and the old one stays until uninstalled.

The in-app updater downloads the official release, whose ID (`dev.alder`) and key differ: on a Docker build it can
offer an update that then fails to install. Update by building and installing again instead.

### `APP_NAME`

Used in every language. Any characters work (quotes, `&`, …): the build escapes them. Only the name changes: the
banner picture on the TV home screen still shows the Alder logo. The launcher may keep showing the old name for a
moment after an update.

## Signing with your own key (optional)

### 1. Make the key (once)

The image has `keytool`, so no Java is needed on the host:

```bash
mkdir -p utils/keys
docker compose -f utils/docker-compose.yaml run --rm --entrypoint keytool apk \
    -genkeypair -v \
    -keystore /utils/keys/release.jks \
    -alias alder \
    -keyalg RSA -keysize 4096 \
    -validity 10000
```

It asks for a password and a name ("first and last name", organisation, …: any values work, they're only shown in
the certificate). The keystore is PKCS12, so the key's password is the same as the store's.

### 2. Give the build its password

In `utils/.env` (copied from `utils/.env.example`):

```bash
SIGNING_STORE_PASSWORD=the-password-you-chose
# Only when they differ from the defaults:
# SIGNING_KEY_ALIAS=alder
# SIGNING_KEY_PASSWORD=same-as-store-for-pkcs12
# SIGNING_KEYSTORE=/utils/keys/release.jks
```

```bash
chmod 600 utils/.env utils/keys/release.jks
```

### 3. Build

The same release command as above. The log shows `Signing with /utils/keys/release.jks, key alder`. Debug builds
keep the debug key either way.

To check the signature: `docker compose -f utils/docker-compose.yaml run --rm --entrypoint keytool apk -printcert
-jarfile /utils/output/app-release.apk`.

### Keep the key safe

- **Back up `release.jks` and its password somewhere outside this machine.** Android only installs an update over
  an app signed with the same key. Lose it, and every device must uninstall the app (losing its data, including the
  Stremio sign-in) before a newer build installs.
- An APK signed with your key can't update one with the same application ID signed with another key (e.g. the
  debug key). Switching means uninstalling first, once.
- `utils/keys/` is git-ignored. Don't move the key into the repository.

## Installing on an Android TV

1. On the TV: Settings → Device Preferences → About → press **Build** 7 times. Then Settings → Device Preferences →
   Developer options → turn on **Network debugging** (on SHIELD; "USB debugging" elsewhere) and note the IP address.
2. On the computer, with `adb` (Android platform tools, e.g. `apt install adb`):

   ```bash
   adb connect <tv-ip>:5555        # accept the prompt on the TV the first time
   adb install -r utils/output/app-release.apk
   ```

   `-r` keeps the app's data. `INSTALL_FAILED_UPDATE_INCOMPATIBLE` means the installed copy has another key:
   `adb uninstall dev.alder.dockerbuilt` (or the `APP_ID` used) first, which clears its data.
