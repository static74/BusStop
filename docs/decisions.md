# Decisions

Dated records of choices that shape the code, with the alternatives that were turned down. Newest first.

## 2026-10-13: Map cards and chips render after the zoom, in one drawing group

**Question.** How should the map's cards and speed/power chips stay sharp at every zoom, as the links already do?

**Decision.** The chips layer and the cards share one `drawingGroup()` in `GraphMap`. Each card keeps its `scaleEffect` and `position`, but the group renders them after the zoom, at the screen's resolution, instead of enlarging a bitmap drawn at 100 %. Everything inside the group must be pure SwiftUI drawing (text, shapes, SF Symbols): a drawing group shows glass, materials, `ProgressView`, `Menu`, `TextField`, system-styled controls and `NSViewRepresentable`s as placeholders. The map leaves the view tree while the topology window is closed, so the group's textures are freed; the window itself is kept for reuse.

**Why.** At 200 % a card matched a bilinear 2× enlargement of its 100 % render (mean difference 1.2/255), which looks pixelated on a 1× display and soft on Retina. With the drawing group it differs from that enlargement by 7.9, and its edge sharpness rises from 16.4 to 21.4. At 100 % the two renders match (mean difference 0.14/255). Panning and a 25 %–200 % zoom sweep on a 27-device dock hold the same frame times as before (about 16.7 ms p95 at 60 Hz; not measured at 120 Hz). While the window is open, memory rises by about 50 MB in a 1280 × 820 window (1× and 2×) and 100 to 130 MB in a 1900 × 1000 to 2400 × 1050 window on a 2× display. While it is closed, the footprint is lower than before the change (75–130 MB against 119–250 MB), because the map leaves the tree.

**Rejected alternatives.**

- *Lay the cards out at screen size with zoom-scaled fonts, paddings and icons.* Every shared chip, badge and icon would need a zoom parameter, and `Lagoon.font` rounds point sizes while SF Pro changes optical size at 20 pt, so truncation would shift between zoom steps.
- *Draw the cards in a `Canvas`, like SVG.* It duplicates all card and chip styling and rebuilds hit testing, hover, tooltips and accessibility by hand.
- *One drawing group per card.* More offscreen passes, for no gain.
- *Cap the zoom at 100 %.* It removes the zoom the map offers.

## 2026-10-13: The topology map draws through its own camera, not a scroll view

**Question.** How should the topology map pan and zoom, so that it stays sharp at 200 %, stays smooth on a large graph and pans freely like a web map?

**Decision.** The map has no `ScrollView`. `GraphCamera` holds a scale and an offset (a layout point `p` appears at `p × scale + offset`). Every canvas (backdrop, links, highlights, pulses) is the size of the window and draws through the camera; cards and speed chips are SwiftUI views placed through the camera and scaled with `scaleEffect`. Only what is on screen is drawn. A drag or pinch moves the camera on screen through gesture state and commits it when the gesture ends. The scroll-wheel monitor zooms for a mouse wheel and pans for trackpad scrolls and modified wheels, since no scroll view is left to take them.

**Why.** The graph used to be one canvas the size of the whole layout inside a scroll view, enlarged with `scaleEffect`. On a real dock with 27 devices that caused three problems:

- **Blur.** `scaleEffect` enlarges a `Canvas` as a bitmap, so links went soft above 100 %. SwiftUI text and shapes stay sharp under `scaleEffect`; canvases do not. (Corrected the same day: cards and chips were also enlarged as bitmaps; see "Map cards and chips render after the zoom".)
- **Lag.** Every canvas covered the whole layout, the pulse canvas redrew it 30 times a second, and the backdrop rebuilt its whole dot grid at every zoom step.
- **Panning.** A scroll view only moves within its content, so a graph that fits the window could not be dragged at all. Pan state also came from geometry callbacks that lag behind programmatic scrolls, which is the likeliest cause of a second drag snapping the map back.

**Rejected alternatives.**

- *Draw the canvases at the zoomed size inside the scroll view.* This keeps the scroll view but makes each canvas `layout × scale` large: several hundred megabytes of bitmap at 200 % on this graph, and slower, not faster.
- *Pad the scroll view's content by half a window on every side.* Tried first, to allow free panning. It quadrupled the area of every full-graph canvas, made the lag worse and still depended on the scroll view's geometry callbacks.
- *Keep the camera in `TopologyGraphView`.* Its body builds the layout and the strokes. A camera there would rebuild them on every frame of a drag, so the camera is read only by `GraphMap`.
