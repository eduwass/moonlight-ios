# Computers & Consoles for Apple TV

A personal tvOS fork with a computer landing screen, keyboard and raw mouse input,
and one-click Desktop streaming. iOS keeps the upstream interface.

- Tiles show the most recent frame captured during a stream (every 15 seconds and
  on disconnect), with its timestamp. They are cached previews, not live feeds.
- Response time measures a Sunshine HTTP round trip, not ICMP ping or video latency.
- Keyboard status comes from GameController; mouse status turns green after real
  input and asks for movement again after 60 idle seconds because tvOS does not
  reliably expose mouse connection state. The keyboard name is supplied by tvOS.
- Click, Return, or the remote Select button opens Desktop; hold Select for host
  options. Remote Back or Play/Pause disconnects; Escape (including double-Escape) stays
  inside the remote desktop. If Desktop is not advertised, the normal app picker opens instead.
- Physical Siri Remote Back uses its GameController button callback. UIKit's
  ambiguous Menu event is consumed and forwarded as Escape, never a disconnect.
  Play/Pause also returns home. Other remote types have not been verified.
- Bare F4 sends Command+Space to the connected computer (Raycast on Mac,
  Oma-Cast on Omarchy). Consumer AC Search and Apple's vendor Spotlight usage
  are accepted too when delivered by tvOS. System App Menu is not a launcher:
  Escape can produce that event. Modified F4 shortcuts pass through.
- With the Mac cursor helper, the TV draws the pointer locally and sends absolute
  positions within the video rectangle, so motion does not wait for a video frame.
  The existing cursor-shape protocol on TCP 47995 supplies images and hotspots;
  only the selected host's IPv4 address is accepted. If the helper disconnects,
  the TV falls back to the host cursor and relative motion. Hosts without the
  helper retain the existing input path.
- Stream input comes from raw HID keyboard and mouse events, with GCKeyboard as
  the fallback when the private observer is unavailable. Public
  GCMouse handlers are disabled during the stream: tvOS can report a mouse
  without delivering its events. Held keys/buttons are released when leaving
  the stream and suppressed across a host change until physically released.
- Video playback anchors its clock to the first host frame. A resumed host can
  send timestamps hours into its session; interpreting those as the TV's uptime
  freezes the picture even while keyboard and mouse input reaches the host.
- The raw HID observer is a private API for personal sideloading. It may break on
  a tvOS update and is unsuitable for App Store distribution.

Build the **Moonlight TV** scheme with Xcode and your development team (tvOS 17.4+).
The fork uses `com.eduwass.moonlightnext.tv` so it can coexist with stock Moonlight.

Input check: `cc -Wall -Wextra -Werror tests/sofa-input.c -lm -o /tmp/sofa-input-check && /tmp/sofa-input-check`.
On a real TV, verify pointer movement before connecting, click/Return, typing,
left/right clicks, scroll and drag in a desktop, disconnect while holding a mouse
button, switch hosts, and reconnect the keyboard. Check the updated preview.
For video regression, stream a ticking clock from both a freshly started and a
resumed Mac/Linux session for at least 30 seconds; confirm it keeps advancing.
Verify local cursor motion, aligned small-target clicks and drags, shape changes,
and fallback when the host helper disconnects.
Verify single/double keyboard Escape stay connected and physical remote Back and
Play/Pause return home.

Optional first-install migration: `python3 tools/export-qt-pairing.py /private/tmp/sofa-pairing`
exports your existing Mac pairing into private files. With the TV app stopped,
copy the exported preferences as `Library/Caches/sofa-identity.plist` and the host
list as `Library/Caches/sofa-hosts.plist` using
`devicectl device copy to --domain-type appDataContainer`. The next launch imports
and deletes both files.
Check that host addresses are reachable from the TV. Delete the exported files
after copying. This reuses the Mac pairing identity; revoking it affects both clients.
Never copy these files into the repository. Importing replaces the TV pairing identity.

## Dictation experiment

A stream automatically activates a native tvOS editor, covered by the existing live
stream layer. Hold the Siri Remote mic, speak, then release; the completed phrase
is sent once as ordinary keystrokes using Moonlight's existing US-key mapping.
The test supports printable ASCII; other characters are rejected visibly before
any text is sent. This avoids Sunshine Linux's broken Unicode shortcut path.
Double-tapping the mic within 400 ms sends Enter; finishing dictation alone does
not. Duplicate HID releases and holds are excluded. Physical
keyboard presses continue through raw HID and are withheld from the hidden editor.
Back/disconnect restores the layer tree and dismisses the editor.

This is a private-API sideload experiment verified initially on tvOS 27.2. It exposes
recognized text, not the microphone recording. Debug builds run a phrase-delivery
self-check at startup; `Library/Caches/sofa-dictation.json` records lifecycle,
character counts and transport return codes without transcripts.

Mic gesture check: `cc -Wall -Wextra -Werror tests/sofa-mic-tap.c -o /tmp/sofa-mic-tap && /tmp/sofa-mic-tap`.

Device check: connect, click an empty host text box, type `abc`, dictate two phrases
(including the same phrase twice), type and use arrows/Return, then disconnect and
reconnect. Verify live video, cursor alignment, one insertion per phrase and Back.

## Console inputs

**Computers** is the existing Moonlight TV app (`com.eduwass.moonlightnext.tv`),
with its saved pairings and settings preserved. Its full-screen Top Shelf carousel opens with a dark coding scene with pixel mascots,
then recent computer screenshots, newest first, that connect directly to Desktop.

**Consoles** is a separate lightweight app (`com.eduwass.sofa.consoles`). Build the
**Consoles** scheme in `Consoles.xcodeproj`. It shares the Philips control source and
console artwork, without the streaming engine. Its full-screen Top Shelf opens with official GTA VI artwork, then PS5 Pro and
Switch 2 via `sofa-consoles://console/ps5` and `/switch2`. Put either or both apps in
the Apple TV Home Screen’s top row. Console cards switch HDMI inputs; wake a
sleeping console with its controller.

Into the **Consoles** app container, import a private `Library/Caches/sofa-tv.plist` with `host`, `username`, `password`,
`certificate` (DER data), and `inputs` (each with `id`, `name`, `port`, and `uri`).
The only supported IDs are `ps5` and `switch2`. The app validates and moves this
file into its device-only Keychain, then deletes the import. Never put it in the
repository or application bundle. Requests use HTTPS with the paired TV’s pinned
certificate and Digest authentication; redirects are refused.

Icon catalog check: `python3 tests/sofa-assets.py`.

Console-link check (macOS):
`clang -fobjc-arc -framework Foundation tests/sofa-console-link.m -o /tmp/sofa-console-link && /tmp/sofa-console-link`.
Verify both tiles and Top Shelf cards on the physical Apple TV. A successful API
response means the TV accepted the command; confirm the selected HDMI input on
the screen too. Debug builds write only the input ID, HTTP status and error code
to `Library/Caches/sofa-tv-result.json` for that check.

## Upstream Moonlight iOS/tvOS

[![CI](https://github.com/moonlight-stream/moonlight-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/moonlight-stream/moonlight-ios/actions/workflows/ci.yml)

[Moonlight for iOS/tvOS](https://moonlight-stream.org) is an open source client for [Sunshine](https://github.com/LizardByte/Sunshine) and NVIDIA GameStream. Moonlight for iOS/tvOS allows you to stream your full collection of games and apps from your powerful desktop computer to your iOS device or Apple TV.

Moonlight also has a [PC client](https://github.com/moonlight-stream/moonlight-qt) and [Android client](https://github.com/moonlight-stream/moonlight-android).

Check out [the Moonlight wiki](https://github.com/moonlight-stream/moonlight-docs/wiki) for more detailed project information, setup guide, or troubleshooting steps.

[![Moonlight for iOS and tvOS](https://moonlight-stream.org/images/App_Store_Badge_135x40.svg)](https://apps.apple.com/us/app/moonlight-game-streaming/id1000551566)

## Building
* Install Xcode from the [App Store page](https://apps.apple.com/us/app/xcode/id497799835)
* Run `git clone --recursive https://github.com/moonlight-stream/moonlight-ios.git`
  *  If you've already clone the repo without `--recursive`, run `git submodule update --init --recursive`
* Open Moonlight.xcodeproj in Xcode
* To run on a real device, you will need to locally modify the signing options:
    * Click on "Moonlight" at the top of the left sidebar
    * Click on the "Signing & Capabilities" tab
    * Under "Targets", select "Moonlight" (for iOS/iPadOS) or "Moonlight TV" (for tvOS)
    * In the "Team" dropdown, select your name. If your name doesn't appear, you may need to sign into Xcode with your Apple account.
    * Change the "Bundle Identifier" to something different. You can add your name or some random letters to make it unique.
    * Now you can select your Apple device in the top bar as a target and click the Play button to run.
