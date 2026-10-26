# M4-Nix installer kit

Experimental NixOS for the 13-inch M4 MacBook Air (Mac16,12 / J713) only,
minimal-risk profile. Installed and booted on one Air so far.

This kit is the Omarchy-M4-Native v0.1.0-alpha.1 update 4 installer, unchanged,
with a NixOS OS package instead of Omarchy's. It is not made, endorsed or
supported by that project, Asahi Linux or Apple.

Before installing:

1. Make a full, tested backup of the Mac.
2. Have macOS 26.5.1 or newer. The installer puts a 26.5.1 stub beside it.
3. Read GUIDE.md in this folder, on another device, before you start.

Then, in Terminal on the Air:

```sh
bash Install.command --verify-only
bash Install.command --install
```

The installer runs in expert mode. Keep macOS and both recovery environments.
Select the NixOS entry, choose the size, and follow its on-screen steps.

To undo: from macOS, delete the NixOS partitions it created with Disk Utility
or `diskutil`, as GUIDE.md describes (R2). macOS is not changed by the install.

License notices for the installer are in `notices/`.
