# Artifact integrity and authenticity

## What the SHA-256 files prove, and what they don't

`images/SHA256SUMS` and `experimental/images/SHA256SUMS` list the SHA-256 hash of each binary. `sha256sum -c`, and the installer, check that your copy matches the hash **written in that file**.

| Question | Answered by SHA256SUMS? |
|---|---|
| Did the download, the copy or the SD card corrupt the file? | **Yes.** Any change to a byte changes the hash. |
| Is this the same file the team tested? | **Only if you trust the SHA256SUMS file itself.** It lives in the same repository as the binaries, so anyone who can change one can change both. |
| Who produced this file? | **No.** A hash carries no identity. |

So SHA256SUMS gives **integrity** against accidents. It does **not** give **authenticity**, meaning proof that the files came from the TALOS team unmodified. Nothing in this repository is signed. **No authenticity claim is made.**

Practical meaning today: get the repository only from the team's official location. Compare hashes with a second channel if you can, for example the hash posted in the team chat by the person who tested the image. Known values:

```text
29d926e476074f026c166d6032ad384d511e93dfaaa1c24b62fbed03549531f5  images/sel4.uImage            (verified baseline)
8aabe37f2891eb2aabe33783cdb10aad19ecb78640d534e81a5fb89834f349fb  boot/boot-sel4.scr            (verified baseline)
```

Experimental hashes are in `experimental/images/SHA256SUMS` and are expected to change while it is developed.

## Reproducibility as a partial substitute

The experimental image can be rebuilt by anyone from public pinned sources ([build-experimental.sh](../experimental/scripts/build-experimental.sh)). Two independent builds produced byte-identical output. A teammate who rebuilds and gets the same SHA-256 has independently checked that the published experimental binary matches the published sources and patches. That is stronger than trusting a hash file, but it relies on the pinned container image. The **verified baseline cannot be reproduced byte-for-byte**, because it embeds the original developer's paths.

## Future signed-release workflow (not implemented)

Proposed for the first public release. **No keys exist and nothing has been signed.**

1. **Choose who signs.** One or two named maintainers create signing keys on their own machines and never share them. Options include an OpenPGP key (`gpg --full-generate-key`), an SSH signing key (Git ≥ 2.34), or keyless Sigstore `cosign` using the maintainer's GitHub identity.
2. **Publish the public keys or identities** somewhere independent of the repository: the team's GitHub org profile, the course page, or a pinned team message. List their fingerprints in `docs/SIGNING_KEYS.md`.
3. **Tag releases signed:** `git tag -s v0.1.0 -m "TALOS seL4 bring-up v0.1.0"` (or `-s` with an SSH key and `gpg.format=ssh`).
4. **Sign the checksum files, not each binary:** e.g. `gpg --armor --detach-sign images/SHA256SUMS` → `SHA256SUMS.asc`, or `cosign sign-blob --bundle SHA256SUMS.bundle SHA256SUMS`. Upload the signature and the [corresponding-source archive](../THIRD_PARTY_NOTICES.md#gpl-source-availability) as release assets.
5. **Teammates verify:** import the maintainer key with the fingerprint from step 2, run `gpg --verify SHA256SUMS.asc SHA256SUMS` (or `cosign verify-blob …`), then `sha256sum -c SHA256SUMS`.
6. **Hardware-tested status** is recorded per release in [FIRMWARE_COMPATIBILITY.md](FIRMWARE_COMPATIBILITY.md). A signature says who published a file, not that it was tested.

Until this is in place, refer to the hashes as **checksums**, and avoid words like "signed", "authentic" or "official".
