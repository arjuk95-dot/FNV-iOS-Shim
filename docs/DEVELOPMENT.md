# Building and testing

The repository landing page is for players. This page covers the source build
entry points; the [archived developer README](ARCHIVED-README.md) retains the
earlier analysis recipes and historical investigation notes.

## Reproduce a release

Check out the release's source tag so the runtime, input policy and packaging tools
match its IPA. Private executable-derived inputs and game content stay outside the
source repository. Use the exact executable supported by that release.

An Apple build host with Xcode and an iPhoneOS SDK is required. The compiler targets
ARM64 iOS 18 even when the build host is an Intel Mac.

```sh
python3 tools/build_codecs.py ios --out "$WORK/codecs-ios"
python3 tools/build.py game \
  --generated "$WORK/generated" \
  --exe "$EXE" \
  --codec-prefix "$WORK/codecs-ios/prefix" \
  --hybrid-input "$CAMERA_PROFILE_JSON"
python3 tools/verify_ipa.py build/FNVGame.ipa --target game
```

Full-game translated C and a verified camera profile must already exist. The
[maintained translation recipe](../tools/translate/README.md) describes the analysis
requirements. Generated units are compiled into the runtime; the matching original
executable is also checked when the app launches.

The build creates the iOS host, compiles its icon asset catalog, links the game and
packages an unsigned IPA. Pinned native Ogg/Vorbis inputs and their bundled notices
are validated. Movie caches and game archives are supplied separately.

## Public hardware probe

```sh
python3 tools/build.py probe
```

This builds the separate Metal/input probe using public source only. A successful
probe is a hardware check; game startup, content loading and gameplay need the full
game target and matching private inputs.

## Checks

```sh
bash tests/run.sh
python3 tests/touch_controls_test.py
python3 tests/input_display_test.py
```

The media/input Actions workflow also runs native audio callback/lifetime tests,
archived WAV I/O, movie decoding and real Metal pixel checks, preference migration,
Pip-Boy/input transitions and actual iPhoneOS compilation. Tests use authored
fixtures. Touch feel, sensors, physical controllers and gameplay acceptance still
need a phone run.

Release notes record the source revision, executable identity, IPA checksum,
validation results and remaining device checks. Keep private build-input uploads
temporary, and preserve the user's game files, saves and preferences during updates.
