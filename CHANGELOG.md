# Changelog

All notable changes to LiteDisplay are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Eye comfort: a blue light filter by colour temperature (2700 K – 6500 K), per monitor or on all displays, all day
  or on a schedule. Gamma tables are restored when the app quits.
- Project documentation: English and Portuguese READMEs, contributing guide, security policy, code of conduct and
  issue and pull request templates.

### Changed

- The virtual display now delivers an exact 2:1 mirror of the panel at its native refresh rate.
- Turning the virtual display off relaunches the app so macOS releases the virtual display.

## [0.1.0] — 2026-10-22

Initial version.

### Added

- Sharpness per monitor: Standard (1x), Native HiDPI and Virtual display.
- HiDPI profile generation and installation for panels without HiDPI modes.
- Curated interface sizes, refresh rate selection and the full mode table.
- Profiles with one-click apply and "apply when the display connects".
- Stronger font smoothing, open at login and automatic restore after reconnect and wake.
- Menu bar menu and main window, in Portuguese (Brazil) and English.

[Unreleased]: https://github.com/renatoasterio/LiteDisplay/commits/main
[0.1.0]: https://github.com/renatoasterio/LiteDisplay/commit/27a73e4
