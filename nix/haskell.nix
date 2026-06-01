# Haskell package set overrides for ghc948.
#
# nixpkgs 24.11 ships sbv >= 10.2 so no overrides are currently needed.
#
# If a dependency needs pinning, uncomment and adapt the example below:
#
#   hfinal: hprev: {
#     sbv = hprev.callHackage "sbv" "10.2" {};
#   }
#
# The function signature must always be `hfinal: hprev: { ... }`.
hfinal: hprev: {}
