# Installing FNV iOS

Use a release IPA and the matching PC game installation. The release contains the
iOS runtime; supply the executable, archives, other game content and movie files
from your own copy.

## Before starting

The app targets iOS 18 and later. Current phone testing uses LiveContainer and
the project owner's prepared game files. Use the
[official LiveContainer setup instructions](https://livecontainer.github.io/docs/installation/)
to prepare the launcher/signing side.

The runtime checks the executable's SHA-256 at launch. Use the supported executable
listed in the release notes. An executable mismatch needs matching game inputs or
a runtime built for that executable; renaming a different file does not change its
identity.

## Game folder

Import the IPA into LiveContainer and launch it once. Open **FNVGame's own data
container**, then prepare this layout:

```text
Documents/
└── FalloutNV/
    ├── FalloutNV.exe
    ├── Fallout_default.ini
    ├── Data/
    │   ├── FalloutNV.esm
    │   ├── ...game archives, DLC and other original files...
    │   └── Video/
    │       └── ...original .bik movies...
    ├── NativeMedia/
    │   └── FNVIntro.mp4
    └── UserDocuments/
        └── My Games/
            └── FalloutNV/
                ├── FALLOUT.INI
                ├── FalloutPrefs.ini
                └── Saves/
```

Copy the original configuration files alongside the executable too. Keep the
Data folder intact and use content from the same installation. The host handles
Windows path casing and prepares the display adapter identity needed at startup.

The IPA installer inbox in LiveContainer is separate from the game's data
container. Game content belongs in the folder shown above.

## Movies

Current builds play a locally prepared MP4 cache for each original movie. Prepare
H.264 video with AAC audio from your own original Bink file, keep its basename,
and place the MP4 under `NativeMedia`. The tested intro cache is `FNVIntro.mp4`.
Keep the original Bink files under `Data/Video`.

Missing caches and native decoding errors appear in `fnv.log`.

## Character shadows

The game reads these switches from **different files**:

| File under `UserDocuments/My Games/FalloutNV` | Section | Setting |
| --- | --- | --- |
| `FalloutPrefs.ini` | `[Display]` | `bDrawShadows=1` |
| `FALLOUT.INI` | `[Display]` | `bActorSelfShadowing=1` |

Close the game before editing. Back up both files and preserve their other
settings. A similarly named draw-shadow line in `FALLOUT.INI` is not the renderer
setting used for character shadows. The two settings above restored cast shadows
and self-shadowing on the same phone build without a renderer change.

The existing tested actor counts and 256-pixel shadow-map setting were retained
for that comparison. Higher quality settings have separate performance costs.

## Updating and saves

Back up the existing game data container. Update the existing FNVGame entry in
LiveContainer while keeping its data, then fully close and reopen LiveContainer.
Check that an existing save loads before continuing.

Your configuration, movie cache and saves remain in the data container. Touch
layouts and gyro preferences are stored separately as versioned app preferences;
updates migrate supported preferences while retaining custom layouts.

## First checks

Check menu music/clicks, intro picture/audio, movement and look, firing, Pip-Boy
navigation, an interior/exterior transition and saving/reloading. Compare the
release's remaining phone-test list with your result.

If an issue occurs, preserve `Documents/fnv.log` **before another launch**. Record
the build, location/save and exact action that caused it. Keep saves intact while
investigating.
