import XCTest
@testable import ScreenGrab

// MARK: - Selection State Machine Model

/// Testable model of annotation selection lifecycle in draw modes.
/// Mirrors the state transitions in SelectionView without requiring NSView.
private class SelectionModel {
    var annotations: [RectangleAnnotation] = []
    var selectedAnnotation: RectangleAnnotation?
    var hasSelectionHandles = false
    var isDraggingAnnotation = false
    var isDrawingAnnotation = false
    var hoveredAnnotation: RectangleAnnotation?
    var isHoveringSelectedHandle = false

    /// Simulate clicking on empty space in draw mode → start drawing
    func clickEmptySpace() {
        // Deselect
        selectedAnnotation = nil
        hasSelectionHandles = false
        // Start drawing
        isDrawingAnnotation = true
    }

    /// Simulate finishing drawing a new rectangle
    func finishDrawing(bounds: CGRect) {
        isDrawingAnnotation = false
        let annotation = RectangleAnnotation(bounds: bounds)
        annotations.append(annotation)
        // Drawing completion does NOT auto-select
    }

    /// Simulate clicking on an existing annotation in draw mode → grab it
    func clickAnnotation(_ annotation: RectangleAnnotation) {
        selectedAnnotation = annotation
        hasSelectionHandles = true
        isDraggingAnnotation = true
    }

    /// Simulate releasing after drag
    func releaseDrag() {
        isDraggingAnnotation = false
    }

    /// Simulate hover state update at a point
    func updateHover(at point: CGPoint) {
        guard !isDraggingAnnotation && !isDrawingAnnotation else { return }

        isHoveringSelectedHandle = false

        // Check selected annotation handles first
        if let selected = selectedAnnotation, let handle = selected.hitTest(point: point) {
            hoveredAnnotation = nil
            isHoveringSelectedHandle = true
            return
        }

        // Check all annotations for body hover
        for annotation in annotations.reversed() {
            let rect = annotation.bounds.insetBy(dx: -4, dy: -4)
            if rect.contains(point) {
                hoveredAnnotation = annotation
                return
            }
        }

        hoveredAnnotation = nil
    }

    /// What cursor should be shown (models updateCoordDisplay guard logic)
    var shouldShowCrosshairCoords: Bool {
        if isDraggingAnnotation || isDrawingAnnotation || isHoveringSelectedHandle { return false }
        if hoveredAnnotation != nil { return false }
        return true
    }
}

// MARK: - Tests

final class SelectionLifecycleTests: XCTestCase {

    // MARK: - Deselection on Draw

    func testDrawingNewRectangleDeselectsPrevious() {
        let model = SelectionModel()
        let rect1 = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        model.annotations.append(rect1)

        // Grab rect1
        model.clickAnnotation(rect1)
        XCTAssertNotNil(model.selectedAnnotation)
        XCTAssertTrue(model.hasSelectionHandles)

        model.releaseDrag()

        // Click empty space to start drawing new rectangle
        model.clickEmptySpace()
        XCTAssertNil(model.selectedAnnotation, "Starting to draw should deselect previous annotation")
        XCTAssertFalse(model.hasSelectionHandles, "Selection handles should be removed when drawing starts")
    }

    func testDrawingCompletionDoesNotAutoSelect() {
        let model = SelectionModel()

        model.clickEmptySpace()
        model.finishDrawing(bounds: CGRect(x: 50, y: 50, width: 100, height: 80))

        XCTAssertNil(model.selectedAnnotation, "Newly drawn rectangle should not be auto-selected")
        XCTAssertFalse(model.hasSelectionHandles, "No handles should appear for unselected annotation")
        XCTAssertEqual(model.annotations.count, 1)
    }

    func testDrawSecondRectangleFirstStaysDeselected() {
        let model = SelectionModel()

        // Draw first rectangle
        model.clickEmptySpace()
        model.finishDrawing(bounds: CGRect(x: 50, y: 50, width: 100, height: 80))

        // Draw second rectangle
        model.clickEmptySpace()
        model.finishDrawing(bounds: CGRect(x: 300, y: 300, width: 120, height: 90))

        XCTAssertNil(model.selectedAnnotation, "No annotation should be selected after drawing")
        XCTAssertEqual(model.annotations.count, 2)
    }

    func testGrabThenDrawDeselectsGrabbed() {
        let model = SelectionModel()
        let rect1 = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        model.annotations.append(rect1)

        // Grab rect1
        model.clickAnnotation(rect1)
        model.releaseDrag()
        XCTAssertEqual(model.selectedAnnotation?.id, rect1.id)

        // Draw a new rectangle (click empty space)
        model.clickEmptySpace()
        XCTAssertNil(model.selectedAnnotation, "Grabbed annotation should be deselected when starting to draw")

        model.finishDrawing(bounds: CGRect(x: 400, y: 400, width: 100, height: 100))
        XCTAssertNil(model.selectedAnnotation, "Still no selection after draw completes")
    }

    // MARK: - Click to Select/Deselect

    func testClickAnnotationSelectsIt() {
        let model = SelectionModel()
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        model.annotations.append(rect)

        model.clickAnnotation(rect)
        XCTAssertEqual(model.selectedAnnotation?.id, rect.id)
        XCTAssertTrue(model.hasSelectionHandles)
    }

    func testClickEmptySpaceDeselects() {
        let model = SelectionModel()
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        model.annotations.append(rect)

        model.clickAnnotation(rect)
        model.releaseDrag()

        model.clickEmptySpace()
        XCTAssertNil(model.selectedAnnotation, "Clicking empty space should deselect")
        XCTAssertFalse(model.hasSelectionHandles)
    }

    func testClickDifferentAnnotationSwitchesSelection() {
        let model = SelectionModel()
        let rect1 = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        let rect2 = RectangleAnnotation(bounds: CGRect(x: 400, y: 100, width: 200, height: 150))
        model.annotations.append(rect1)
        model.annotations.append(rect2)

        model.clickAnnotation(rect1)
        model.releaseDrag()
        XCTAssertEqual(model.selectedAnnotation?.id, rect1.id)

        model.clickAnnotation(rect2)
        model.releaseDrag()
        XCTAssertEqual(model.selectedAnnotation?.id, rect2.id, "Should switch to newly clicked annotation")
    }

    // MARK: - Hover/Cursor After Drawing

    func testCursorInsideJustDrawnRectangleShowsOpenHand() {
        let model = SelectionModel()
        model.clickEmptySpace()
        model.finishDrawing(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))

        // Mouse is inside the just-drawn rectangle
        model.updateHover(at: CGPoint(x: 200, y: 175))

        XCTAssertNotNil(model.hoveredAnnotation, "Should detect hover on the new rectangle")
        XCTAssertFalse(model.shouldShowCrosshairCoords, "Timer should not show crosshair — annotation is hovered")
    }

    func testCursorOutsideAnnotationsShowsCrosshair() {
        let model = SelectionModel()
        model.clickEmptySpace()
        model.finishDrawing(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))

        // Mouse outside all annotations
        model.updateHover(at: CGPoint(x: 500, y: 500))

        XCTAssertNil(model.hoveredAnnotation, "No annotation should be hovered")
        XCTAssertTrue(model.shouldShowCrosshairCoords, "Timer should show crosshair with coords")
    }

    func testCursorDuringDrawSuppressesCrosshairUpdate() {
        let model = SelectionModel()
        model.clickEmptySpace()  // isDrawingAnnotation = true

        XCTAssertTrue(model.isDrawingAnnotation)
        XCTAssertFalse(model.shouldShowCrosshairCoords, "Timer must not override cursor during active drawing")
    }

    func testCursorDuringDragSuppressesCrosshairUpdate() {
        let model = SelectionModel()
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        model.annotations.append(rect)

        model.clickAnnotation(rect)
        XCTAssertTrue(model.isDraggingAnnotation)
        XCTAssertFalse(model.shouldShowCrosshairCoords, "Timer must not override cursor during drag")
    }

    // MARK: - Hover on Selected Annotation Handles

    func testHoverSelectedHandleSuppressesCrosshair() {
        let model = SelectionModel()
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 200))
        model.annotations.append(rect)

        model.clickAnnotation(rect)
        model.releaseDrag()

        // Hover a corner handle of the selected annotation
        model.updateHover(at: CGPoint(x: 100, y: 300))  // topLeft

        XCTAssertTrue(model.isHoveringSelectedHandle, "Should detect handle hover on selected annotation")
        XCTAssertFalse(model.shouldShowCrosshairCoords, "Timer must not show crosshair when hovering handle")
    }

    func testHoverSelectedBodyShowsOpenHand() {
        let model = SelectionModel()
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 200))
        model.annotations.append(rect)

        model.clickAnnotation(rect)
        model.releaseDrag()

        // Hover center of selected annotation (body, not handle)
        model.updateHover(at: CGPoint(x: 200, y: 200))

        // hitTest at center returns .body, which still sets isHoveringSelectedHandle
        // because it's the selected annotation and hitTest returns a handle
        XCTAssertTrue(model.isHoveringSelectedHandle)
    }

    func testHoverNothingAfterDeselect() {
        let model = SelectionModel()
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        model.annotations.append(rect)

        model.clickAnnotation(rect)
        model.releaseDrag()
        model.clickEmptySpace()  // deselect + start drawing
        model.isDrawingAnnotation = false  // simulate completing without drawing

        // Hover outside all annotations
        model.updateHover(at: CGPoint(x: 500, y: 500))

        XCTAssertNil(model.hoveredAnnotation)
        XCTAssertFalse(model.isHoveringSelectedHandle)
        XCTAssertTrue(model.shouldShowCrosshairCoords, "Should show crosshair when nothing is hovered or selected")
    }

    // MARK: - No Hover Updates During Active Operations

    func testNoHoverUpdateDuringDrag() {
        let model = SelectionModel()
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        model.annotations.append(rect)

        model.clickAnnotation(rect)
        // While dragging, hover update should be skipped
        model.updateHover(at: CGPoint(x: 500, y: 500))

        XCTAssertNil(model.hoveredAnnotation, "Hover should not update during drag")
    }

    func testNoHoverUpdateDuringDraw() {
        let model = SelectionModel()
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))
        model.annotations.append(rect)

        model.clickEmptySpace()
        // While drawing, hover update should be skipped
        model.updateHover(at: CGPoint(x: 200, y: 175))

        XCTAssertNil(model.hoveredAnnotation, "Hover should not update during active drawing")
    }

    // MARK: - Multiple Annotations Hover Priority

    func testHoverDetectsTopAnnotation() {
        let model = SelectionModel()
        let bottom = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 200))
        let top = RectangleAnnotation(bounds: CGRect(x: 150, y: 150, width: 200, height: 200))
        model.annotations.append(bottom)
        model.annotations.append(top)

        // Point in overlapping area
        model.updateHover(at: CGPoint(x: 200, y: 200))

        XCTAssertEqual(model.hoveredAnnotation?.id, top.id,
                       "Should hover the topmost (last-added) annotation in overlap area")
    }

    func testSelectedHandleTakesPriorityOverOtherAnnotationHover() {
        let model = SelectionModel()
        let selected = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 200))
        let other = RectangleAnnotation(bounds: CGRect(x: 90, y: 290, width: 50, height: 50))
        model.annotations.append(selected)
        model.annotations.append(other)

        model.clickAnnotation(selected)
        model.releaseDrag()

        // Point at topLeft handle of selected (100, 300), which also overlaps 'other'
        model.updateHover(at: CGPoint(x: 100, y: 300))

        XCTAssertTrue(model.isHoveringSelectedHandle,
                      "Selected annotation's handle should take priority over other annotation body")
        XCTAssertNil(model.hoveredAnnotation,
                     "hoveredAnnotation should be nil when hovering selected handle")
    }
}
