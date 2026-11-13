# Vendored from homebrew-core libidn2 (same source and SHA-256), built for the
# engine floor. SDK 15.4+ declares strchrnul, so gnulib's link test passes and
# lookup.c calls a weak import that is NULL below macOS 15.4. Telling gnulib the
# function is from a future OS makes it compile its own rpl_strchrnul.
class Libidn2 < Formula
  desc "International domain name library (IDNA2008, Punycode and TR46)"
  homepage "https://www.gnu.org/software/libidn/#libidn2"
  url "https://ftpmirror.gnu.org/libidn/libidn2-2.3.8.tar.gz"
  mirror "https://ftp.gnu.org/gnu/libidn/libidn2-2.3.8.tar.gz"
  mirror "http://ftp.gnu.org/gnu/libidn/libidn2-2.3.8.tar.gz"
  sha256 "f557911bf6171621e1f72ff35f5b1825bb35b52ed45325dcdee931e5d3c0787a"
  license all_of: [
    { any_of: ["GPL-2.0-or-later", "LGPL-3.0-or-later"] }, # lib
    { all_of: ["Unicode-TOU", "Unicode-DFS-2016"] }, # matching COPYING.unicode
    "GPL-3.0-or-later", # bin
    "LGPL-2.1-or-later", # parts of gnulib
    "FSFAP-no-warranty-disclaimer", # man3
  ]
  compatibility_version 1

  depends_on "pkgconf" => :build
  depends_on "libunistring"

  on_macos do
    depends_on "gettext"
  end

  deny_network_access!

  def install
    ENV["gl_cv_onwards_func_strchrnul"] = "future OS version"

    args = ["--disable-silent-rules", "--with-packager=Homebrew"]
    args << "--with-libintl-prefix=#{formula_opt_prefix("gettext")}" if OS.mac?

    system "./configure", *args, *std_configure_args
    system "make", "install"
  end

  test do
    ENV.delete("LC_CTYPE")
    ENV["CHARSET"] = "UTF-8"
    output = shell_output("#{bin}/idn2 räksmörgås.se")
    assert_equal "xn--rksmrgs-5wao1o.se", output.chomp
    output = shell_output("#{bin}/idn2 blåbærgrød.no")
    assert_equal "xn--blbrgrd-fxak7p.no", output.chomp
  end
end
