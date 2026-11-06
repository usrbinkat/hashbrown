# AGENTS.md

## Header: this checkout is a long-lived fork, not an upstream branch

This clone is `rust-lang/hashbrown` with the fork `usrbinkat/hashbrown` as
`origin` and `rust-lang/hashbrown` as `upstream`. Fork work lives on
`feat/map-bucket-index`. The fork exists to give a bounded, resumable
consumer (dCBOR's bounded engine, through a forked Rust standard library)
access to the table's buckets that hashbrown does not expose today:
`num_buckets`, `get_bucket`, `next_full_bucket`, `bucket_group_width` and
`bucket_state` (`src/map_buckets.rs`, over `src/raw.rs`).

The workflow below is expected to run for months to years. Code written in
this fork is evidence-gathering code. It is not the upstream contribution.
The contribution is written later, by hand, from what production taught.

### The workflow, in order

1. **Fork.** Every change is made here, on the fork branch, as an ordinary
   commit with a full conventional-commit body. A change exists only once it
   is committed: no copy of an uncommitted working tree is ever taken into
   another repository.

2. **Develop.** Keep the fork's footprint minimal and named: new API in
   `src/map_buckets.rs`, the smallest possible hunks in `src/raw.rs` and
   `src/lib.rs`, everything else byte-identical to upstream. Every added
   function carries its tests in the same commit (differential tests against
   the per-index scan, tables with deleted buckets, unallocated and cleared
   tables, `HashMap` and `HashTable`). `cargo fmt --all -- --check` and the
   crate's own test suite pass before the commit.

3. **Vendor.** The Rust standard library fork (`usrbinkat/rust`, branch
   `feat/bounded-collection-access`, clone at
   `/workspace/usrbinkat/github.com/rust-lang/rust`) carries this crate as a
   path dependency at `library/hashbrown/`, wired by `library/std/Cargo.toml`
   and excluded from the library workspace in `library/Cargo.toml`. Vendoring
   is one mechanical commit in that repository and nothing else:
   - export the committed revision of this fork (`git archive <rev>`) over
     `library/hashbrown/`, without `ci/`, `.github/`, `Cross.toml` and
     `.gitignore`, and without the fork-only `AGENTS.md`, `flake.nix` and
     `flake.lock`, which are not crate sources;
   - regenerate `library/hashbrown/SHA256SUMS` and verify every file against
     it;
   - name the exact hashbrown revision in the commit message ("Sources match
     usrbinkat/hashbrown <rev>").

   std's own forwarders (`library/std/src/collections/hash/map/buckets.rs`,
   the re-exports in `hash/map.rs`) are a separate commit after the vendoring
   commit. They are std's API, not hashbrown's.

4. **Build.** Consumers pin revisions, never branches:
   - dCBOR's `Cargo.toml` pins this fork by `rev` (its `no_std` path) and
     its `flake.nix` reads that `rev` into the build configuration identity;
   - dCBOR's `flake.lock` pins the rust fork, whose `library/` replaces the
     toolchain's `rust-src` for `-Zbuild-std`.

   A new hashbrown revision reaches a build only after: this fork is
   committed and pushed, the rust fork re-vendors and is pushed, and the
   consumer moves both pins (`Cargo.toml` `rev`, `flake.lock`) and
   regenerates its lock files in one change.

5. **Test.** The consumer's gates run at the pinned identity: native tests in
   every feature domain, Miri under both aliasing models (hashbrown's group
   implementation is chosen by `cfg_select!` in `src/control/group/mod.rs`;
   at this fork's base, upstream f7c44c6, the SSE2, NEON and LSX arms are
   all `not(miri)`, so Miri runs the generic group and `bucket_group_width`
   and bucket windows differ there; upstream #755, "miri supports SSE and
   neon nowadays", lifts that for SSE2 and NEON once the fork moves past
   it), and the consumer's
   recorded evidence. A result is evidence only for the revisions it was
   produced at.

6. **Deploy.** Downstream services (kappa-registry, through dCBOR) take the
   fork only through those pinned revisions. Nothing deploys from a working
   tree.

7. **Operate and gather data from production.** The fork's purpose is to
   learn what the access API must be. Record, against the deployed
   revisions: which accessors are called and how often, the bucket and
   group-window distributions seen (vacant, deleted, full, partial last
   group), tables with heavy deletion, cost of the group scan against the
   per-index scan, any misuse the API allowed, and any accessor that proved
   unnecessary or insufficient. Keep that record with the revision it
   describes.

8. **Return, rewrite by hand, contribute upstream.** When production evidence
   has settled the API:
   - start from current `upstream/main`, not from this branch;
   - write the change by hand, smallest form the evidence supports, in
     upstream's style and conventions, with upstream-quality docs and tests;
   - contribute to `rust-lang/hashbrown` first, with the production evidence
     as the motivation;
   - after a hashbrown release carries it, the std side goes to
     `rust-lang/rust` as its own change: a version bump of the crates.io
     dependency plus std's forwarders. Upstream std does not vendor hashbrown;
     the vendored copy under `library/hashbrown/` is fork scaffolding and is
     never part of an upstream contribution;
   - once upstream ships each piece, delete the fork's copy of it (this
     branch's commit, the rust fork's vendored copy and forwarder, the
     consumer's pins) in the same change that adopts the upstream version.

### Standing rules for agents in this checkout

- Do not push, rebase, reset or force anything without the operator's
  instruction. The operator commits.
- Do not copy files from this working tree into the rust fork. Vendoring
  takes a committed revision only (step 3).
- Keep upstream files byte-identical unless the change requires otherwise,
  including rustfmt ordering under the crate's edition-2024 style.
- The fork branches from `upstream/main` past the last release while the
  crate still declares that release's version. Treat the revision, not the
  version string, as the identity, and say so wherever a version is pinned.
- Read a file in full before editing it.
