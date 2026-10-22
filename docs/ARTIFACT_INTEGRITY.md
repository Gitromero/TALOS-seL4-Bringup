# Artifact integrity and authenticity

## What the SHA-256 files prove, and what they don't

`images/SHA256SUMS` lists the SHA-256 hash of each binary. `sha256sum -c`, and the installer, check that your copy matches the hash **written in that file**.

| Question | Answered by SHA256SUMS? |
|---|---|
| Did the download, the copy or the SD card corrupt the file? | **Yes.** Any change to a byte changes the hash. |
| Is this the same file the team tested? | **Only if you trust the SHA256SUMS file itself.** It lives in the same repository as the binaries, so anyone who can change one can change both. |
| Who produced this file? | **No.** A hash carries no identity. |

So SHA256SUMS gives **integrity** against accidents. It does **not** give **authenticity**, meaning proof that the files came from the TALOS team unmodified. Nothing in this repository is signed. **No authenticity claim is made.**

Practical meaning today: get the repository only from the team's official location. Compare hashes with a second channel if you can, for example the hash posted in the team chat by the person who tested the image. Known values:

```text
2c98607641ea3418f39e3b4396c9fd97afdd982b151a3b7a783408a41b887d27  images/sel4test.uImage   (booted on the board: 118/49)
a5ab05d40c7d918150ded509a8a20ad91d39441d89772f6e992668160bcc6242  boot/boot-auto.scr
322ee52106fd2067a0b45932501d46d277018dbe46706ef6e608b41955db0060  boot/boot-linux.scr
```

The Rust root task image is not shipped; build it yourself ([rust-root-task/](../rust-root-task/README.md)).

## Reproducibility as a partial substitute

`images/sel4test.uImage` and `boot/boot-auto.scr` can be rebuilt by anyone from public pinned sources ([build-sel4test.sh](../scripts/build-sel4test.sh)). Three independent builds of the image (two on 2026-10-20, one on 2026-10-21) were byte-identical, and the 2026-10-21 build also reproduced the current `boot-auto.scr`. A teammate who rebuilds and gets the same SHA-256 has independently checked that the published binary matches the published sources and patches. That is stronger than trusting a hash file, but it relies on the pinned container image.

## Future signed-release workflow (not implemented)

Proposed for the first public release. **No keys exist and nothing has been signed.**

1. **Choose who signs.** One or two named maintainers create signing keys on their own machines and never share them. Options include an OpenPGP key (`gpg --full-generate-key`), an SSH signing key (Git ≥ 2.34), or keyless Sigstore `cosign` using the maintainer's GitHub identity.
2. **Publish the public keys or identities** somewhere independent of the repository: the team's GitHub org profile, the course page, or a pinned team message. List their fingerprints in `docs/SIGNING_KEYS.md`.
3. **Tag releases signed:** `git tag -s v0.1.0 -m "TALOS seL4 bring-up v0.1.0"` (or `-s` with an SSH key and `gpg.format=ssh`).
4. **Sign the checksum files, not each binary:** e.g. `gpg --armor --detach-sign images/SHA256SUMS` → `SHA256SUMS.asc`, or `cosign sign-blob --bundle SHA256SUMS.bundle SHA256SUMS`. Upload the signature and the [corresponding-source archive](../THIRD_PARTY_NOTICES.md#gpl-source-availability) as release assets.
5. **Teammates verify:** import the maintainer key with the fingerprint from step 2, run `gpg --verify SHA256SUMS.asc SHA256SUMS` (or `cosign verify-blob …`), then `sha256sum -c SHA256SUMS`.
6. **Hardware-tested status** is recorded per release in [FIRMWARE_COMPATIBILITY.md](FIRMWARE_COMPATIBILITY.md). A signature says who published a file, not that it was tested.

Until this is in place, refer to the hashes as **checksums**, and avoid words like "signed", "authentic" or "official".
