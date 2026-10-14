# Decisions

Dated records of choices that shape the code, with the alternatives that were turned down. Newest first.

## 2026-10-14: The map draws its own tooltips for chips and badges

**Question.** Hovering a speed chip, transport chip or power badge on a map card showed no tooltip, although each carries `.help`. How should the map explain its chips?

**Decision.** On the map, chips and badges publish their rectangles in layout coordinates through a preference (`GraphTooltipRegionsKey`), measured in one named coordinate space per card before the zoom. A card reports the pointer in that same space, and the map's hit layer reports it for the link chips, which never take the pointer. `GraphTooltipState` finds the smallest chip under the pointer and shows its text in `GraphTooltipOverlay`, drawn above the drawing group so it keeps its size and stays sharp at every zoom. It never takes the pointer. It appears after the system's `NSInitialToolTipDelay` (one second unless set), or after 0.1 s when moving on from another tooltip. It hides on a mouse-down, a pan or zoom, a Data/Power switch, when the window stops appearing active, and when its chip goes away; after a click it stays hidden until the pointer leaves the chip. It fades only without Reduce Motion, and its border is the accent under Increase Contrast. The chips' `.help` stays everywhere else (popover, List mode, tables, inspector): an environment value, `showsChipHelp`, is false only inside the map. Accessibility labels are unchanged; the tooltip is hidden from VoiceOver.

The regions are kept out of observation and the map's body never reads tooltip state. Only the overlay observes the tooltip on screen, which changes only when a tooltip appears, disappears or its text changes. Each chip keeps its rectangle with `onGeometryChange` in the card's own space, which a pan or zoom does not change. So the tooltip adds no redraws of the map, and a pan or zoom publishes no new regions; a snapshot redraws the map as before (see the 16.7 ms p95 budget under "Map cards and chips render after the zoom").

**Why.** Checked by hand on main in the topology window. With link animation on (the default), the map's own Zoom In button showed no tooltip, while the toolbar's buttons did. With `-animateLinks NO` in the demo, Zoom In showed its tooltip. So the 30 fps pulse `TimelineView` keeps the system's tooltips from appearing anywhere over the map. It may not be the only cause: on real hardware with `-animateLinks NO` and a 5 s poll, Zoom In still showed no tooltip in two tries. Card chips showed no tooltip even with animation off, in the demo and on real hardware, so the cards add a cause of their own. The suspects, not proven, are the chips sitting inside each card's `Button` label and the snapshot being replaced every poll. A map-drawn tooltip sidesteps all of these without pausing the pulses. A headless hosting-view test confirms that the regions pass through the drawing group and that a `ViewThatFits` publishes only the chips it shows.

List mode in the topology window also loses native tooltips at the demo's 2 s cadence (it showed them at a 5 s poll; the menu-bar popover shows them at 2 s). That looks like a window-level problem; it is not fixed here and is to be filed as a follow-up.

**Rejected alternatives.**

- *Pause the pulses while the pointer rests.* The card chips showed no tooltip with the pulses off either.
- *One `.help` on each card's `Button`, summarising its chips.* Not per chip, it still depends on the system tooltip over the animating map, and the link chips stay uncovered.
- *One map-wide `.help` whose text follows the pointer.* Whether the system re-arms it when the text changes is undocumented, and the pulses suppress it anyway.
- *Clear views carrying `.help` above the drawing group.* They would take clicks, hover and pointer styles from the cards and links.
- *Let the link chips take the pointer.* They would take hover and clicks from the links under them.

## 2026-10-14: No page sets the minimum width of the topology window's detail column

**Question.** With the inspector open, the topology window crashed on the Events page at 1000 pt wide and narrower (issue #5). AppKit raised an exception because the window needed more update-constraints passes than it has views. How should the pages and the detail column share the width?

**Decision.** `TopologyWindowView` gives the detail column `.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)`, so no page passes a minimum width to the split view. A page that is still wider than the column runs past its right edge, under the inspector, never under the sidebar. Pages also fit narrow columns on their own: the Events header puts the filter and Clear under the title when one row does not fit (`ViewThatFits`), and a diagnostic's Show buttons stack the same way. `TopologyWindowLayoutTests` hosts the whole window as `WindowManager` does, with the inspector open, and lays it out for a second.

**Why.** `NavigationSplitView` hosts each column in its own `NSHostingView`, with a constraint that keeps the column at least as wide as its fitting width, at priority 999.9. The fitting width includes the safe-area insets, and the detail column runs under the floating sidebar (232 pt) and the inspector (330 pt), so those are its insets. When the page inside sets a minimum width, the column's width and its insets keep invalidating each other. At 1000 pt the Events column settled at 535 pt wide with a right inset of 0, where every other page's column was 1000 pt wide with insets of 232 and 330. With the fix, the Events column is 1000 pt wide too, and its constraint is 562 pt, the two insets and nothing from the page. Measured on macOS 27. The root view's own minimum (860 pt from `.frame(minWidth: 860)`) was the same on every page and with or without the fix, so `sizingOptions = [.minSize]` in `WindowManager` is not involved.

The threshold does not follow from the page's minimum width. The Events page measured 303.5 pt at every text size (its filter popup alone is 199.5 pt and does not grow with Text Size), and it crashed from 900 pt up to 1080 pt, but not at 1100 pt. Diagnostics with one finding measured 207 pt and crashed at 900 and 1000 pt, but not at 1050 pt. Devices and Power never crashed, and no page crashed with the inspector closed. With the fix, the Events page reports 85 to 99 pt (Small to Extra Large), the floor of its empty-state text.

Each half was measured on its own in the window test. The detail column frame alone ends the crash on both pages. The adaptive Events header alone ends it on Events but not on Diagnostics, so the frame is the fix and the header keeps Clear from being clipped (at 1040 pt it was).

**Rejected alternatives.**

- *Raise the window's minimum width.* SPEC §3.3 promises 900 × 600, and Events crashed up to 1080 pt.
- *Remove `.fixedSize()` from the Events filter.* Measured: still crashed at 900 pt.
- *Only the adaptive Events header.* Measured: Diagnostics with a finding still crashed.
- *`.clipped()` on the detail column.* It would also cut the page background off where it runs up under the transparent title bar (see the next entry).
- *Close the inspector when the window is narrow.* It overrides the user's choice, and the inspector is where Events and Diagnostics show what they select.

## 2026-10-13: The topology window's title bar is transparent where nothing scrolls under it

**Question.** With the inspector open, the toolbar's search field straddled the end of a gray band over the detail column, because the inspector's black runs up under the toolbar. How should the toolbar strip look?

**Decision.** The title bar is transparent on the map (an overview or port page in Graph mode), the All Ports and All Devices tables, Events, and Diagnostics while it has no findings. `TopologyWindowView` sets it through `HostingWindowObserver`. On those pages the toolbar strip shows the window's black over the page and the inspector alike (SPEC §4.1, "true dark"). Power, the List overview and Diagnostics with findings keep the system's opaque title bar. The Export menu hides its chevron.

**Why.** Over the map, which has no scroll view, the title bar drew an opaque gray band (40/255), while the inspector's black ran up under the toolbar. The search capsule began just left of that boundary. The map is clipped to its frame, so a transparent title bar there shows only black. The rows of the two tables and of Events scroll only below their page header, and Diagnostics has no scroll view while it has no findings, so nothing passes under the strip on those pages either.

Pages that scroll need the opaque title bar. A transparent bar on every page was built first. Under it, rows scrolled up showed crisp under the title and the toolbar buttons on the List, Power and Diagnostics pages. With the opaque bar, those rows stay hidden or dimmed as before.

With the inspector open, the opaque-bar pages measure 8 to 16/255 over the detail column against 3 to 5 over the inspector, so no page shows a seam. On main, Power and Diagnostics turned gray (30/255) once the window had shown the map; switching the title bar back to opaque resets that. Whether the window is active makes no difference.

The Export button is a `Menu`, whose disclosure chevron pushed the share icon left of centre.

**Rejected alternatives.** Each was built and captured.

- *A transparent title bar on every page.* Rows scrolled under it showed crisp under the title and buttons. `.scrollEdgeEffectStyle(.hard, for: .top)` hid them only on AppKit lists and tables, not on SwiftUI `ScrollView` pages such as Power.
- *`.toolbarBackground(.black, for: .windowToolbar)` with the background visible.* The band stayed gray.
- *`.scrollEdgeEffectHidden(true, for: .top)` on the map.* The band stayed gray.
- *Stop the inspector's background at the toolbar.* It left a step in the strip's gray from 42 to 35 and a hairline that ended at the column boundary.
- *`.scrollEdgeEffectStyle(.soft, for: .top)` alone.* The gray band stayed.
- *Search in the sidebar.* Search disappears from the window when the sidebar is collapsed.
- *`.searchable` on the detail column, `DefaultToolbarItem(kind: .search)` declared before the buttons, a fixed `ToolbarSpacer` before search, or hiding the window toolbar's background.* None of them moved the field off the seam or removed the band.

## 2026-10-13: Map cards and chips render after the zoom, in one drawing group

**Question.** How should the map's cards and speed/power chips stay sharp at every zoom, as the links already do?

**Decision.** The chips layer and the cards share one `drawingGroup()` in `GraphMap`. Each card keeps its `scaleEffect` and `position`, but the group renders them after the zoom, at the screen's resolution, instead of enlarging a bitmap drawn at 100 %. Everything inside the group must be pure SwiftUI drawing (text, shapes, SF Symbols): a drawing group shows glass, materials, `ProgressView`, `Menu`, `TextField`, system-styled controls and `NSViewRepresentable`s as placeholders. The system focus ring is lost inside the group too, so each selectable card draws its own `accentGlow` ring while it has keyboard focus. The map leaves the view tree while the topology window is closed, so the group's textures are freed; the window itself is kept for reuse.

**Why.** At 200 % a card matched a bilinear 2× enlargement of its 100 % render (mean difference 1.2/255), which looks pixelated on a 1× display and soft on Retina. With the drawing group it differs from that enlargement by 7.9, and its edge sharpness rises from 16.4 to 21.4. At 100 % the two renders match (mean difference 0.14/255). The remaining figures were measured in one session against main, on a 27-device dock. Panning and a 25 %–200 % zoom sweep held 16.7 ms p95 in both builds, on a 60 Hz display and on a 144 Hz display. On the 144 Hz display both builds paced at 60 fps, so at 60 fps the drawing group adds no frame cost; neither build was measured at a higher frame rate. With the window open, memory matches main before any zoom: 309 against 308 MB in a 1280 × 820 window at 1×, and 422 against 407 MB in a 1900 × 1000 window at 2×. After a zoom sweep it is higher: 393 against 347 MB at 1×, and 682 against 591 MB at 2×. Closing the window gives the group's textures back, because the map leaves the tree: the closed footprint was 142 against 129 MB at 1×, and 180 against 247 MB at 2×.

**Rejected alternatives.**

- *Lay the cards out at screen size with zoom-scaled fonts, paddings and icons.* Every shared chip, badge and icon would need a zoom parameter, and `Lagoon.font` rounds point sizes while SF Pro changes optical size at 20 pt, so truncation would shift between zoom steps.
- *Draw the cards in a `Canvas`, like SVG.* It duplicates all card and chip styling and rebuilds hit testing, hover, tooltips and accessibility by hand.
- *One drawing group per card.* More offscreen passes, for no gain.
- *Cap the zoom at 100 %.* It removes the zoom the map offers.

## 2026-10-13: The topology map draws through its own camera, not a scroll view

**Question.** How should the topology map pan and zoom, so that it stays sharp at 200 %, stays smooth on a large graph and pans freely like a web map?

**Decision.** The map has no `ScrollView`. `GraphCamera` holds a scale and an offset (a layout point `p` appears at `p × scale + offset`). Every canvas (backdrop, links, highlights, pulses) is the size of the window and draws through the camera; cards and speed chips are SwiftUI views placed through the camera and scaled with `scaleEffect`. Only what is on screen is drawn. A drag or pinch moves the camera on screen through gesture state and commits it when the gesture ends. The scroll-wheel monitor zooms for a mouse wheel and pans for trackpad scrolls and modified wheels, since no scroll view is left to take them.

**Why.** The graph used to be one canvas the size of the whole layout inside a scroll view, enlarged with `scaleEffect`. On a real dock with 27 devices that caused three problems:

- **Blur.** `scaleEffect` enlarges a `Canvas` as a bitmap, so links went soft above 100 %. This entry first claimed that SwiftUI text and shapes stay sharp under `scaleEffect`. The claim was wrong: cards and chips were enlarged as bitmaps too, and "Map cards and chips render after the zoom" corrected them the same day.
- **Lag.** Every canvas covered the whole layout, the pulse canvas redrew it 30 times a second, and the backdrop rebuilt its whole dot grid at every zoom step.
- **Panning.** A scroll view only moves within its content, so a graph that fits the window could not be dragged at all. Pan state also came from geometry callbacks that lag behind programmatic scrolls, which is the likeliest cause of a second drag snapping the map back.

**Rejected alternatives.**

- *Draw the canvases at the zoomed size inside the scroll view.* This keeps the scroll view but makes each canvas `layout × scale` large: several hundred megabytes of bitmap at 200 % on this graph, and slower, not faster.
- *Pad the scroll view's content by half a window on every side.* Tried first, to allow free panning. It quadrupled the area of every full-graph canvas, made the lag worse and still depended on the scroll view's geometry callbacks.
- *Keep the camera in `TopologyGraphView`.* Its body builds the layout and the strokes. A camera there would rebuild them on every frame of a drag, so the camera is read only by `GraphMap`.
