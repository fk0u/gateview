# Homebrew cask for GateView.
#
# To submit: fork homebrew/homebrew-cask, copy this file as Casks/gateview.rb, replace
# SHA256_HERE with `shasum -a 256 dist/GateView-<version>-universal.dmg` from the release,
# then open a PR (see https://docs.brew.sh/Cask-Cookbook). Bump `version` and `sha256` here
# on every release so users can also install it from a local tap:
#   brew tap-new <user>/gateview && brew tap <user>/gateview && brew install --cask gateview
cask "gateview" do
  version "2.4.0"
  sha256 "1aa76801f14e87306c1f5e2237d47586a9b30d4548d2dd7e499b596936da0d85"

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
