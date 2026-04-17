# Release Guide (DMG + Homebrew Cask)

## 1) Build DMG locally

Prerequisites:
1. Install `create-dmg`:
   - `brew install create-dmg`
2. Have Xcode command line tools available.
3. Optional (recommended for distribution): set signing/notarization env vars:
   - `DEVELOPER_ID_APPLICATION`
   - `APPLE_ID`
   - `APPLE_TEAM_ID`
   - `APPLE_APP_SPECIFIC_PASSWORD`

Build artifacts:
1. Run:
   - `scripts/release/build_dmg.sh 0.9`
2. Output files:
   - `dist/Kotaeba-0.9.dmg`
   - `dist/Kotaeba-0.9.sha256.txt`

## 2) Publish GitHub release with DMG assets

1. Authenticate GitHub CLI:
   - `gh auth login -h github.com`
2. Publish:
   - `scripts/release/publish_release.sh 0.9 --repo ratniel/kotaeba`
3. This creates (or updates) tag/release `v0.9` and uploads:
   - `Kotaeba-0.9.dmg`
   - `Kotaeba-0.9.sha256.txt`

## 3) CI option (tag-driven release)

The workflow at `/Users/ratniel/kotaeba/.github/workflows/release-dmg.yml` builds, signs, notarizes, and publishes on tag push (`v*`) once required secrets are configured.

## 4) Where should `kotaeba.rb` live?

Short answer: use a separate tap repo for public distribution.

1. Recommended: separate tap repository (example: `ratniel/homebrew-tap`) and place file at `Casks/kotaeba.rb`.
2. Possible but less clean: keep `Casks/kotaeba.rb` in this same app repo and tap by full URL. This works, but mixes app source and package-manager metadata.
3. For submitting to Homebrew core cask, you do not keep the file in your repo; you open a PR to `Homebrew/homebrew-cask`.

Cask template:

```ruby
cask "kotaeba" do
  version "0.9"
  sha256 "<SHA256_FROM_RELEASE_FILE>"

  url "https://github.com/ratniel/kotaeba/releases/download/v#{version}/Kotaeba-#{version}.dmg"
  name "Kotaeba"
  desc "Speech-to-text menubar app for macOS"
  homepage "https://github.com/ratniel/kotaeba"

  app "KotaebaApp.app"
end
```

## 5) Quick release checklist

1. Build and smoke test app locally.
2. Run `scripts/release/build_dmg.sh <version>`.
3. Run `scripts/release/publish_release.sh <version> --repo ratniel/kotaeba`.
4. Test installing DMG on a clean macOS user account.
5. Update cask (`version`, `sha256`, `url`) in your tap repo.
6. Test with `brew install --cask kotaeba`.
