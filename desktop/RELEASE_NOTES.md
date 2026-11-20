Deltanium for desktop. Free to download. Your keys stay on your computer.

**Windows (64-bit):** download `Deltanium-Windows-x64.zip`, extract it, and run `Deltanium.exe`.
The app is not code-signed yet, so Windows SmartScreen may say "Windows protected your PC".
Click **More info** → **Run anyway**.

**macOS (Apple Silicon and Intel):** open `Deltanium-macOS.dmg` and drag **Deltanium** to Applications.
The app is not notarized yet. The first time, macOS will refuse to open it. Go to
**System Settings → Privacy & Security** and click **Open Anyway**.

**New in 1.3.0**
- Connects to network nodes over TCP (DLTP) when a node offers it, and falls back to HTTPS.
- Reaches nodes that run on a home or personal computer with only a public IP address: the app checks
  each such node against the key registered on the network, so nobody can stand in for it.
- Share-with choices on new posts are translated; your own comments show as "You".

Check your download against `SHA256SUMS.txt`. Source code: this repository and
https://github.com/dlvstudio/deltanium-core. Third-party licenses: `THIRD_PARTY_NOTICES.txt`.
