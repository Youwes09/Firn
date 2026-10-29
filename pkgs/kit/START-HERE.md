# Firn installer kit

Firn is an experimental NixOS for the 13-inch M4 MacBook Air (Mac16,12 /
J713) only, with a minimal-risk profile: the parts that are not finished
(speakers, GPU, CPU boost and others) stay off.

The installer is Gravity Linux's installer with the J713 added, built by
the Firn project. Firn is not made, endorsed or supported by Gravity
Linux, Asahi Linux or Apple.

Before installing:

1. Make a full, tested backup of the Mac.
2. Have macOS 26.5 or newer. The installer puts a macOS 26.6.2 stub
   beside it, which the Air needs to boot Linux.
3. Read GUIDE.md in this folder, on another device, before you start.

Then, in Terminal on the Air:

```sh
bash preflight.command
bash Install.command --verify-only
bash Install.command
```

The preflight prints the size to type when the installer asks for macOS's
new size. Keep macOS and both recovery environments. Choose the Firn entry
and follow the on-screen steps.

To undo: from macOS, delete the partitions the installer created, as
GUIDE.md describes (R2). macOS itself is not changed by the install.

License notices for the installer are in `notices/`.
