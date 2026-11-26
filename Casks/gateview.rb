# Homebrew cask for GateView.
#
# To submit: fork homebrew/homebrew-cask, copy this file as Casks/gateview.rb, replace
# SHA256_HERE with `shasum -a 256 dist/GateView-<version>-universal.dmg` from the release,
# then open a PR (see https://docs.brew.sh/Cask-Cookbook). Bump `version` and `sha256` here
# on every release so users can also install it from a local tap:
#   brew tap-new <user>/gateview && brew tap <user>/gateview && brew install --cask gateview
cask "gateview" do
  version "2.3.1"
  sha256 "9152a6932dd172e4ca96707750f4b5a318aca4da5f0ea96f0a31b95d8c19119d"

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
