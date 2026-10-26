# Crest roadmap

This file summarizes public release outcomes and work that is still outstanding
or intentionally deferred. The live
[Crest Roadmap project](https://github.com/users/pauljoda/projects/3) shows
status; release milestones hold the actionable issue descriptions.

## Published releases

- [Crest 0.6.3](https://github.com/pauljoda/Crest/releases/tag/v0.6.3) — [release scope and completed work](https://github.com/pauljoda/Crest/milestone/2?closed=1).
- [Crest 0.5.7](https://github.com/pauljoda/Crest/releases/tag/v0.5.7) — [release scope and completed work](https://github.com/pauljoda/Crest/milestone/1?closed=1).

<!-- crest-roadmap-sync:start -->
## Active releases

Release milestones are shown from earliest to latest. The project board holds
the live status for each issue.

### [0.7](https://github.com/pauljoda/Crest/milestone/3)

#### Completed

- [x] [Keep active location access consistent with site permissions](https://github.com/pauljoda/Crest/issues/141)
- [x] [Keep extension compatibility access aligned with permission choices](https://github.com/pauljoda/Crest/issues/142) — [`22b22c95`](https://github.com/pauljoda/Crest/commit/22b22c959f59d9d1f7a6d7b490f14834fc446129)
- [x] [Clarify local extension replacement and permission continuity](https://github.com/pauljoda/Crest/issues/143) — [`361a1e92`](https://github.com/pauljoda/Crest/commit/361a1e92cd2652e21746e3e3376a54aad70f1c5b)
- [x] [Apply browser border size to Quick Windows](https://github.com/pauljoda/Crest/issues/147) — [`e2dd9187`](https://github.com/pauljoda/Crest/commit/e2dd9187d6a1345c5a1106726e64bdae012d67f0)
- [x] [Restore downloads from the built-in PDF preview](https://github.com/pauljoda/Crest/issues/150) — [`616f92d7`](https://github.com/pauljoda/Crest/commit/616f92d745b82c36cf78daded5e7174d83ab1669)
- [x] [Preserve webpage text interaction beneath the hidden title bar](https://github.com/pauljoda/Crest/issues/155) — [`9610550a`](https://github.com/pauljoda/Crest/commit/9610550a5690bbad15ef3bf37087c9dd085921b6)
- [x] [Choose which sidebar widgets appear](https://github.com/pauljoda/Crest/issues/160) — [`43a75820`](https://github.com/pauljoda/Crest/commit/43a75820a1534c3c69fef3d98a20baaa9d73baa1)
- [x] [Make unloaded-tab dimming optional](https://github.com/pauljoda/Crest/issues/162) — [`b920e80e`](https://github.com/pauljoda/Crest/commit/b920e80e096087b26b67e98ff986dd54644ddb33)
- [x] [Investigate WebP conversion and Slack Huddle behavior](https://github.com/pauljoda/Crest/issues/163) — [`f0de6ca2`](https://github.com/pauljoda/Crest/commit/f0de6ca247b6a769941e70042564aeebb6592011)
- [x] [Return from picture-in-picture to the originating tab](https://github.com/pauljoda/Crest/issues/166) — [`0e5c7162`](https://github.com/pauljoda/Crest/commit/0e5c716267863df43256d7a0b5b2d007440288ff)
- [x] [Stop LastPass popups from reloading the active page](https://github.com/pauljoda/Crest/issues/169) — [`c3a4d451`](https://github.com/pauljoda/Crest/commit/c3a4d4514454519b3dd08b934037576f9ff5bbeb)
- [x] [Balance Quick Window Space indicator padding](https://github.com/pauljoda/Crest/issues/171) — [`4c865709`](https://github.com/pauljoda/Crest/commit/4c8657099291e7384cdd90e43b17f71a851e6194)
- [x] [Keep Settings content visible while switching Spaces](https://github.com/pauljoda/Crest/issues/174) — [`292694ca`](https://github.com/pauljoda/Crest/commit/292694ca9bf4c0c43b66ef9f1234afedb26002d2)
- [x] [Return a saved tab to its root URL with one favicon click](https://github.com/pauljoda/Crest/issues/175) — [`52264922`](https://github.com/pauljoda/Crest/commit/52264922f1b6a3c65a84819ee0ecfadbc4cf0de5)
- [x] [Close an entire split by middle-clicking its title](https://github.com/pauljoda/Crest/issues/177) — [`dbd6a3fe`](https://github.com/pauljoda/Crest/commit/dbd6a3fea879e90b7fb57a76d147910434cd4336)

#### Not planned

- [x] [Use a thinner scrollbar that fades when idle](https://github.com/pauljoda/Crest/issues/148)

### [0.8](https://github.com/pauljoda/Crest/milestone/4)

#### Completed

- [x] [feature: Decouple pinned tab options and regular tab options](https://github.com/pauljoda/Crest/issues/138)
- [x] [Add common browsing actions to the macOS Dock menu](https://github.com/pauljoda/Crest/issues/152)
- [x] [bug: bad colors on new tab](https://github.com/pauljoda/Crest/issues/185)
- [x] [bug: The Manage Search Engines button doesn't work](https://github.com/pauljoda/Crest/issues/194)
- [x] [bug: Default Page Zoom deosn't work](https://github.com/pauljoda/Crest/issues/212)
- [x] [bug: Quick Window does not prompt macOS for camera/microphone access](https://github.com/pauljoda/Crest/issues/214)
- [x] [bug: Pin icon looks blurry or poor quality](https://github.com/pauljoda/Crest/issues/217)
- [x] [bug: Cant install Keeper as Extension in Chromium](https://github.com/pauljoda/Crest/issues/219)
- [x] [feature: Make Tab Groups visible](https://github.com/pauljoda/Crest/issues/220)
- [x] [feature: Install Crest with Homebrew (tap first, then homebrew-cask)](https://github.com/pauljoda/Crest/issues/222)
- [x] [bug: Quitting Crest creates an empty ~/Library/Application Support/Chromium](https://github.com/pauljoda/Crest/issues/223)
- [x] [bug: Crest 0.7.2 crashes when clicking a website's Login button on macOS](https://github.com/pauljoda/Crest/issues/224)
- [x] [Investigate a reported crash when signing in to Pinterest on Mac](https://github.com/pauljoda/Crest/issues/225) — [`606000ce`](https://github.com/pauljoda/Crest/commit/606000ce4b006e04dee412926366ebb355bcc186)
- [x] [Investigate reported passkey failures in both engines](https://github.com/pauljoda/Crest/issues/226)
- [x] [Recover safely from an accidentally repeated browser import](https://github.com/pauljoda/Crest/issues/230)
- [x] [Choose one search engine for every Space](https://github.com/pauljoda/Crest/issues/232) — [`c3e712f2`](https://github.com/pauljoda/Crest/commit/c3e712f200fb1fc90935c09eec48e1f41ae1c330)
- [x] [Evaluate a swipe gesture for History and Downloads on Mac](https://github.com/pauljoda/Crest/issues/235)
- [x] [Keep the Claude extension signed in after relaunching Crest](https://github.com/pauljoda/Crest/issues/238) — [`1222cfab`](https://github.com/pauljoda/Crest/commit/1222cfab91e205f9325b814fb7224a35f2d9872c)
- [x] [bug: Site Settings/Extension Menu unreliable in opening](https://github.com/pauljoda/Crest/issues/239)
- [x] [feature: Control Crest from the command line for scripts and AI agents](https://github.com/pauljoda/Crest/issues/240)
- [x] [feature: Delete a Space from the sidebar instead of the bottom of Settings](https://github.com/pauljoda/Crest/issues/241)
- [x] [Keep the back and forward history menu fast on long-lived tabs](https://github.com/pauljoda/Crest/issues/244) — [`86f5d23c`](https://github.com/pauljoda/Crest/commit/86f5d23cd6995e2d8790311bff1d09dbafa00bc5)
- [x] [bug: Crest crash eah time using 1password autofill extension](https://github.com/pauljoda/Crest/issues/248)
- [x] [bug: Unable to import spaces from Zen](https://github.com/pauljoda/Crest/issues/252)
- [x] [Keep a tab's back and forward history after relaunching](https://github.com/pauljoda/Crest/issues/253) — [`28e2c71b`](https://github.com/pauljoda/Crest/commit/28e2c71bf1e02e993bb0a0cc05285f554e14d02c)
- [x] [Evaluate site-specific search from the command palette](https://github.com/pauljoda/Crest/issues/255) — [`c3e712f2`](https://github.com/pauljoda/Crest/commit/c3e712f200fb1fc90935c09eec48e1f41ae1c330)
- [x] [Link the Crest Discord from the website](https://github.com/pauljoda/Crest/issues/256)
- [x] [bug: Crest crashes when allowing a site's microphone or camera access](https://github.com/pauljoda/Crest/issues/260)
- [x] [feature: Show "Unpin Tab" in a pinned tab's context menu](https://github.com/pauljoda/Crest/issues/261)
- [x] [feature: Reduce empty white space in the sidebar. ](https://github.com/pauljoda/Crest/issues/266)
- [x] [bug: extension install waits 180 s for the engine's download unless a page has loaded](https://github.com/pauljoda/Crest/issues/268)
- [x] [feature: Import from Aside and ego lite](https://github.com/pauljoda/Crest/issues/271)
- [x] [Import every Chrome profile during setup](https://github.com/pauljoda/Crest/issues/275) — [`d1cd39dd`](https://github.com/pauljoda/Crest/commit/d1cd39dd4deecd7f400ed3c639bd1786c4adff8e)
- [x] [Redesign Settings and Crest Studio](https://github.com/pauljoda/Crest/issues/282) — [`c2955759`](https://github.com/pauljoda/Crest/commit/c29557594b7e0c6932569079bec80278267326b5)
- [x] [feature: Be able to select a single tab instead of whole window while screen sharing](https://github.com/pauljoda/Crest/issues/295)
- [x] [feature: Make the page frame's corners concentric with the macOS 26 window corners](https://github.com/pauljoda/Crest/issues/305)
- [x] [Dark band covers the top of pages after entering full screen](https://github.com/pauljoda/Crest/issues/309) — [`81deb19d`](https://github.com/pauljoda/Crest/commit/81deb19d5825fad5f4094db137e6d715579c3791)
- [x] [Update relaunch can get stuck, and a cancelled relaunch can't be retried](https://github.com/pauljoda/Crest/issues/310) — [`0b5ebd4c`](https://github.com/pauljoda/Crest/commit/0b5ebd4c5501fb51c706cee25f879a748746d572)
- [x] [Show History doesn't open a hidden sidebar, and sidebar buttons don't follow a right-side sidebar](https://github.com/pauljoda/Crest/issues/311) — [`6c05ab37`](https://github.com/pauljoda/Crest/commit/6c05ab379fd793d7020e870e01638242d7469433)
- [x] [feature: Show audio indicator on active playback tabs](https://github.com/pauljoda/Crest/issues/318)
- [x] [bug: Crash when switching spaces with keyboard shortcut](https://github.com/pauljoda/Crest/issues/322)
- [x] [Sync doesn't resume on its own after recovering or relaunching](https://github.com/pauljoda/Crest/issues/324) — [`bf4f005f`](https://github.com/pauljoda/Crest/commit/bf4f005f58fffb3f363dfc92949bae76db9dcd7e)
- [x] [Show what iCloud sync is doing instead of just "Ready"](https://github.com/pauljoda/Crest/issues/325) — [`bf4f005f`](https://github.com/pauljoda/Crest/commit/bf4f005f58fffb3f363dfc92949bae76db9dcd7e)
- [x] [Keep the address card in place while typing on Mac](https://github.com/pauljoda/Crest/issues/327) — [`c3e712f2`](https://github.com/pauljoda/Crest/commit/c3e712f200fb1fc90935c09eec48e1f41ae1c330)
- [x] [Fill in a visited site's address while typing](https://github.com/pauljoda/Crest/issues/330) — [`c3e712f2`](https://github.com/pauljoda/Crest/commit/c3e712f200fb1fc90935c09eec48e1f41ae1c330)
- [x] [Copy Link copies the page behind Peek instead of the Peek page](https://github.com/pauljoda/Crest/issues/332) — [`b8162f4d`](https://github.com/pauljoda/Crest/commit/b8162f4db834c968d310f505ddfe7af15f305f5f)
- [x] [⌘G doesn't move to the next find-in-page match](https://github.com/pauljoda/Crest/issues/333) — [`8d699f9a`](https://github.com/pauljoda/Crest/commit/8d699f9a1a18bda64f0ea74e66200d09cbf1783a)
- [x] [Allow a narrower sidebar](https://github.com/pauljoda/Crest/issues/336)
- [x] [Overhaul the command palette: smarter ordering and a Settings section to customize it](https://github.com/pauljoda/Crest/issues/338) — [`c3e712f2`](https://github.com/pauljoda/Crest/commit/c3e712f200fb1fc90935c09eec48e1f41ae1c330)
- [x] [Search engine logos look stretched in Settings › Search on Mac](https://github.com/pauljoda/Crest/issues/354) — [`d27a88c5`](https://github.com/pauljoda/Crest/commit/d27a88c5bcb7bc48cf160e295d0dc7e8f6006f5e)
- [x] [Edit Shortcuts does nothing in Settings › Search on iPhone and iPad](https://github.com/pauljoda/Crest/issues/361) — [`6365c526`](https://github.com/pauljoda/Crest/commit/6365c5264b199a3523dd179eebe1432830cf4d69)
- [x] [Collapsed sidebar buttons can't be tapped on small iPhones](https://github.com/pauljoda/Crest/issues/368)
- [x] [Optional new-tab button in the iPhone toolbar](https://github.com/pauljoda/Crest/issues/371)
- [x] [feature:  Allow multiple Spaces to share a browser profile Allow multiple Spaces to share a browser profile](https://github.com/pauljoda/Crest/issues/379)

#### Not planned

- [x] [Sidebar hide and reveal animation is choppy on Mac](https://github.com/pauljoda/Crest/issues/355)
- [x] [Site Controls may still not open in full screen on Mac](https://github.com/pauljoda/Crest/issues/374)

### [0.9](https://github.com/pauljoda/Crest/milestone/5)

#### Planned and in progress

- [ ] [Choose a default Space using Focus](https://github.com/pauljoda/Crest/issues/145)
- [ ] [Switch the active Space in a Quick Window](https://github.com/pauljoda/Crest/issues/161)
- [ ] [Dim only the content behind Peek](https://github.com/pauljoda/Crest/issues/164)
- [ ] [Clear browsing data by Space and time range](https://github.com/pauljoda/Crest/issues/170)
- [ ] [Reveal the collapsed iPad sidebar on pointer hover](https://github.com/pauljoda/Crest/issues/176)
- [ ] [Add privacy-preserving analytics and opt-in diagnostics](https://github.com/pauljoda/Crest/issues/179)
- [ ] [feature: Add Edit Pinned URL menu option and dialogue](https://github.com/pauljoda/Crest/issues/218)
- [ ] [Make Quick Windows practical for short browsing sessions](https://github.com/pauljoda/Crest/issues/228)
- [ ] [Keep tabs opened inside collapsed folders visible](https://github.com/pauljoda/Crest/issues/231)
- [ ] [Return a pinned tab to its saved address from the mobile menu](https://github.com/pauljoda/Crest/issues/236)
- [ ] [bug: white flash between loading screen in dark mode](https://github.com/pauljoda/Crest/issues/246)
- [ ] [feature: have a top url bar when in fullscreen mode](https://github.com/pauljoda/Crest/issues/249)
- [ ] [bug: Can't install a private Chrome Web Store extension](https://github.com/pauljoda/Crest/issues/263)
- [ ] [feature: Double-click a tab to rename](https://github.com/pauljoda/Crest/issues/264)
- [ ] [Keep find in page in step with what you type](https://github.com/pauljoda/Crest/issues/278)
- [ ] [Show a designed window when opening the Mac installer](https://github.com/pauljoda/Crest/issues/280)
- [ ] [bug: Extension keyboard shortcuts act on a different tab than the one being viewed](https://github.com/pauljoda/Crest/issues/290)
- [ ] [Show page loading in the address bar instead of on the page card](https://github.com/pauljoda/Crest/issues/296)
- [ ] [Move whole folders between Spaces](https://github.com/pauljoda/Crest/issues/298)
- [ ] [Pointer reappears during playback and the sidebar opens on its own](https://github.com/pauljoda/Crest/issues/304)
- [ ] [Opening a new window can briefly freeze Crest](https://github.com/pauljoda/Crest/issues/328)
- [ ] [Sidebar toggle and download animation don't follow a right-side sidebar or right-to-left layout](https://github.com/pauljoda/Crest/issues/329)
- [ ] [Show both ends of a shared tab and keep its titles current](https://github.com/pauljoda/Crest/issues/335)
- [ ] [feature: Reorder Spaces in the drawer and rearrange the extension bar below the address bar](https://github.com/pauljoda/Crest/issues/339)
- [ ] [feature: Per-site developer mode toggle in the URL bar menu, persistent per origin](https://github.com/pauljoda/Crest/issues/351)
- [ ] [feature: Show extension actions next to the address field in Developer Mode](https://github.com/pauljoda/Crest/issues/352)
- [ ] [bug: cannot install third-party extensions](https://github.com/pauljoda/Crest/issues/364)
- [ ] [Hold-space cursor control doesn't work in the iPhone address bar](https://github.com/pauljoda/Crest/issues/370)
- [ ] [Switch what a tab is sharing from its sharing menu](https://github.com/pauljoda/Crest/issues/375)
- [ ] [bug: On fullscreen the Site Controls -menu doesn't open](https://github.com/pauljoda/Crest/issues/385)
- [ ] [feature: Show a peek indicator on the originating tab when a Peek is open](https://github.com/pauljoda/Crest/issues/389)
- [ ] [feature: Let agents run several page steps in one call](https://github.com/pauljoda/Crest/issues/403)
- [ ] [feature: Connect an agent from Settings without a terminal](https://github.com/pauljoda/Crest/issues/404)
- [ ] [bug: Command palette treats custom URL schemes as web search queries instead of opening them](https://github.com/pauljoda/Crest/issues/408)
- [ ] [Translation language download never progresses on Mac WebKit pages](https://github.com/pauljoda/Crest/issues/413)
- [ ] [bug: Cannot rearrange bookmarks](https://github.com/pauljoda/Crest/issues/419)
- [ ] [Tab switches Spaces instead of moving between form fields on iPad](https://github.com/pauljoda/Crest/issues/425)
- [ ] [Let agents attach local files to a page's file input over MCP](https://github.com/pauljoda/Crest/issues/442)
- [ ] [Web Inspector shortcut follow-ups](https://github.com/pauljoda/Crest/issues/443)
- [ ] [bug: Quick Window password support](https://github.com/pauljoda/Crest/issues/462)
- [ ] [Menu titles for History, Archive and Downloads now that they toggle](https://github.com/pauljoda/Crest/issues/470)
- [ ] [bug: Preserve sidebar state and page state when moving a tab to another window/display](https://github.com/pauljoda/Crest/issues/477)
- [ ] [feature: Support multiple Private Browsing windows](https://github.com/pauljoda/Crest/issues/481)
- [ ] [bug: Cannot visit Kagi homepage (CREST_NAVIGATION_FAILED)](https://github.com/pauljoda/Crest/issues/487)
- [ ] [feature: Share one extension install across chosen Spaces](https://github.com/pauljoda/Crest/issues/527)
- [ ] [bug: can't continue onboarding when importing from Arc](https://github.com/pauljoda/Crest/issues/535)
- [ ] [Remove the blank space at the bottom of the iPad layout](https://github.com/pauljoda/Crest/issues/548)
- [ ] [Keep a Quick Window from another app clear of a new tab's keyboard on iPhone](https://github.com/pauljoda/Crest/issues/563)
- [ ] [Say so when a link from another app needs a locked Space](https://github.com/pauljoda/Crest/issues/564)
- [ ] [bug: Saved passwords: one bad item can break a Space, and other storage gaps](https://github.com/pauljoda/Crest/issues/649)
- [ ] [Clear a single site's cookies, cache and website data, and manage website data in Settings](https://github.com/pauljoda/Crest/issues/686)

#### Completed

- [x] [feature: Swipping Tab Gesture On iphone](https://github.com/pauljoda/Crest/issues/54)
- [x] [Investigate mouse side buttons ignoring the sidebar's Space switching](https://github.com/pauljoda/Crest/issues/227) — [`36ed0821`](https://github.com/pauljoda/Crest/commit/36ed0821b08b6373775208aa9bb104596f1184a1)
- [x] [Evaluate a visual recent-tab switcher on Mac](https://github.com/pauljoda/Crest/issues/254) — [`179e9e8b`](https://github.com/pauljoda/Crest/commit/179e9e8b108caf7212188fc10c22625033764832)
- [x] [bug: CPU usage very high compared to Arc](https://github.com/pauljoda/Crest/issues/259)
- [x] [bug: Right-clicking an extension in Site Controls closes Site Controls](https://github.com/pauljoda/Crest/issues/262)
- [x] [feature: Redesign bottom space picker in the sidebar. ](https://github.com/pauljoda/Crest/issues/265)
- [x] [Treat a Split View as one tab when cycling tabs from the keyboard](https://github.com/pauljoda/Crest/issues/356) — [`179e9e8b`](https://github.com/pauljoda/Crest/commit/179e9e8b108caf7212188fc10c22625033764832)
- [x] [bug: http://192.168.0.1 automatically turns into https://192.168.0.1 and can not be open](https://github.com/pauljoda/Crest/issues/363)
- [x] [Some settings don't sync to iPhone](https://github.com/pauljoda/Crest/issues/369) — [`55653076`](https://github.com/pauljoda/Crest/commit/55653076149e7c8743ec9dab3135d7f2a7926d63)
- [x] [Open links in Crest from the iOS share sheet](https://github.com/pauljoda/Crest/issues/372) — [`b51ce590`](https://github.com/pauljoda/Crest/commit/b51ce5904844cdd6f64d6d63beb714e8d60f797b)
- [x] [Crest's iOS icon doesn't tint with tinted Home Screen icons](https://github.com/pauljoda/Crest/issues/373) — [`e7a30419`](https://github.com/pauljoda/Crest/commit/e7a304192244e91e69d825be430ade8aee1f95db)
- [x] [Page menu commands are disabled in Quick Windows on Mac](https://github.com/pauljoda/Crest/issues/377) — [`2b661960`](https://github.com/pauljoda/Crest/commit/2b661960d1013f9101417871ebdfeb8796dab253)
- [x] [Closing find with Escape doesn't return focus to the page on Mac](https://github.com/pauljoda/Crest/issues/378) — [`fdee1e3d`](https://github.com/pauljoda/Crest/commit/fdee1e3d41566ba4cf245d528d325b438b8be48b)
- [x] [feature: Expose native scripting & automation interface for Spaces, Tabs, and Window management](https://github.com/pauljoda/Crest/issues/380)
- [x] [feature: Choose search engine on new tab prompt (based on shortcut)](https://github.com/pauljoda/Crest/issues/386)
- [x] [feature: Toggle History, Archive, and Downloads sidebars and focus search](https://github.com/pauljoda/Crest/issues/397)
- [x] [bug: Sidebar expand and collapse animation drops frames](https://github.com/pauljoda/Crest/issues/398)
- [x] [Back and Forward stop working after a page falls back from Chromium to WebKit](https://github.com/pauljoda/Crest/issues/412)
- [x] [bug: Pin layout capped at 4 pins per row since 0.8 — selecting 5 or 6 has no effect](https://github.com/pauljoda/Crest/issues/415)
- [x] [Crest can quit while playing Reddit videos on iPhone](https://github.com/pauljoda/Crest/issues/420) — [`482a066f`](https://github.com/pauljoda/Crest/commit/482a066fc81362b1d98ce86828acb9eadbf526e3)
- [x] [Select the address when tapping the iPhone address bar](https://github.com/pauljoda/Crest/issues/421) — [`90021fea`](https://github.com/pauljoda/Crest/commit/90021feac234d549712ac302ae158265e3d0e7b8)
- [x] [Show that a link opened in a background tab](https://github.com/pauljoda/Crest/issues/422) — [`638ccdc0`](https://github.com/pauljoda/Crest/commit/638ccdc07cafcdce15e45405c078a83d0a013d2f)
- [x] [Swipe from the edge to go back on iPhone and iPad](https://github.com/pauljoda/Crest/issues/426) — [`53fdbdae`](https://github.com/pauljoda/Crest/commit/53fdbdae36cfe1da158b6693fbe7dbb201708e10)
- [x] [Air Traffic Control rules for links opened inside Crest](https://github.com/pauljoda/Crest/issues/427) — [`9579e3f4`](https://github.com/pauljoda/Crest/commit/9579e3f417a9c28fc3abd301779de5eafd6a9cec)
- [x] [bug: cannot input url for new route under links](https://github.com/pauljoda/Crest/issues/437)
- [x] [bug: Revealed sidebar stays open after the pointer leaves the window for another app](https://github.com/pauljoda/Crest/issues/440)
- [x] [After a Peek closes on Chromium, the tab doesn't get the keyboard back](https://github.com/pauljoda/Crest/issues/444) — [`a04f5215`](https://github.com/pauljoda/Crest/commit/a04f52157f2358fe648ef1eee41894db617602d9)
- [x] [bug: Look and Feel preview's page corners don't follow the preview's rounded corner on iPhone](https://github.com/pauljoda/Crest/issues/449)
- [x] [feature: Configure Tab and Space search-provider triggers independently](https://github.com/pauljoda/Crest/issues/450)
- [x] [bug: Open link in another Space can leave the new tab unselected](https://github.com/pauljoda/Crest/issues/451)
- [x] [Space switch animation: wrap-around jumps, and a sidebar animation restarts a running slide](https://github.com/pauljoda/Crest/issues/469) — [`62715030`](https://github.com/pauljoda/Crest/commit/6271503014ef6902c75c32193d9bf6ec0c2bfd60)
- [x] [bug: dropdown menus in the settings do not open](https://github.com/pauljoda/Crest/issues/476)
- [x] [Make Translate, Reader, content blocking, the inspector and engine moves act on a Quick Window](https://github.com/pauljoda/Crest/issues/484) — [`a0edbcc9`](https://github.com/pauljoda/Crest/commit/a0edbcc96c055f448c8b64de99dbb906ad8f632e)
- [x] [bug: Crash when DNS returns NXDOMAIN](https://github.com/pauljoda/Crest/issues/485)
- [x] [bug: Space settings stop responding to clicks after the first one](https://github.com/pauljoda/Crest/issues/491)
- [x] [Keep a Space slide moving forward when Next is pressed again mid-slide](https://github.com/pauljoda/Crest/issues/495) — [`118d9334`](https://github.com/pauljoda/Crest/commit/118d933403d1caf36fe940a6ff22431262d8fe7e)
- [x] [Restart to Update waits for Command-Q instead of quitting on its own](https://github.com/pauljoda/Crest/issues/496) — [`3a81c9f6`](https://github.com/pauljoda/Crest/commit/3a81c9f658a42153c4d3407f78d37ea58d221551), [`9623204f`](https://github.com/pauljoda/Crest/commit/9623204f56fbf86655cc05e567a1c492b3171e8a)
- [x] [Show the right tab title in the sidebar after a page fails to load](https://github.com/pauljoda/Crest/issues/506) — [`fbddee58`](https://github.com/pauljoda/Crest/commit/fbddee58da9df69d09256a5a1b59897018e1ac55)
- [x] [Redesign first-launch setup as a full-screen flow with a Heraldic or Modern look](https://github.com/pauljoda/Crest/issues/515) — [`37618b0d`](https://github.com/pauljoda/Crest/commit/37618b0d4f8d9abfb19b72cf6af4774304090916)
- [x] [bug: Shift-click in the sidebar toggles one tab instead of selecting a range](https://github.com/pauljoda/Crest/issues/519)
- [x] [bug: The sidebar hiding animation is broken and laggy.](https://github.com/pauljoda/Crest/issues/524)
- [x] [feature: Stretch pins to fill the row](https://github.com/pauljoda/Crest/issues/530)
- [x] [Paste and Match Style is greyed out on web pages](https://github.com/pauljoda/Crest/issues/540) — [`58a4792b`](https://github.com/pauljoda/Crest/commit/58a4792bed157f0e4f4d9cbc508dff19c2f4d375)
- [x] [Adapt Crest for iPhone Duo's inner and outer displays](https://github.com/pauljoda/Crest/issues/547) — [`bc99dcd9`](https://github.com/pauljoda/Crest/commit/bc99dcd926de87af86354bd434080a02b262f656)
- [x] [Restore the page's address after dismissing a typed address](https://github.com/pauljoda/Crest/issues/549) — [`a2303d81`](https://github.com/pauljoda/Crest/commit/a2303d8114c6749a6fca1d297e017e3b321da2fc)
- [x] [Keep the iPad Quick Window card inside the screen in portrait](https://github.com/pauljoda/Crest/issues/550) — [`30f93252`](https://github.com/pauljoda/Crest/commit/30f9325290bf1296a1b826b3aba4234251b87826)
- [x] [Show the shared page when a share opens Crest from closed on iPhone](https://github.com/pauljoda/Crest/issues/551) — [`b51ce590`](https://github.com/pauljoda/Crest/commit/b51ce5904844cdd6f64d6d63beb714e8d60f797b)
- [x] [Keep the Quick Window card clear of the top of the screen only once on iPhone](https://github.com/pauljoda/Crest/issues/558) — [`30f93252`](https://github.com/pauljoda/Crest/commit/30f9325290bf1296a1b826b3aba4234251b87826)
- [x] [Let the iPhone Duo sidebar's list run into the bottom corner](https://github.com/pauljoda/Crest/issues/560) — [`d1082130`](https://github.com/pauljoda/Crest/commit/d1082130937c86fca1b15e180f8885cb9e2868cd)
- [x] [Update the Chromium engine to 155.0.8059.84 and distrust the compromised eMudhra CAs](https://github.com/pauljoda/Crest/issues/572) — [`d8b18cd1`](https://github.com/pauljoda/Crest/commit/d8b18cd190ea196db650fdb01888f11c0fe55cab)
- [x] [feature: Capture part of a page from the keyboard](https://github.com/pauljoda/Crest/issues/579)
- [x] [feature: Space switcher shows all Spaces at normal sidebar width](https://github.com/pauljoda/Crest/issues/588)
- [x] [Show what coding agents do in Crest and stop them all at once](https://github.com/pauljoda/Crest/issues/609) — [`db8c4e0e`](https://github.com/pauljoda/Crest/commit/db8c4e0ede11456a8b010dc536f318f7f6399b73)
- [x] [Keep a Space's lock off after switching it off in Settings](https://github.com/pauljoda/Crest/issues/618) — [`0757dd90`](https://github.com/pauljoda/Crest/commit/0757dd903c6ab9a17d072699d922689857ed86e2)
- [x] [Keep Look and Feel changes smooth while they preview live](https://github.com/pauljoda/Crest/issues/619) — [`b3fd540c`](https://github.com/pauljoda/Crest/commit/b3fd540c0157fb630535540793e68888f23f508a)
- [x] [bug: An imported password with an IPv6 host makes the whole Space's passwords unreadable](https://github.com/pauljoda/Crest/issues/645)
- [x] [Stop Crest freezing when an iCloud sync arrives during a save](https://github.com/pauljoda/Crest/issues/667) — [`e4d08a31`](https://github.com/pauljoda/Crest/commit/e4d08a31582180422fd2870298d63f358ffe499a)

<!-- crest-roadmap-sync:end -->

These describe intended user outcomes rather than fixed implementation
promises. Scope may change when WebKit capability, accessibility, or physical
device evidence shows a better boundary.

## Approval-gated capabilities

- Obtain Apple's managed default-browser entitlement for `com.pauldavis.crest`, then enable and validate default-browser registration on physical devices.
- Complete the browser passkey entitlement request and physical-device passkey validation before advertising passkey-provider support.

## Release gates

Repeat these checks for each release candidate.

- Deploy and verify the production CloudKit schema.
- Complete two-device convergence testing for Space lifecycle, secure deletion, Keychain behavior, and offline edits.
- Exercise camera, microphone, document picker, picture-in-picture, and offline recovery on physical iPhone and iPad hardware.
- Finish physical accessibility coverage for VoiceOver, Voice Control, keyboard-only use, pointer interaction, larger text, reduced motion, and right-to-left localization.
- Validate Stage Manager and external-display behavior on iPad.
- Run the real-world migration corpus for bookmarks, tabs, folders, and portable archives from supported source browsers.

## Active platform work

- [Image-conversion compatibility](https://github.com/pauljoda/Crest/issues/163) is delivered. Slack Huddles remain deferred and are not claimed fixed or validated.

- Extension work is active in the Chromium Mac product. Preserve per-Space isolation, keep extensions out of private windows, and report what Crest's host does not support instead of presenting partially initialized extension UI as working.
