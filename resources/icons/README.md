# App icon

`Rewarp.png` is the original artwork from the
[shared reference](https://chatgpt.com/s/m_6aed4ef3cec48191a206eb7c6e2dfbf9),
with its transparent background preserved.

`Rewarp.icns` contains the standard macOS sizes from 16 through 512 points at
both 1x and 2x resolution, up to 1024 pixels. It is checked in so ordinary builds
do not need to regenerate it. To rebuild it on macOS after replacing the source:

```sh
make icons
```

The bundle declares this icon for Finder, the Dock, the app switcher and the
standard About panel. Unbundled development launches load the same file from
the repository.
