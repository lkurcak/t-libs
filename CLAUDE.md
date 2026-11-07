# t-libs

Libraries written in T (the repo was t-hashmap until 2026-11-07). Each package is
a directory with a `lib.t` (dependents name it by `subdirectory`, t
0.66.0+): the hash map in `hashmap/`, with `grid/` and `graph/` to come
beside it. There's no workspace concept yet: `tests/run.sh` loops over
`*/lib.t`. The hash map is a library written in T, the language at `~/repos/tooling/t-lang`
(GitHub: lkurcak/t-lang). Like tcalc (`~/repos/tooling/tcalc`), its real
purpose is to find out what using T is like, here for a library: writing
an interface, separate checking, a user-implemented `Hash` trait, the
orphan rule, API evolution. tcalc depends on it, by git rev, for its
variables.

- `hashmap/lib.t` is the package's root (`Map`), `hashmap/hash.t` the
  `hash` module (`Hash`, `Hasher`, `Probe`).
- `tests/run.sh` runs what CI runs, for every package; each package's
  `tests/lib.t` is a dependent package of `#[test]`s (`t test
  hashmap/tests/lib.t`).
- CI pins a `t` release (`t-version` + `t-sha256` in .github/workflows/t.yml, which calls forge's shared t-ci.yml); bump both
  after a t-lang release, from `gh release view vX.Y.Z -R lkurcak/t-lang
  --json assets`.
- `FRICTION.md` is the friction log: label entries gap / by design /
  unsure / works, with the code that hit them. It's evidence for t-lang
  steps, planned in t-lang, not here.
- `git` over ssh doesn't work in Claude's shell: push and fetch through
  `origin` with `-c url."https://github.com/".insteadOf=git@github.com:
  -c credential.helper='!gh auth git-credential'`.
