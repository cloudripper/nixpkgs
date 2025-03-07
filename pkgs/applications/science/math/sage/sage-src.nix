{ stdenv
, lib
, fetchFromGitHub
, fetchpatch
, fetchurl
}:

# This file is responsible for fetching the sage source and adding necessary patches.
# It does not actually build anything, it just copies the patched sources to $out.
# This is done because multiple derivations rely on these sources and they should
# all get the same sources with the same patches applied.

stdenv.mkDerivation rec {
  version = "10.4";
  pname = "sage-src";

  src = fetchFromGitHub {
    owner = "sagemath";
    repo = "sage";
    rev = version;
    hash = "sha256-BDO00ZSm5lnjEuA56VsY/FZyAhoG1hkFxdIlTtBZVBA=";
  };

  # contains essential files (e.g., setup.cfg) generated by the bootstrap script.
  # TODO: investigate https://github.com/sagemath/sage/pull/35950
  configure-src = fetchurl {
    # the hash below is the tagged commit's _parent_. it can also be found by looking for
    # the "configure" asset at https://github.com/sagemath/sage/releases/tag/${version}
    url = "mirror://sageupstream/configure/configure-3c279ec5712e0fa35c5733e03e010970727d7189.tar.gz";
    hash = "sha256-3bRlgIUSIq9tDzvI+ZfEd5LMy1qHXdItEwu1say4cx4=";
  };

  # Patches needed because of particularities of nix or the way this is packaged.
  # The goal is to upstream all of them and get rid of this list.
  nixPatches = [
    # Parallelize docubuild using subprocesses, fixing an isolation issue. See
    # https://groups.google.com/forum/#!topic/sage-packaging/YGOm8tkADrE
    ./patches/sphinx-docbuild-subprocesses.patch

    # After updating smypow to (https://github.com/sagemath/sage/issues/3360)
    # we can now set the cache dir to be within the .sage directory. This is
    # not strictly necessary, but keeps us from littering in the user's HOME.
    ./patches/sympow-cache.patch
  ] ++ lib.optionals (stdenv.cc.isClang) [
    # https://github.com/NixOS/nixpkgs/pull/264126
    # Dead links in python sysconfig cause LLVM linker warnings, leading to cython doctest failures.
    ./patches/silence-linker.patch

    # Stack overflows during doctests; this does not change functionality.
    ./patches/disable-singular-doctest.patch
  ];

  # Since sage unfortunately does not release bugfix releases, packagers must
  # fix those bugs themselves. This is for critical bugfixes, where "critical"
  # == "causes (transient) doctest failures / somebody complained".
  bugfixPatches = [
    # https://github.com/sagemath/sage/pull/38628, landed in 10.5.beta4
    (fetchpatch {
      name = "pari-stack-cysignals-exception.patch";
      url = "https://github.com/sagemath/sage/commit/4a9c985b769b1209902c970ade1892f18ab48c10.diff";
      hash = "sha256-S6NdonB7needJlQdx52Huk34Q8/vG3nyGicA5JpsdWc=";
    })

    # https://github.com/sagemath/sage/pull/38851, landed in 10.5.beta8
    (fetchpatch {
      name = "glpk-aarch64-hang-workaround.patch";
      url = "https://github.com/sagemath/sage/commit/ce4a78dcb4178f85273619cea076c97345977ee1.diff";
      hash = "sha256-TibTx5llkXjkEZB/MDy4hfGwKBmwtitEpWP6K/ykke0=";
    })

    # compile libs/gap/element.pyx with -O1
    # a more conservative version of https://github.com/sagemath/sage/pull/37951
    ./patches/gap-element-crash.patch
  ];

  # Patches needed because of package updates. We could just pin the versions of
  # dependencies, but that would lead to rebuilds, confusion and the burdons of
  # maintaining multiple versions of dependencies. Instead we try to make sage
  # compatible with never dependency versions when possible. All these changes
  # should come from or be proposed to upstream. This list will probably never
  # be empty since dependencies update all the time.
  packageUpgradePatches = [
    # https://github.com/sagemath/sage/pull/38500, landed in 10.5.beta3
    (fetchpatch {
      name = "cython-3.0.11-upgrade.patch";
      url = "https://patch-diff.githubusercontent.com/raw/sagemath/sage/pull/38500.diff";
      hash = "sha256-ePfH3Gy1T0UfpoVd3EZowCfy88CbE+yE2MV2itWthsA=";
    })

    # https://github.com/sagemath/sage/pull/36641, landed in 10.5.beta3
    (fetchpatch {
      name = "sympy-1.13.2-update.patch";
      url = "https://github.com/sagemath/sage/commit/100189fa62f9a40e7aa0d856615366ea99b87aff.diff";
      sha256 = "sha256-uWr3I15WByQYGVxbJFqG4zUJ7c7+4rjkcgwkAT85O7w=";
    })

    # https://github.com/sagemath/sage/pull/38250, landed in 10.5.beta0
    (fetchpatch {
      name = "numpy-2.0-compat.patch";
      url = "https://github.com/sagemath/sage/commit/0962e0bcb159d342e7c7d83557a71e7b670fff47.diff";
      sha256 = "sha256-4SBhgPgT9VsBxcBH8+T5uYtWzYP5tZi9+iKOG55hWgI=";
    })
  ];

  patches = nixPatches ++ bugfixPatches ++ packageUpgradePatches;

  # do not create .orig backup files if patch applies with fuzz
  patchFlags = [ "--no-backup-if-mismatch" "-p1" ];

  postPatch = ''
    # Make sure sage can at least be imported without setting any environment
    # variables. It won't be close to feature complete though.
    sed -i \
      "s|var(\"SAGE_ROOT\".*|var(\"SAGE_ROOT\", \"$out\")|" \
      src/sage/env.py

    # sage --docbuild unsets JUPYTER_PATH, which breaks our docbuilding
    # https://trac.sagemath.org/ticket/33650#comment:32
    sed -i "/export JUPYTER_PATH/d" src/bin/sage
  '';

  buildPhase = "# do nothing";

  installPhase = ''
    cp -r . "$out"
    tar xzf ${configure-src} -C "$out"
    rm "$out/configure"
  '';
}
