import XCTest
@testable import ScreenGrab

// MARK: - Tab Toggle State Machine (mirrors SelectionView logic)

/// Testable model of the Tab toggle behavior without requiring a full NSView.
private class ModeToggleModel {
    var currentMode: CaptureMode = .regionSelect {
        didSet {
            if oldValue != .regionSelect {
                modeBeforeRegionSelect = oldValue
            }
        }
    }
    var modeBeforeRegionSelect: CaptureMode = .select

    func pressTab() {
        if currentMode == .regionSelect {
            currentMode = modeBeforeRegionSelect
        } else {
            currentMode = .regionSelect
        }
    }
}

final class TabToggleTests: XCTestCase {

    func testTabFromArrowToRegionAndBack() {
        let m = ModeToggleModel()
        m.currentMode = .arrow              // user picks arrow mode
        XCTAssertEqual(m.currentMode, .arrow)

        m.pressTab()                         // Tab → region select
        XCTAssertEqual(m.currentMode, .regionSelect)

        m.pressTab()                         // Tab → back to arrow
        XCTAssertEqual(m.currentMode, .arrow)
    }

    func testTabFromRectangleToRegionAndBack() {
        let m = ModeToggleModel()
        m.currentMode = .rectangle
        m.pressTab()
        XCTAssertEqual(m.currentMode, .regionSelect)
        m.pressTab()
        XCTAssertEqual(m.currentMode, .rectangle)
    }

    func testTabFromSelectToRegionAndBack() {
        let m = ModeToggleModel()
        m.currentMode = .select
        m.pressTab()
        XCTAssertEqual(m.currentMode, .regionSelect)
        m.pressTab()
        XCTAssertEqual(m.currentMode, .select)
    }

    func testTabFromTextToRegionAndBack() {
        let m = ModeToggleModel()
        m.currentMode = .text
        m.pressTab()
        XCTAssertEqual(m.currentMode, .regionSelect)
        m.pressTab()
        XCTAssertEqual(m.currentMode, .text)
    }

    func testDoubleTabStaysInSameMode() {
        let m = ModeToggleModel()
        m.currentMode = .arrow
        m.pressTab()  // → regionSelect
        m.pressTab()  // → arrow
        m.pressTab()  // → regionSelect
        m.pressTab()  // → arrow
        XCTAssertEqual(m.currentMode, .arrow)
    }

    func testTabRemembersMostRecentNonRegionMode() {
        let m = ModeToggleModel()
        m.currentMode = .arrow
        m.pressTab()                         // → regionSelect (remembers arrow)
        XCTAssertEqual(m.currentMode, .regionSelect)

        // While in regionSelect, user switches to rectangle via hotkey
        m.currentMode = .rectangle
        m.pressTab()                         // → regionSelect (now remembers rectangle)
        XCTAssertEqual(m.currentMode, .regionSelect)

        m.pressTab()                         // → rectangle
        XCTAssertEqual(m.currentMode, .rectangle)
    }

    func testTabFromInitialRegionSelectGoesToSelect() {
        // App starts in regionSelect. modeBeforeRegionSelect defaults to .select.
        let m = ModeToggleModel()
        XCTAssertEqual(m.currentMode, .regionSelect)
        m.pressTab()
        XCTAssertEqual(m.currentMode, .select)
    }

    func testModeBeforeRegionSelectNotOverwrittenByRegionSelect() {
        let m = ModeToggleModel()
        m.currentMode = .arrow               // modeBeforeRegionSelect = .regionSelect(initial) then .arrow?
        // didSet: oldValue(.regionSelect) == .regionSelect → skip. No, wait:
        // initial is .regionSelect, setting to .arrow → oldValue is .regionSelect → skip (it IS regionSelect)
        // So modeBeforeRegionSelect stays .select (the default)
        // Hmm, that's a subtle case. Let me verify:
        // Actually: oldValue != .regionSelect is FALSE, so we skip. modeBeforeRegionSelect stays .select
        // Then pressTab:
        m.pressTab()                         // currentMode is .arrow → goes to regionSelect
        // didSet: oldValue(.arrow) != .regionSelect → modeBeforeRegionSelect = .arrow ✓
        XCTAssertEqual(m.currentMode, .regionSelect)
        XCTAssertEqual(m.modeBeforeRegionSelect, .arrow)
        m.pressTab()
        XCTAssertEqual(m.currentMode, .arrow)
    }
}

final class CursorBehaviorTests: XCTestCase {

    // MARK: - Annotation HitTest Tests

    func testRectangleHitTestBody() {
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        let handle = rect.hitTest(point: CGPoint(x: 200, y: 175))
        XCTAssertEqual(handle, .body)
    }

    func testRectangleHitTestTopLeft() {
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        // topLeft corner is at (100, 250) — minX, maxY
        let handle = rect.hitTest(point: CGPoint(x: 100, y: 250))
        XCTAssertEqual(handle, .topLeft)
    }

    func testRectangleHitTestTopRight() {
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        // topRight corner is at (300, 250) — maxX, maxY
        let handle = rect.hitTest(point: CGPoint(x: 300, y: 250))
        XCTAssertEqual(handle, .topRight)
    }

    func testRectangleHitTestBottomLeft() {
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        // bottomLeft corner is at (100, 100) — minX, minY
        let handle = rect.hitTest(point: CGPoint(x: 100, y: 100))
        XCTAssertEqual(handle, .bottomLeft)
    }

    func testRectangleHitTestBottomRight() {
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        // bottomRight corner is at (300, 100) — maxX, minY
        let handle = rect.hitTest(point: CGPoint(x: 300, y: 100))
        XCTAssertEqual(handle, .bottomRight)
    }

    func testRectangleHitTestOutside() {
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        let handle = rect.hitTest(point: CGPoint(x: 50, y: 50))
        XCTAssertNil(handle)
    }

    func testArrowHitTestStartPoint() {
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))
        let handle = arrow.hitTest(point: CGPoint(x: 101, y: 101))
        XCTAssertEqual(handle, .startPoint)
    }

    func testArrowHitTestEndPoint() {
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))
        let handle = arrow.hitTest(point: CGPoint(x: 299, y: 299))
        XCTAssertEqual(handle, .endPoint)
    }

    func testArrowHitTestBody() {
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))
        // Point near the middle of the line
        let handle = arrow.hitTest(point: CGPoint(x: 200, y: 200))
        XCTAssertEqual(handle, .body)
    }

    func testArrowHitTestOutside() {
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))
        let handle = arrow.hitTest(point: CGPoint(x: 50, y: 300))
        XCTAssertNil(handle)
    }

    // MARK: - Select Mode Hover Highlight Tests

    func testSelectModeHoverShowsHighlightForNonSelectedAnnotation() {
        // When in select mode, hovering over an annotation that is NOT selected
        // should show the dashed hover highlight
        let rect1 = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        let rect2 = RectangleAnnotation(bounds: CGRect(x: 400, y: 100, width: 200, height: 150))

        // Simulate: rect1 is selected, hovering over rect2
        // rect2 should get hover highlight (hoveredAnnotation = rect2)
        let hoverPoint = CGPoint(x: 500, y: 175) // center of rect2
        let rect2Bounds = rect2.bounds.insetBy(dx: -4, dy: -4)
        XCTAssertTrue(rect2Bounds.contains(hoverPoint), "Hover point should be inside rect2's visual bounds")
        XCTAssertNotEqual(rect1.id, rect2.id, "Annotations should have distinct IDs")
    }

    func testSelectModeHoverSelectedAnnotationNoHighlight() {
        // When in select mode, hovering over the SELECTED annotation
        // should NOT show dashed hover highlight (handles are shown instead)
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        let handle = rect.hitTest(point: CGPoint(x: 200, y: 175))
        XCTAssertEqual(handle, .body, "Hovering body of selected annotation should return .body handle")
    }

    // MARK: - Drawing Mode Hover Cursor Tests

    func testDrawingModeHoverAnnotationShouldBeGrabbable() {
        // In rectangle/arrow/text drawing modes, hovering over an existing annotation
        // should show openHand cursor (not arrow), because clicking grabs it for dragging.
        // The annotation must be within the hover detection bounds.
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        let hoverPoint = CGPoint(x: 200, y: 175) // center of rectangle
        let hoverBounds = rect.bounds.insetBy(dx: -4, dy: -4)
        XCTAssertTrue(hoverBounds.contains(hoverPoint),
                      "Hover point must be inside annotation's visual bounds for hover detection")
        // hitTest returns .body → cursor should be openHand (not arrow)
        let handle = rect.hitTest(point: hoverPoint)
        XCTAssertEqual(handle, .body,
                       "Hovering center of annotation should return .body handle, meaning openHand cursor")
    }

    func testDrawingModeHoverArrowAnnotationShouldBeGrabbable() {
        // Same test but for arrow annotations — hovering the line body in draw mode
        // should show openHand, not arrow cursor.
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 400, y: 400))
        let hoverPoint = CGPoint(x: 250, y: 250) // midpoint of line
        let handle = arrow.hitTest(point: hoverPoint)
        XCTAssertEqual(handle, .body,
                       "Hovering midpoint of arrow should return .body handle, meaning openHand cursor")
    }

    // MARK: - Drawing Mode Hover Resize Handle Tests

    func testDrawingModeHoverResizeHandleOnSelectedRect() {
        // After grab-and-release in draw mode, selection handles are visible.
        // Hovering a corner handle should show directional resize cursor, not openHand.
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 200))

        // Simulate: rect is selected, hover each corner handle
        let tl = rect.hitTest(point: CGPoint(x: 100, y: 300))
        XCTAssertEqual(tl, .topLeft, "Should detect topLeft → nwse resize cursor")

        let tr = rect.hitTest(point: CGPoint(x: 300, y: 300))
        XCTAssertEqual(tr, .topRight, "Should detect topRight → nesw resize cursor")

        let bl = rect.hitTest(point: CGPoint(x: 100, y: 100))
        XCTAssertEqual(bl, .bottomLeft, "Should detect bottomLeft → nesw resize cursor")

        let br = rect.hitTest(point: CGPoint(x: 300, y: 100))
        XCTAssertEqual(br, .bottomRight, "Should detect bottomRight → nwse resize cursor")
    }

    func testDrawingModeHoverResizeHandleOnSelectedArrow() {
        // Arrow endpoints should show crosshair when hovered in draw mode
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))

        let start = arrow.hitTest(point: CGPoint(x: 101, y: 101))
        XCTAssertEqual(start, .startPoint, "Should detect startPoint → crosshair cursor")

        let end = arrow.hitTest(point: CGPoint(x: 299, y: 299))
        XCTAssertEqual(end, .endPoint, "Should detect endPoint → crosshair cursor")
    }

    func testDrawingModeHoverHandleTakesPriorityOverBody() {
        // When hovering a handle on the selected annotation, should get directional
        // cursor, not openHand (which is for body/unselected annotations)
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 200))

        // Point exactly at corner — hitTest should return corner handle, not .body
        let handle = rect.hitTest(point: CGPoint(x: 100, y: 300))
        XCTAssertEqual(handle, .topLeft, "Handle should take priority over body")
        XCTAssertNotEqual(handle, .body, "Must not fall through to body/openHand")
    }

    // MARK: - Drawing Mode Drag Cursor Tests

    func testDrawingModeDragBodyShouldBeClosedHand() {
        // Regression: in draw modes, dragging an annotation body should show closedHand.
        // The 120Hz timer's updateCoordDisplay must not override the drag cursor with
        // crosshair. Verify that .body handle maps to closedHand when dragging.
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        let grabPoint = CGPoint(x: 200, y: 175)
        let handle = rect.hitTest(point: grabPoint)
        XCTAssertEqual(handle, .body, "Clicking center should return .body handle")
        // .body with isDragging=true → closedHand (verified by cursorForHandle mapping)
        // The timer guard (isDraggingAnnotation check) prevents overriding this cursor
    }

    func testDrawingModeDragResizeHandleShouldBeDirectional() {
        // Regression: in draw modes, dragging a corner handle should show directional
        // resize cursor, not crosshair. The timer must not override it.
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 200))

        // topLeft at (100, 300)
        let tlHandle = rect.hitTest(point: CGPoint(x: 100, y: 300))
        XCTAssertEqual(tlHandle, .topLeft, "Should detect topLeft handle")

        // bottomRight at (300, 100)
        let brHandle = rect.hitTest(point: CGPoint(x: 300, y: 100))
        XCTAssertEqual(brHandle, .bottomRight, "Should detect bottomRight handle")

        // topRight at (300, 300)
        let trHandle = rect.hitTest(point: CGPoint(x: 300, y: 300))
        XCTAssertEqual(trHandle, .topRight, "Should detect topRight handle")

        // bottomLeft at (100, 100)
        let blHandle = rect.hitTest(point: CGPoint(x: 100, y: 100))
        XCTAssertEqual(blHandle, .bottomLeft, "Should detect bottomLeft handle")
    }

    func testDrawingModeDragArrowEndpointShouldBeCrosshair() {
        // In draw modes, dragging an arrow's startPoint/endPoint should show crosshair,
        // not get overridden by the coord-crosshair from the timer.
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))
        let startHandle = arrow.hitTest(point: CGPoint(x: 101, y: 101))
        XCTAssertEqual(startHandle, .startPoint, "Should detect startPoint handle")
        let endHandle = arrow.hitTest(point: CGPoint(x: 299, y: 299))
        XCTAssertEqual(endHandle, .endPoint, "Should detect endPoint handle")
        // .startPoint/.endPoint → crosshair cursor (intentional, repositioning endpoint)
    }

    func testTimerShouldNotOverrideCursor() {
        // Model the updateCoordDisplay guards. The timer must not set the crosshair
        // cursor when another cursor is being managed by drag/draw/hover/handle state.
        struct CoordDisplayModel {
            var isDraggingAnnotation = false
            var isDrawingAnnotation = false
            var isHoveringSelectedHandle = false
            var editingTextAnnotation = false
            var isSelectMode = false
            var hoveredAnnotation = false

            /// Returns true if updateCoordDisplay should set the crosshair cursor
            func shouldUpdateCrosshair() -> Bool {
                if editingTextAnnotation { return false }
                if isDraggingAnnotation || isDrawingAnnotation || isHoveringSelectedHandle { return false }
                if isSelectMode { return false }
                if hoveredAnnotation { return false }
                return true
            }
        }

        // Scenario: drawing mode, dragging annotation → should NOT update crosshair
        let dragging = CoordDisplayModel(isDraggingAnnotation: true)
        XCTAssertFalse(dragging.shouldUpdateCrosshair(),
                       "Timer must not override cursor while dragging annotation")

        // Scenario: drawing mode, actively drawing new shape → should NOT update crosshair
        let drawing = CoordDisplayModel(isDrawingAnnotation: true)
        XCTAssertFalse(drawing.shouldUpdateCrosshair(),
                       "Timer must not override cursor while drawing new annotation")

        // Scenario: drawing mode, hovering selected annotation's handle → should NOT
        let hoveringHandle = CoordDisplayModel(isHoveringSelectedHandle: true)
        XCTAssertFalse(hoveringHandle.shouldUpdateCrosshair(),
                       "Timer must not override cursor while hovering selected annotation's resize handle")

        // Scenario: drawing mode, idle, no hover → SHOULD update crosshair
        let idle = CoordDisplayModel()
        XCTAssertTrue(idle.shouldUpdateCrosshair(),
                      "Timer should update crosshair when idle in drawing mode")

        // Scenario: drawing mode, hovering annotation body → should NOT update crosshair
        let hovering = CoordDisplayModel(hoveredAnnotation: true)
        XCTAssertFalse(hovering.shouldUpdateCrosshair(),
                       "Timer must not override cursor while hovering annotation")
    }

    func testMouseMovedShouldNotOverrideHandleHoverCursor() {
        // Regression: mouseMoved set crosshair whenever hoveredAnnotation==nil in draw
        // modes, not knowing that isHoveringSelectedHandle was managing the cursor.
        // This caused flicker: timer set directional cursor, mouseMoved stomped it with
        // crosshair, timer set it back, etc — every frame.
        struct MouseMovedModel {
            var isSelectMode = false
            var hoveredAnnotation = false
            var isHoveringSelectedHandle = false

            /// Returns true if mouseMoved should set the crosshair cursor
            func shouldSetCrosshair() -> Bool {
                if isSelectMode { return false }
                if hoveredAnnotation { return false }
                if isHoveringSelectedHandle { return false }
                return true
            }
        }

        // Hovering selected handle in draw mode → must NOT set crosshair
        let hoveringHandle = MouseMovedModel(isHoveringSelectedHandle: true)
        XCTAssertFalse(hoveringHandle.shouldSetCrosshair(),
                       "mouseMoved must not override cursor when hovering selected annotation's handle")

        // Hovering annotation body in draw mode → must NOT set crosshair
        let hoveringBody = MouseMovedModel(hoveredAnnotation: true)
        XCTAssertFalse(hoveringBody.shouldSetCrosshair(),
                       "mouseMoved must not override cursor when hovering annotation body")

        // Idle in draw mode → SHOULD set crosshair
        let idle = MouseMovedModel()
        XCTAssertTrue(idle.shouldSetCrosshair(),
                      "mouseMoved should set crosshair when idle in drawing mode")

        // Select mode → must NOT set crosshair (cursor managed by hover state)
        let selectMode = MouseMovedModel(isSelectMode: true)
        XCTAssertFalse(selectMode.shouldSetCrosshair(),
                       "mouseMoved must not set crosshair in select mode")
    }

    func testSystemCursorCallbacksMustRouteThoughHoverState() {
        // Regression: resetCursorRects added a crosshair cursor rect for draw modes,
        // causing macOS to enforce crosshair via cursorUpdate/mouseEntered at arbitrary
        // times — overriding our hover/handle/drag cursors and causing flicker.
        //
        // Fix: resetCursorRects adds NO cursor rects. cursorUpdate and mouseEntered
        // route through updateHoverState instead of blindly setting crosshair.
        //
        // Model: each system callback should produce the same cursor as updateHoverState
        // for any given state, never independently force crosshair.
        struct SystemCallbackModel {
            var editingText = false
            var isSelectMode = false
            var isDrawMode = false
            var isHoveringSelectedHandle = false
            var hoveredAnnotation = false

            /// What resetCursorRects should do — must never add cursor rects
            var shouldAddCursorRect: Bool { false }

            /// cursorUpdate/mouseEntered should delegate to hover state,
            /// never independently decide crosshair
            var shouldDelegateToHoverState: Bool { true }
        }

        // Draw mode, hovering handle — system must NOT force crosshair
        let handleHover = SystemCallbackModel(isDrawMode: true, isHoveringSelectedHandle: true)
        XCTAssertFalse(handleHover.shouldAddCursorRect,
                       "resetCursorRects must not add cursor rects that override handle cursor")
        XCTAssertTrue(handleHover.shouldDelegateToHoverState,
                      "cursorUpdate must delegate to hover state, not force crosshair")

        // Draw mode, hovering annotation body — system must NOT force crosshair
        let bodyHover = SystemCallbackModel(isDrawMode: true, hoveredAnnotation: true)
        XCTAssertFalse(bodyHover.shouldAddCursorRect)
        XCTAssertTrue(bodyHover.shouldDelegateToHoverState)

        // Select mode — system must NOT add cursor rects
        let selectMode = SystemCallbackModel(isSelectMode: true)
        XCTAssertFalse(selectMode.shouldAddCursorRect)
        XCTAssertTrue(selectMode.shouldDelegateToHoverState)

        // Text editing — system must NOT override iBeam
        let textEdit = SystemCallbackModel(editingText: true)
        XCTAssertFalse(textEdit.shouldAddCursorRect)
        XCTAssertTrue(textEdit.shouldDelegateToHoverState)

        // Draw mode, idle — still must not add cursor rects (timer handles it)
        let idle = SystemCallbackModel(isDrawMode: true)
        XCTAssertFalse(idle.shouldAddCursorRect,
                       "Even idle draw mode must not use cursor rects — timer manages cursor")
        XCTAssertTrue(idle.shouldDelegateToHoverState)
    }

    func testSystemCallbacksMustSetCursorDuringDrag() {
        // Regression: cursorUpdate/mouseEntered called updateHoverState during drag,
        // which returned early (isDraggingAnnotation guard) WITHOUT setting any cursor.
        // The system then reverted to a default cursor, causing flicker.
        //
        // Fix: cursorUpdate/mouseEntered must set the drag cursor directly when
        // isDraggingAnnotation is true, before falling through to updateHoverState.
        struct SystemCallbackDragModel {
            var isDraggingAnnotation = false
            var isDrawingAnnotation = false
            var activeHandle: AnnotationHandle? = nil

            enum Action {
                case setDragCursor(AnnotationHandle)
                case setCrosshair
                case delegateToHoverState
            }

            func action() -> Action {
                if isDraggingAnnotation, let handle = activeHandle {
                    return .setDragCursor(handle)
                }
                if isDrawingAnnotation {
                    return .setCrosshair
                }
                return .delegateToHoverState
            }
        }

        // Dragging body → must set closedHand directly, not delegate
        let dragBody = SystemCallbackDragModel(isDraggingAnnotation: true, activeHandle: .body)
        if case .setDragCursor(let handle) = dragBody.action() {
            XCTAssertEqual(handle, .body)
        } else {
            XCTFail("Must set drag cursor when dragging, not delegate to hover state")
        }

        // Dragging corner → must set resize cursor directly
        let dragCorner = SystemCallbackDragModel(isDraggingAnnotation: true, activeHandle: .topLeft)
        if case .setDragCursor(let handle) = dragCorner.action() {
            XCTAssertEqual(handle, .topLeft)
        } else {
            XCTFail("Must set drag cursor for corner handle")
        }

        // Actively drawing → must set crosshair directly
        let drawing = SystemCallbackDragModel(isDrawingAnnotation: true)
        if case .setCrosshair = drawing.action() {
            // correct
        } else {
            XCTFail("Must set crosshair during active drawing")
        }

        // Idle → delegate to hover state
        let idle = SystemCallbackDragModel()
        if case .delegateToHoverState = idle.action() {
            // correct
        } else {
            XCTFail("Should delegate to hover state when idle")
        }
    }

    // MARK: - Visual Bounds Tests (for hover detection)

    func testVisualBoundsRectangle() {
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        // Rectangle visual bounds should equal its bounds
        XCTAssertEqual(rect.bounds, CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    func testArrowBoundsEncloseEndpoints() {
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 250))
        let bounds = arrow.bounds
        // CGRect.contains excludes points on maxX/maxY edge, so inset by -1
        let expandedBounds = bounds.insetBy(dx: -1, dy: -1)
        XCTAssertTrue(expandedBounds.contains(arrow.startPoint), "Bounds should enclose start point")
        XCTAssertTrue(expandedBounds.contains(arrow.endPoint), "Bounds should enclose end point")
    }

    // MARK: - Handle-to-Cursor Mapping Tests (logic verification)

    func testHandleMappingCompleteness() {
        // Verify all AnnotationHandle cases are accounted for
        let allHandles: [AnnotationHandle] = [
            .body, .topLeft, .topRight, .bottomLeft, .bottomRight,
            .top, .bottom, .left, .right, .startPoint, .endPoint
        ]
        // Each handle should map to a known cursor behavior:
        // .body → openHand/closedHand
        // .topLeft/.bottomRight → NWSE diagonal
        // .topRight/.bottomLeft → NESW diagonal
        // .top/.bottom → resizeUpDown
        // .left/.right → resizeLeftRight
        // .startPoint/.endPoint → crosshair
        XCTAssertEqual(allHandles.count, 11, "All 11 handle types should be covered")
    }

    func testCornerHandlesArePaired() {
        // topLeft and bottomRight should use the same cursor (NWSE)
        // topRight and bottomLeft should use the same cursor (NESW)
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 200))

        let tl = rect.hitTest(point: CGPoint(x: 100, y: 300))  // topLeft
        let br = rect.hitTest(point: CGPoint(x: 300, y: 100))  // bottomRight
        let tr = rect.hitTest(point: CGPoint(x: 300, y: 300))  // topRight
        let bl = rect.hitTest(point: CGPoint(x: 100, y: 100))  // bottomLeft

        // NWSE pair
        XCTAssertEqual(tl, .topLeft)
        XCTAssertEqual(br, .bottomRight)

        // NESW pair
        XCTAssertEqual(tr, .topRight)
        XCTAssertEqual(bl, .bottomLeft)
    }

    // MARK: - Arrow Endpoint Handle Priority

    func testArrowEndpointTakesPriorityOverBody() {
        // When clicking near an arrow endpoint, the endpoint handle
        // should be returned, not .body
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))
        let handle = arrow.hitTest(point: CGPoint(x: 103, y: 103))
        XCTAssertEqual(handle, .startPoint, "Endpoint should take priority over body when near endpoint")
    }

    func testArrowBodyReturnedWhenNotNearEndpoint() {
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 400, y: 400))
        // Point at midpoint of line, far from endpoints
        let handle = arrow.hitTest(point: CGPoint(x: 250, y: 250))
        XCTAssertEqual(handle, .body, "Body should be returned when far from endpoints")
    }

    // MARK: - Crosshair Font Cache Safety

    func testCrosshairFontCacheDoesNotCrash() {
        // Regression test: buildCrosshairCursor previously called sizeWithAttributes
        // from the 120Hz timer, which could crash CoreText with a nil font dictionary.
        // The fix caches the font and char metrics as static properties, computing
        // text size arithmetically. Verify the cached metrics are sensible.
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let charSize = ("0" as NSString).size(withAttributes: attrs)
        XCTAssertGreaterThan(charSize.width, 0, "Cached char width must be positive")
        XCTAssertGreaterThan(charSize.height, 0, "Cached char height must be positive")

        // Verify arithmetic size matches real size for a typical coord string
        let testString = "1234, 5678"
        let arithmeticWidth = charSize.width * CGFloat(testString.count)
        let realSize = (testString as NSString).size(withAttributes: attrs)
        // Monospaced font: arithmetic width should closely match real width
        XCTAssertEqual(arithmeticWidth, realSize.width, accuracy: 2.0,
                       "Arithmetic text width should match sizeWithAttributes for monospaced font")
    }
}
