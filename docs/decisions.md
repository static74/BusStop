# Decisions

Dated records of choices that shape the code, with the alternatives that were turned down. Newest first.

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
