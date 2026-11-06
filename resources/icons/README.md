# App icon

`Rewarp.png` is an edge-to-edge, opaque version of the artwork from the
[shared reference](https://chatgpt.com/s/m_6aed4ef3cec48191a206eb7c6e2dfbf9).
The dark background fills the square canvas, with the chevron and underscore
enlarged together. The previous transparent margin and rounded tile exposed a
pale frame when Finder applied its macOS Tahoe icon treatment. Keep this source
full-bleed; Tahoe supplies the outer corner mask. Earlier macOS versions display
the square artwork directly.

The artwork was edited with the built-in imagegen tool. The edit requested an
opaque, full-bleed square with no outer margin, frame or baked-in rounded corners,
preserving the original blue folded chevron, white underscore and their relative
positions.

`Rewarp.icns` contains the standard macOS sizes from 16 through 512 points at
both 1x and 2x resolution, up to 1024 pixels. It is checked in so ordinary builds
do not need to regenerate it. To rebuild it on macOS after replacing the source:

```sh
make icons
```

The bundle declares this icon for Finder, the Dock, the app switcher and the
standard About panel. Unbundled development launches load the same file from
the repository.
