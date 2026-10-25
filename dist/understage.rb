class Understage < Formula
  desc "Instant Actions CLI for macOS Finder (part of Understage)"
  homepage "https://github.com/qydxyx/understage-macos"
  url "https://github.com/qydxyx/understage-macos/archive/refs/tags/v0.1.0.tar.gz"
  license "MIT"
  depends_on :macos => :sequoia
  depends_on :xcode => ["16.0", :build]

  def install
    system "make", "cli"
    bin.install ".derived/Build/Products/Release/understage"
  end

  test do
    assert_match "Instant Actions", shell_output("#{bin}/understage --help")
  end
end
