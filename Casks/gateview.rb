# Homebrew cask for GateView.
#
# To submit: fork homebrew/homebrew-cask, copy this file as Casks/gateview.rb, replace
# SHA256_HERE with `shasum -a 256 dist/GateView-<version>-universal.dmg` from the release,
# then open a PR (see https://docs.brew.sh/Cask-Cookbook). Bump `version` and `sha256` here
# on every release so users can also install it from a local tap:
#   brew tap-new <user>/gateview && brew tap <user>/gateview && brew install --cask gateview
cask "gateview" do
  version "2.3.0"
  sha256 "c8ee6c0c8de0a89402aa1049a73697f91fdfdc647ddffcb05ed70e9cd8fc5e5b"

  url "https://github.com/fk0u/gateview/releases/download/v#{version}/GateView-#{version}-universal.dmg"
  name "GateView"
  desc "Ambient desktop dashboard that lives on the macOS wallpaper"
  homepage "https://github.com/fk0u/gateview"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "GateView.app"

  zap trash: "~/.config/gateview"
end
