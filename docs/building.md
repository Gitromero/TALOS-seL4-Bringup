# Building and releasing

Teammates who only boot seL4 **don't need this page**: the shipped image is ready to use. It covers rebuilding that image byte-for-byte from public sources, running the offline tests, and the checks that go with publishing binaries. Where each shipped file came from is recorded in [provenance.md](provenance.md).

## Prerequisites

- Linux x86-64 with Docker Engine, and your user in the `docker` group (`docker run hello-world` works without `sudo`).
- `git` and Google's `repo` launcher (`sudo apt install repo` on Ubuntu/Mint, or see the [repo docs](https://gerrit.googlesource.com/git-repo)).
- Network access to github.com and Docker Hub, and about 12 GB of free disk for the toolchain image plus about 250 MB per build directory.
- The toolchain image, pulled by digest so you get exactly these tools: `trustworthysystems/camkes@sha256:77dcf9c7927c138d88434d812d8bd8b86455f9418d0895682250745b192e291e` (GCC 14.2.0, CMake 3.31.6, Ninja 1.12.1, dtc 1.7.2, mkimage 2025.01).

## Rebuild `images/sel4test.uImage`

[`scripts/build-sel4test.sh`](../scripts/build-sel4test.sh) checks out the pinned sel4test manifest ([`source/sel4test-manifest-pinned.xml`](../source/sel4test-manifest-pinned.xml)), verifies the manifest and every project SHA, applies [the patches](../patches/README.md), and builds in the pinned container with a generic build path and prefix maps, so the output does not depend on who builds it or where. The work directory must be new or empty:

```bash
WORK=$HOME/talos-sel4test-build
scripts/build-sel4test.sh "$WORK"
sha256sum "$WORK/out/sel4test.uImage"
grep sel4test.uImage images/SHA256SUMS
```

The two hashes must match. Outputs land in `$WORK/out/` (`sel4test.uImage`, the ELF, `boot-auto.scr`, `SHA256SUMS`); the patched checkout stays in `$WORK/sel4test`, which the Rust experiment and the source archive take as input. To rebuild **and** copy the results into `images/` and `boot/` (and regenerate `images/SHA256SUMS`), use another empty directory:

```bash
scripts/build-sel4test.sh "$HOME/talos-sel4test-build-2" --update-repo
```

Independent builds on 2026-10-20, 2026-10-21 and 2026-10-22 were byte-identical (SHA-256 `2c986076…`). Build settings and logs: [reports/BUILD_REPORT.md](../reports/BUILD_REPORT.md). **A changed image is a new, unverified image** until it has passed on the board.

The autoboot script source is [`boot/boot-auto.cmd`](../boot/boot-auto.cmd); `build-sel4test.sh` also rebuilds `boot-auto.scr` from it ([details](../boot/README.md#rebuilding-boot-autoscr)).

## Other images

- **Rust root task** (experiment): [experiments/rust-root-task/](../experiments/rust-root-task/README.md). It builds against the patched checkout from `build-sel4test.sh` and also needs a local `sel4-rust-tutorial` Docker image.
- **Any U-Boot image** you build elsewhere: `scripts/board.py flash path/to/image.uImage --expect 'REGEX'` ([flashing](flashing.md)). seL4's `make-uimage` helper wraps an elfloader ELF as a legacy uImage (load = entry = the ELF entry); its load range must stay below `0x8e000000`.

## Offline tests

```bash
tests/run.sh
```

Runs everything that needs no board, network or root (about 30 s): the flash sequence against a simulated U-Boot, the serial-share broker on a pseudo-terminal, port lookup, TFTP staging, every tool's command line, and repository hygiene (Markdown links, permissions, stale names, private data, image hashes). It also runs `shellcheck` and the SD installer test (`tests/test-installer.sh`, 88 checks on disposable FAT images) when their dependencies are installed, and lists what it skipped. What each test covers: [tooling.md](tooling.md#tests).

## Before publishing binaries

1. **Privacy audit.** Every shipped binary must be free of usernames, home paths, host names and real IP/MAC addresses:

   ```bash
   python3 -I scripts/privacy_audit.py images/sel4test.uImage boot/boot-auto.scr boot/boot-linux.scr board/discovery/discovery.dtb --json reports/privacy-audit.json
   ```

   It reports printable strings that look like paths, e-mail, IPv4 or MAC addresses or secrets, counts occurrences of your own user name, home directory and host name (without printing them), and decodes every embedded device tree to check for non-zero MAC addresses. Review the report; [reports/PRIVACY_AUDIT.md](../reports/PRIVACY_AUDIT.md) explains the current results.
2. **Corresponding source.** The kernel is GPL-2.0, so each release that ships the image must also offer its source:

   ```bash
   scripts/make-source-archive.sh "$WORK/sel4test" dist/
   ```

   The archive holds the pristine upstream sources at the pinned SHAs, this repository's patches, board files, build scripts and manifest, and a README tying them together ([notices](../THIRD_PARTY_NOTICES.md)).
3. **Checksums**: `sha256sum -c images/SHA256SUMS`, and read the next section.

## Checksums and authenticity

`images/SHA256SUMS` lists the SHA-256 hash of each binary. `sha256sum -c`, and the installer, check that your copy matches the hash **written in that file**.

| Question | Answered by SHA256SUMS? |
|---|---|
| Did the download, the copy or the SD card corrupt the file? | **Yes.** Any change to a byte changes the hash. |
| Is this the same file the team tested? | **Only if you trust the SHA256SUMS file itself.** It lives in the same repository as the binaries, so anyone who can change one can change both. |
| Who produced this file? | **No.** A hash carries no identity. |

So SHA256SUMS gives **integrity** against accidents, not **authenticity**. Nothing in this repository is signed, and **no authenticity claim is made**. Get the repository only from the team's official location, and compare hashes over a second channel when you can. Known values:

```text
2c98607641ea3418f39e3b4396c9fd97afdd982b151a3b7a783408a41b887d27  images/sel4test.uImage   (booted on the board: 118/49)
a5ab05d40c7d918150ded509a8a20ad91d39441d89772f6e992668160bcc6242  boot/boot-auto.scr
322ee52106fd2067a0b45932501d46d277018dbe46706ef6e608b41955db0060  boot/boot-linux.scr
```

Reproducibility is a partial substitute: a teammate who rebuilds and gets the same SHA-256 has independently checked that the published binary matches the published sources and patches. That relies on the pinned container image.

### Signed releases (proposed, not implemented)

**No keys exist and nothing has been signed.** For the first public release:

1. One or two named maintainers create signing keys on their own machines (an OpenPGP key, an SSH signing key with Git ≥ 2.34, or keyless Sigstore `cosign` with their GitHub identity).
2. Publish the public keys or identities somewhere independent of the repository (the team's GitHub org profile, the course page), and list their fingerprints in `docs/signing-keys.md`.
3. Tag releases signed: `git tag -s v0.1.0 -m "TALOS seL4 bring-up v0.1.0"`.
4. Sign the checksum file, not each binary: `gpg --armor --detach-sign images/SHA256SUMS`, or `cosign sign-blob --bundle SHA256SUMS.bundle SHA256SUMS`. Upload the signature and the corresponding-source archive as release assets.
5. Teammates import the key by its published fingerprint, run `gpg --verify SHA256SUMS.asc SHA256SUMS` (or `cosign verify-blob …`), then `sha256sum -c SHA256SUMS`.
6. Record hardware-tested status per release in [hardware.md](hardware.md#8-firmware-compatibility): a signature says who published a file, not that it was tested.

Until then, call the hashes **checksums**, and avoid words like "signed", "authentic" or "official".
