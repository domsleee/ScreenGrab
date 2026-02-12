import XCTest
@testable import ScreenGrab

// MARK: - Context Menu Model (mirrors SelectionView arrange/clipboard logic)

/// Testable model of the context menu actions without requiring a full NSView.
/// Uses the real annotation types and SelectionView.AnnotationSnapshot.
private class ContextMenuModel {
    var annotations: [any Annotation] = []
    var selectedAnnotation: (any Annotation)?
    var copiedAnnotationSnapshot: SelectionView.AnnotationSnapshot?
    var undoStack: [[SelectionView.AnnotationSnapshot]] = []
    var redoStack: [[SelectionView.AnnotationSnapshot]] = []

    func snapshotAnnotations() -> [SelectionView.AnnotationSnapshot] {
        annotations.map { annotation in
            if let arrow = annotation as? ArrowAnnotation {
                return .arrow(id: arrow.id, startPoint: arrow.startPoint, endPoint: arrow.endPoint,
                              color: arrow.color, strokeWidth: arrow.strokeWidth)
            } else if let rect = annotation as? RectangleAnnotation {
                return .rectangle(id: rect.id, bounds: rect.bounds, color: rect.color, strokeWidth: rect.strokeWidth)
            } else if let text = annotation as? TextAnnotation {
                return .text(id: text.id, text: text.text, position: text.position,
                             fontSize: text.fontSize, color: text.color, backgroundColor: text.backgroundColor,
                             backgroundPadding: text.backgroundPadding)
            }
            fatalError("Unknown annotation type")
        }
    }

    func restoreAnnotations(from snapshots: [SelectionView.AnnotationSnapshot]) {
        annotations = snapshots.map { snapshot in
            switch snapshot {
            case .arrow(let id, let startPoint, let endPoint, let color, let strokeWidth):
                return ArrowAnnotation(id: id, startPoint: startPoint, endPoint: endPoint,
                                       color: color, strokeWidth: strokeWidth)
            case .rectangle(let id, let bounds, let color, let strokeWidth):
                return RectangleAnnotation(id: id, bounds: bounds, color: color, strokeWidth: strokeWidth)
            case .text(let id, let text, let position, let fontSize, let color, let backgroundColor, let backgroundPadding):
                return TextAnnotation(id: id, text: text, position: position, fontSize: fontSize, color: color, backgroundColor: backgroundColor, backgroundPadding: backgroundPadding)
            }
        }

        if let selectedId = selectedAnnotation?.id {
            selectedAnnotation = annotations.first { $0.id == selectedId }
        } else {
            selectedAnnotation = nil
        }
    }

    func pushUndoState() {
        undoStack.append(snapshotAnnotations())
        redoStack.removeAll()
    }

    func performUndo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshotAnnotations())
        restoreAnnotations(from: previous)
    }

    func performRedo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshotAnnotations())
        restoreAnnotations(from: next)
    }

    // MARK: - Helpers

    @discardableResult
    func addRectangle(bounds: CGRect, color: CGColor = NSColor.red.cgColor) -> RectangleAnnotation {
        let annotation = RectangleAnnotation(bounds: bounds, color: color)
        annotations.append(annotation)
        return annotation
    }

    @discardableResult
    func addArrow(start: CGPoint, end: CGPoint, color: CGColor = NSColor.red.cgColor) -> ArrowAnnotation {
        let annotation = ArrowAnnotation(startPoint: start, endPoint: end, color: color)
        annotations.append(annotation)
        return annotation
    }

    @discardableResult
    func addText(text: String, position: CGPoint, fontSize: CGFloat = 24,
                 color: CGColor = NSColor.white.cgColor,
                 backgroundColor: CGColor? = nil, backgroundPadding: CGFloat = 4) -> TextAnnotation {
        let annotation = TextAnnotation(text: text, position: position, fontSize: fontSize,
                                        color: color, backgroundColor: backgroundColor,
                                        backgroundPadding: backgroundPadding)
        annotations.append(annotation)
        return annotation
    }

    /// Returns array of annotation IDs in current order (for order assertions)
    var order: [UUID] { annotations.map { $0.id } }

    // MARK: - Arrange Actions (mirrors SelectionView)

    func bringSelectedToFront() {
        guard let selected = selectedAnnotation,
              let index = annotations.firstIndex(where: { $0.id == selected.id }),
              index < annotations.count - 1 else { return }
        pushUndoState()
        let annotation = annotations.remove(at: index)
        annotations.append(annotation)
    }

    func bringSelectedForward() {
        guard let selected = selectedAnnotation,
              let index = annotations.firstIndex(where: { $0.id == selected.id }),
              index < annotations.count - 1 else { return }
        pushUndoState()
        annotations.swapAt(index, index + 1)
    }

    func sendSelectedBackward() {
        guard let selected = selectedAnnotation,
              let index = annotations.firstIndex(where: { $0.id == selected.id }),
              index > 0 else { return }
        pushUndoState()
        annotations.swapAt(index, index - 1)
    }

    func sendSelectedToBack() {
        guard let selected = selectedAnnotation,
              let index = annotations.firstIndex(where: { $0.id == selected.id }),
              index > 0 else { return }
        pushUndoState()
        let annotation = annotations.remove(at: index)
        annotations.insert(annotation, at: 0)
    }

    // MARK: - Clipboard Actions (mirrors SelectionView)

    func copySelectedAnnotation() {
        guard let selected = selectedAnnotation else { return }
        copiedAnnotationSnapshot = snapshotAnnotations().first { snapshot in
            switch snapshot {
            case .arrow(let id, _, _, _, _): return id == selected.id
            case .rectangle(let id, _, _, _): return id == selected.id
            case .text(let id, _, _, _, _, _, _): return id == selected.id
            }
        }
    }

    func cutSelectedAnnotation() {
        copySelectedAnnotation()
        deleteSelectedAnnotation()
    }

    func pasteAnnotation(at point: NSPoint? = nil) {
        guard let snapshot = copiedAnnotationSnapshot else { return }
        pushUndoState()

        let offset: CGFloat = point == nil ? 20 : 0
        let newAnnotation: any Annotation

        switch snapshot {
        case .arrow(_, let startPoint, let endPoint, let color, let strokeWidth):
            let dx = point.map { $0.x - startPoint.x } ?? offset
            let dy = point.map { $0.y - startPoint.y } ?? offset
            newAnnotation = ArrowAnnotation(
                startPoint: CGPoint(x: startPoint.x + dx, y: startPoint.y + dy),
                endPoint: CGPoint(x: endPoint.x + dx, y: endPoint.y + dy),
                color: color, strokeWidth: strokeWidth
            )
        case .rectangle(_, let bounds, let color, let strokeWidth):
            let dx = point.map { $0.x - bounds.midX } ?? offset
            let dy = point.map { $0.y - bounds.midY } ?? offset
            newAnnotation = RectangleAnnotation(
                bounds: CGRect(x: bounds.origin.x + dx, y: bounds.origin.y + dy,
                               width: bounds.width, height: bounds.height),
                color: color, strokeWidth: strokeWidth
            )
        case .text(_, let text, let position, let fontSize, let color, let backgroundColor, let backgroundPadding):
            let dx = point.map { $0.x - position.x } ?? offset
            let dy = point.map { $0.y - position.y } ?? offset
            newAnnotation = TextAnnotation(
                text: text, position: CGPoint(x: position.x + dx, y: position.y + dy),
                fontSize: fontSize, color: color, backgroundColor: backgroundColor,
                backgroundPadding: backgroundPadding
            )
        }

        annotations.append(newAnnotation)
        selectedAnnotation = newAnnotation
    }

    func duplicateSelectedAnnotation() {
        guard selectedAnnotation != nil else { return }
        copySelectedAnnotation()
        pasteAnnotation()
    }

    func deleteSelectedAnnotation() {
        guard let selected = selectedAnnotation else { return }
        pushUndoState()
        annotations.removeAll { $0.id == selected.id }
        selectedAnnotation = nil
    }
}

// MARK: - Tests

final class ContextMenuTests: XCTestCase {

    // MARK: - Bring Forward

    func testBringForwardMovesUpOneLevel() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))

        m.selectedAnnotation = a
        m.bringSelectedForward()

        XCTAssertEqual(m.order, [b.id, a.id, c.id], "A should move from index 0 to index 1")
    }

    func testBringForwardOnTopIsNoOp() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))

        m.selectedAnnotation = b
        let orderBefore = m.order
        m.bringSelectedForward()

        XCTAssertEqual(m.order, orderBefore, "Top annotation should not move")
        XCTAssertTrue(m.undoStack.isEmpty, "No undo state should be pushed for no-op")
    }

    // MARK: - Bring to Front

    func testBringToFrontMovesToTop() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))
        let d = m.addRectangle(bounds: CGRect(x: 300, y: 0, width: 50, height: 50))

        m.selectedAnnotation = a
        m.bringSelectedToFront()

        XCTAssertEqual(m.order, [b.id, c.id, d.id, a.id], "A should move from index 0 to last")
    }

    func testBringToFrontOnTopIsNoOp() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))

        m.selectedAnnotation = b
        let orderBefore = m.order
        m.bringSelectedToFront()

        XCTAssertEqual(m.order, orderBefore)
        XCTAssertTrue(m.undoStack.isEmpty)
    }

    // MARK: - Send Backward

    func testSendBackwardMovesDownOneLevel() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))

        m.selectedAnnotation = c
        m.sendSelectedBackward()

        XCTAssertEqual(m.order, [a.id, c.id, b.id], "C should move from index 2 to index 1")
    }

    func testSendBackwardOnBottomIsNoOp() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))

        m.selectedAnnotation = a
        let orderBefore = m.order
        m.sendSelectedBackward()

        XCTAssertEqual(m.order, orderBefore)
        XCTAssertTrue(m.undoStack.isEmpty)
    }

    // MARK: - Send to Back

    func testSendToBackMovesToBottom() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))
        let d = m.addRectangle(bounds: CGRect(x: 300, y: 0, width: 50, height: 50))

        m.selectedAnnotation = d
        m.sendSelectedToBack()

        XCTAssertEqual(m.order, [d.id, a.id, b.id, c.id], "D should move from last to index 0")
    }

    func testSendToBackOnBottomIsNoOp() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))

        m.selectedAnnotation = a
        let orderBefore = m.order
        m.sendSelectedToBack()

        XCTAssertEqual(m.order, orderBefore)
        XCTAssertTrue(m.undoStack.isEmpty)
    }

    // MARK: - Arrange with No Selection

    func testArrangeWithNoSelectionIsNoOp() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let orderBefore = m.order

        m.bringSelectedForward()
        m.bringSelectedToFront()
        m.sendSelectedBackward()
        m.sendSelectedToBack()

        XCTAssertEqual(m.order, orderBefore, "No arrange should happen without selection")
        XCTAssertTrue(m.undoStack.isEmpty)
    }

    // MARK: - Arrange with Single Annotation

    func testArrangeWithSingleAnnotationIsNoOp() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a

        m.bringSelectedForward()
        m.bringSelectedToFront()
        m.sendSelectedBackward()
        m.sendSelectedToBack()

        XCTAssertEqual(m.annotations.count, 1)
        XCTAssertTrue(m.undoStack.isEmpty, "No undo state pushed for no-op on single annotation")
    }

    // MARK: - Arrange Preserves Relative Order of Others

    func testBringToFrontPreservesRelativeOrder() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))
        let d = m.addRectangle(bounds: CGRect(x: 300, y: 0, width: 50, height: 50))
        let e = m.addRectangle(bounds: CGRect(x: 400, y: 0, width: 50, height: 50))

        m.selectedAnnotation = b
        m.bringSelectedToFront()

        // B removed from index 1, others shift down, B appended at end
        XCTAssertEqual(m.order, [a.id, c.id, d.id, e.id, b.id])
    }

    func testSendToBackPreservesRelativeOrder() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))
        let d = m.addRectangle(bounds: CGRect(x: 300, y: 0, width: 50, height: 50))
        let e = m.addRectangle(bounds: CGRect(x: 400, y: 0, width: 50, height: 50))

        m.selectedAnnotation = d
        m.sendSelectedToBack()

        XCTAssertEqual(m.order, [d.id, a.id, b.id, c.id, e.id])
    }

    // MARK: - Arrange + Undo

    func testBringForwardUndo() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))
        let originalOrder = m.order

        m.selectedAnnotation = a
        m.bringSelectedForward()
        XCTAssertEqual(m.order, [b.id, a.id, c.id])

        m.performUndo()
        XCTAssertEqual(m.order, originalOrder, "Undo should restore original order")
    }

    func testSendToBackUndoRedo() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))
        let originalOrder = m.order

        m.selectedAnnotation = c
        m.sendSelectedToBack()
        let reorderedOrder = m.order
        XCTAssertEqual(reorderedOrder, [c.id, a.id, b.id])

        m.performUndo()
        XCTAssertEqual(m.order, originalOrder)

        m.performRedo()
        XCTAssertEqual(m.order, reorderedOrder)
    }

    func testMultipleArrangeUndos() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))

        // Move A forward twice (to top)
        m.selectedAnnotation = a
        m.bringSelectedForward() // [B, A, C]
        m.bringSelectedForward() // [B, C, A]

        XCTAssertEqual(m.order, [b.id, c.id, a.id])

        m.performUndo() // [B, A, C]
        XCTAssertEqual(m.order, [b.id, a.id, c.id])

        m.performUndo() // [A, B, C]
        XCTAssertEqual(m.order, [a.id, b.id, c.id])
    }

    // MARK: - Arrange with Mixed Annotation Types

    func testArrangeWithMixedTypes() {
        let m = ContextMenuModel()
        let rect = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let arrow = m.addArrow(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 200, y: 200))
        let text = m.addText(text: "Hello", position: CGPoint(x: 50, y: 50))

        m.selectedAnnotation = rect
        m.bringSelectedToFront()

        XCTAssertEqual(m.order, [arrow.id, text.id, rect.id])
        XCTAssertTrue(m.annotations[0] is ArrowAnnotation)
        XCTAssertTrue(m.annotations[1] is TextAnnotation)
        XCTAssertTrue(m.annotations[2] is RectangleAnnotation)
    }

    // MARK: - Copy

    func testCopyStoresSnapshot() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 100, y: 200, width: 50, height: 50))
        m.selectedAnnotation = a

        m.copySelectedAnnotation()

        XCTAssertNotNil(m.copiedAnnotationSnapshot)
    }

    func testCopyWithNoSelectionIsNoOp() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))

        m.copySelectedAnnotation()

        XCTAssertNil(m.copiedAnnotationSnapshot)
    }

    func testCopyDoesNotModifyAnnotations() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a

        let countBefore = m.annotations.count
        m.copySelectedAnnotation()

        XCTAssertEqual(m.annotations.count, countBefore, "Copy should not add or remove annotations")
        XCTAssertTrue(m.undoStack.isEmpty, "Copy should not push undo state")
    }

    // MARK: - Paste

    func testPasteCreatesNewAnnotationWithOffset() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.pasteAnnotation()

        XCTAssertEqual(m.annotations.count, 2)
        let pasted = m.annotations[1] as! RectangleAnnotation
        XCTAssertEqual(pasted.bounds.origin.x, 120, accuracy: 0.01, "Pasted should be offset +20 in x")
        XCTAssertEqual(pasted.bounds.origin.y, 120, accuracy: 0.01, "Pasted should be offset +20 in y")
        XCTAssertEqual(pasted.bounds.width, 50, accuracy: 0.01, "Width should be preserved")
        XCTAssertEqual(pasted.bounds.height, 50, accuracy: 0.01, "Height should be preserved")
    }

    func testPasteAtPointCentersOnPoint() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        let pastePoint = NSPoint(x: 400, y: 300)
        m.pasteAnnotation(at: pastePoint)

        let pasted = m.annotations[1] as! RectangleAnnotation
        // paste at point offsets from bounds.midX/midY of original
        let dx = pastePoint.x - 125  // midX of original (100 + 50/2)
        let dy = pastePoint.y - 125  // midY of original (100 + 50/2)
        XCTAssertEqual(pasted.bounds.origin.x, 100 + dx, accuracy: 0.01)
        XCTAssertEqual(pasted.bounds.origin.y, 100 + dy, accuracy: 0.01)
    }

    func testPasteWithEmptyClipboardIsNoOp() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))

        m.pasteAnnotation()

        XCTAssertEqual(m.annotations.count, 1, "No new annotation should be created")
        XCTAssertTrue(m.undoStack.isEmpty)
    }

    func testPastedAnnotationHasNewUUID() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.pasteAnnotation()

        XCTAssertNotEqual(m.annotations[0].id, m.annotations[1].id,
                          "Pasted annotation must have a different UUID")
    }

    func testPasteSelectsNewAnnotation() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.pasteAnnotation()

        XCTAssertEqual(m.selectedAnnotation?.id, m.annotations.last?.id,
                       "Pasted annotation should become selected")
    }

    func testMultiplePastesCreateDistinctAnnotations() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.pasteAnnotation()
        m.pasteAnnotation()
        m.pasteAnnotation()

        XCTAssertEqual(m.annotations.count, 4)
        let ids = Set(m.annotations.map { $0.id })
        XCTAssertEqual(ids.count, 4, "All annotations should have unique UUIDs")
    }

    // MARK: - Paste Preserves Properties

    func testPastePreservesRectangleProperties() {
        let m = ContextMenuModel()
        let color = NSColor.blue.cgColor
        let a = m.addRectangle(bounds: CGRect(x: 50, y: 60, width: 200, height: 100), color: color)
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.pasteAnnotation()

        let pasted = m.annotations[1] as! RectangleAnnotation
        XCTAssertEqual(pasted.bounds.width, 200, accuracy: 0.01)
        XCTAssertEqual(pasted.bounds.height, 100, accuracy: 0.01)
        XCTAssertEqual(pasted.color.components, color.components)
        XCTAssertEqual(pasted.strokeWidth, a.strokeWidth)
    }

    func testPastePreservesArrowProperties() {
        let m = ContextMenuModel()
        let color = NSColor.green.cgColor
        let a = m.addArrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 300, y: 400), color: color)
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.pasteAnnotation()

        let pasted = m.annotations[1] as! ArrowAnnotation
        // Arrow should be offset by +20 in both axes
        XCTAssertEqual(pasted.startPoint.x, 30, accuracy: 0.01)
        XCTAssertEqual(pasted.startPoint.y, 40, accuracy: 0.01)
        XCTAssertEqual(pasted.endPoint.x, 320, accuracy: 0.01)
        XCTAssertEqual(pasted.endPoint.y, 420, accuracy: 0.01)
        XCTAssertEqual(pasted.color.components, color.components)
    }

    func testPastePreservesTextProperties() {
        let m = ContextMenuModel()
        let bgColor = NSColor.yellow.withAlphaComponent(0.5).cgColor
        let fgColor = NSColor.black.cgColor
        let a = m.addText(text: "Hello World", position: CGPoint(x: 100, y: 200),
                          fontSize: 36, color: fgColor, backgroundColor: bgColor, backgroundPadding: 8)
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.pasteAnnotation()

        let pasted = m.annotations[1] as! TextAnnotation
        XCTAssertEqual(pasted.text, "Hello World")
        XCTAssertEqual(pasted.fontSize, 36)
        XCTAssertEqual(pasted.color.components, fgColor.components)
        XCTAssertNotNil(pasted.backgroundColor)
        XCTAssertEqual(pasted.backgroundColor?.components, bgColor.components)
        XCTAssertEqual(pasted.backgroundPadding, 8)
    }

    // MARK: - Cut

    func testCutRemovesAndStoresSnapshot() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        m.selectedAnnotation = a

        m.cutSelectedAnnotation()

        XCTAssertEqual(m.annotations.count, 0, "Cut should remove annotation")
        XCTAssertNotNil(m.copiedAnnotationSnapshot, "Cut should store snapshot")
        XCTAssertNil(m.selectedAnnotation, "Selection should be cleared after cut")
    }

    func testCutWithNoSelectionIsNoOp() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))

        m.cutSelectedAnnotation()

        XCTAssertEqual(m.annotations.count, 1)
        XCTAssertNil(m.copiedAnnotationSnapshot)
    }

    func testCutThenPasteEffectivelyMoves() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        m.selectedAnnotation = a

        m.cutSelectedAnnotation()
        XCTAssertEqual(m.annotations.count, 0)

        m.pasteAnnotation(at: NSPoint(x: 300, y: 400))
        XCTAssertEqual(m.annotations.count, 1)

        let pasted = m.annotations[0] as! RectangleAnnotation
        // Paste at point offsets from midX/midY
        let dx = 300 - 125.0  // midX of original
        let dy = 400 - 125.0
        XCTAssertEqual(pasted.bounds.origin.x, 100 + dx, accuracy: 0.01)
        XCTAssertEqual(pasted.bounds.origin.y, 100 + dy, accuracy: 0.01)
    }

    // MARK: - Duplicate

    func testDuplicateCreatesOffsetCopy() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        m.selectedAnnotation = a

        m.duplicateSelectedAnnotation()

        XCTAssertEqual(m.annotations.count, 2)
        XCTAssertNotEqual(m.annotations[0].id, m.annotations[1].id)
        let dup = m.annotations[1] as! RectangleAnnotation
        XCTAssertEqual(dup.bounds.origin.x, 120, accuracy: 0.01, "Duplicate should offset +20")
        XCTAssertEqual(dup.bounds.origin.y, 120, accuracy: 0.01)
    }

    func testDuplicateWithNoSelectionIsNoOp() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))

        m.duplicateSelectedAnnotation()

        XCTAssertEqual(m.annotations.count, 1)
    }

    func testDuplicateSelectsNewAnnotation() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a

        m.duplicateSelectedAnnotation()

        XCTAssertNotEqual(m.selectedAnnotation?.id, a.id,
                          "Selection should move to duplicate, not original")
        XCTAssertEqual(m.selectedAnnotation?.id, m.annotations.last?.id)
    }

    // MARK: - Delete

    func testDeleteRemovesSelectedAnnotation() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a

        m.deleteSelectedAnnotation()

        XCTAssertEqual(m.annotations.count, 1)
        XCTAssertNil(m.selectedAnnotation)
    }

    func testDeleteWithNoSelectionIsNoOp() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))

        m.deleteSelectedAnnotation()

        XCTAssertEqual(m.annotations.count, 1)
        XCTAssertTrue(m.undoStack.isEmpty)
    }

    // MARK: - Clipboard Survives Delete

    func testClipboardSurvivesDeleteOfOriginal() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        // Delete the original
        m.deleteSelectedAnnotation()
        XCTAssertEqual(m.annotations.count, 0)

        // Paste should still work
        m.pasteAnnotation()
        XCTAssertEqual(m.annotations.count, 1, "Clipboard should survive deletion of source")
    }

    // MARK: - Copy Overwrites Previous Clipboard

    func testCopyOverwritesPreviousClipboard() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addArrow(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 200, y: 200))

        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.selectedAnnotation = b
        m.copySelectedAnnotation()

        m.pasteAnnotation()

        // Last pasted should be an arrow (from b), not a rectangle (from a)
        XCTAssertTrue(m.annotations.last is ArrowAnnotation,
                      "Paste should use the most recent copy, not the first")
    }

    // MARK: - Paste + Undo

    func testPasteUndoRemovesPastedOnly() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.pasteAnnotation()
        XCTAssertEqual(m.annotations.count, 2)

        m.performUndo()
        XCTAssertEqual(m.annotations.count, 1)
        XCTAssertEqual(m.annotations[0].id, a.id, "Original should remain after undo of paste")
    }

    func testCutUndoRestoresAnnotation() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 100, y: 100, width: 50, height: 50))
        let originalId = a.id
        m.selectedAnnotation = a

        m.cutSelectedAnnotation()
        XCTAssertEqual(m.annotations.count, 0)

        m.performUndo()
        XCTAssertEqual(m.annotations.count, 1)
        XCTAssertEqual(m.annotations[0].id, originalId, "Undo cut should restore original annotation")
    }

    func testDuplicateUndoRemovesDuplicate() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a

        m.duplicateSelectedAnnotation()
        XCTAssertEqual(m.annotations.count, 2)

        m.performUndo()
        XCTAssertEqual(m.annotations.count, 1)
        XCTAssertEqual(m.annotations[0].id, a.id)
    }

    // MARK: - Arrange + Clipboard Combined

    func testArrangeAfterPaste() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        m.pasteAnnotation()
        let pasted = m.annotations.last!
        // pasted is now at top: [a, b, pasted]

        m.selectedAnnotation = pasted
        m.sendSelectedToBack()
        // should now be [pasted, a, b]

        XCTAssertEqual(m.order, [pasted.id, a.id, b.id])
    }

    // MARK: - Bring Forward from Middle

    func testBringForwardFromMiddle() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))
        let d = m.addRectangle(bounds: CGRect(x: 300, y: 0, width: 50, height: 50))

        m.selectedAnnotation = b
        m.bringSelectedForward()

        XCTAssertEqual(m.order, [a.id, c.id, b.id, d.id],
                       "B should swap with C only, leaving A and D in place")
    }

    // MARK: - Send Backward from Middle

    func testSendBackwardFromMiddle() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))
        let d = m.addRectangle(bounds: CGRect(x: 300, y: 0, width: 50, height: 50))

        m.selectedAnnotation = c
        m.sendSelectedBackward()

        XCTAssertEqual(m.order, [a.id, c.id, b.id, d.id],
                       "C should swap with B only, leaving A and D in place")
    }

    // MARK: - Selection Preserved After Arrange

    func testSelectionPreservedAfterBringForward() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a

        m.bringSelectedForward()

        XCTAssertEqual(m.selectedAnnotation?.id, a.id,
                       "Selected annotation should remain selected after arrange")
    }

    func testSelectionPreservedAfterSendToBack() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        m.selectedAnnotation = b

        m.sendSelectedToBack()

        XCTAssertEqual(m.selectedAnnotation?.id, b.id,
                       "Selected annotation should remain selected after send to back")
    }

    // MARK: - Consecutive Arrange Operations

    func testConsecutiveBringForwardReachesTop() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))

        m.selectedAnnotation = a
        m.bringSelectedForward() // [B, A, C]
        m.bringSelectedForward() // [B, C, A]

        XCTAssertEqual(m.order.last, a.id, "Two bring-forwards should reach the top")

        // Third bring forward should be no-op (already at top)
        let undoCountBefore = m.undoStack.count
        m.bringSelectedForward()
        XCTAssertEqual(m.undoStack.count, undoCountBefore, "No undo pushed when already at top")
    }

    func testConsecutiveSendBackwardReachesBottom() {
        let m = ContextMenuModel()
        m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        let c = m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))

        m.selectedAnnotation = c
        m.sendSelectedBackward() // [A, C, B]
        m.sendSelectedBackward() // [C, A, B]

        XCTAssertEqual(m.order.first, c.id, "Two send-backwards should reach the bottom")

        let undoCountBefore = m.undoStack.count
        m.sendSelectedBackward()
        XCTAssertEqual(m.undoStack.count, undoCountBefore, "No undo pushed when already at bottom")
    }

    // MARK: - Annotation Count Integrity

    func testArrangeNeverChangesAnnotationCount() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 100, y: 0, width: 50, height: 50))
        m.addRectangle(bounds: CGRect(x: 200, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a

        m.bringSelectedForward()
        XCTAssertEqual(m.annotations.count, 3)
        m.bringSelectedToFront()
        XCTAssertEqual(m.annotations.count, 3)
        m.sendSelectedBackward()
        XCTAssertEqual(m.annotations.count, 3)
        m.sendSelectedToBack()
        XCTAssertEqual(m.annotations.count, 3)
    }

    // MARK: - Paste Arrow at Specific Point

    func testPasteArrowAtPoint() {
        let m = ContextMenuModel()
        let a = m.addArrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 110, y: 120))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        let pastePoint = NSPoint(x: 500, y: 600)
        m.pasteAnnotation(at: pastePoint)

        let pasted = m.annotations[1] as! ArrowAnnotation
        // dx = 500 - 10 = 490, dy = 600 - 20 = 580
        XCTAssertEqual(pasted.startPoint.x, 500, accuracy: 0.01)
        XCTAssertEqual(pasted.startPoint.y, 600, accuracy: 0.01)
        XCTAssertEqual(pasted.endPoint.x, 600, accuracy: 0.01)
        XCTAssertEqual(pasted.endPoint.y, 700, accuracy: 0.01)
    }

    // MARK: - Paste Text at Specific Point

    func testPasteTextAtPoint() {
        let m = ContextMenuModel()
        let a = m.addText(text: "Test", position: CGPoint(x: 50, y: 60))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        let pastePoint = NSPoint(x: 200, y: 300)
        m.pasteAnnotation(at: pastePoint)

        let pasted = m.annotations[1] as! TextAnnotation
        // dx = 200 - 50 = 150, dy = 300 - 60 = 240
        XCTAssertEqual(pasted.position.x, 200, accuracy: 0.01)
        XCTAssertEqual(pasted.position.y, 300, accuracy: 0.01)
    }

    // MARK: - Stress Test

    func testRapidArrangeOperations() {
        let m = ContextMenuModel()
        for i in 0..<10 {
            m.addRectangle(bounds: CGRect(x: CGFloat(i * 60), y: 0, width: 50, height: 50))
        }
        XCTAssertEqual(m.annotations.count, 10)
        let ids = m.order

        // Send first annotation to front, then back, then forward, etc.
        m.selectedAnnotation = m.annotations[0]
        m.bringSelectedToFront()
        m.sendSelectedToBack()
        m.bringSelectedForward()
        m.sendSelectedBackward()

        // Should still have all 10 annotations with same set of IDs
        XCTAssertEqual(m.annotations.count, 10)
        XCTAssertEqual(Set(m.order), Set(ids), "All original IDs should still be present")
    }

    func testRapidCopyPasteDelete() {
        let m = ContextMenuModel()
        let a = m.addRectangle(bounds: CGRect(x: 0, y: 0, width: 50, height: 50))
        m.selectedAnnotation = a
        m.copySelectedAnnotation()

        // Paste 5 times
        for _ in 0..<5 {
            m.pasteAnnotation()
        }
        XCTAssertEqual(m.annotations.count, 6) // original + 5 pastes

        // Delete all pasted (selected is always the last paste)
        for _ in 0..<5 {
            m.deleteSelectedAnnotation()
            if let last = m.annotations.last {
                m.selectedAnnotation = last
            }
        }
        XCTAssertEqual(m.annotations.count, 1)
        XCTAssertEqual(m.annotations[0].id, a.id, "Original should remain")
    }

    // MARK: - Right-Click Hit Test (Bounding Box)

    /// Mirrors SelectionView.rightMouseDown hit testing: uses visualBounds + inset, not annotation.contains
    private func rightClickHitTest(annotations: [any Annotation], at point: CGPoint) -> (any Annotation)? {
        for annotation in annotations.reversed() {
            let rect = visualBounds(for: annotation).insetBy(dx: -4, dy: -4)
            if rect.contains(point) {
                return annotation
            }
        }
        return nil
    }

    /// Mirrors SelectionView.visualBounds
    private func visualBounds(for annotation: any Annotation) -> CGRect {
        if let arrow = annotation as? ArrowAnnotation {
            let geo = ArrowAnnotation.arrowGeometry(from: arrow.startPoint, to: arrow.endPoint,
                                                     headLength: arrow.arrowHeadLength, headAngle: arrow.arrowHeadAngle)
            let allX = [arrow.startPoint.x, arrow.endPoint.x, geo.point1.x, geo.point2.x]
            let allY = [arrow.startPoint.y, arrow.endPoint.y, geo.point1.y, geo.point2.y]
            let minX = allX.min() ?? 0, maxX = allX.max() ?? 0
            let minY = allY.min() ?? 0, maxY = allY.max() ?? 0
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return annotation.bounds
    }

    func testRightClickInArrowBoundingBoxHits() {
        // Diagonal arrow from (100,100) to (300,300)
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))

        // Point inside bounding box but far from the line (e.g. top-left corner area)
        let cornerPoint = CGPoint(x: 110, y: 290)

        // arrow.contains uses line proximity — should NOT hit
        XCTAssertFalse(arrow.contains(point: cornerPoint),
                       "Arrow line-proximity check should miss a corner point")

        // But bounding-box hit test (used by rightMouseDown) SHOULD hit
        let hit = rightClickHitTest(annotations: [arrow], at: cornerPoint)
        XCTAssertNotNil(hit, "Right-click should hit arrow via bounding box, not just line proximity")
        XCTAssertEqual(hit?.id, arrow.id)
    }

    func testRightClickOutsideArrowBoundingBoxMisses() {
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))

        // Point well outside the bounding box
        let outsidePoint = CGPoint(x: 50, y: 50)

        let hit = rightClickHitTest(annotations: [arrow], at: outsidePoint)
        XCTAssertNil(hit, "Right-click outside bounding box should miss")
    }

    func testRightClickOnArrowLineAlsoHits() {
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 300, y: 300))

        // Point right on the line (midpoint)
        let linePoint = CGPoint(x: 200, y: 200)

        let hit = rightClickHitTest(annotations: [arrow], at: linePoint)
        XCTAssertNotNil(hit, "Right-click on the line itself should also hit")
    }

    func testRightClickHitsTopmostOverlappingAnnotation() {
        let bottom = RectangleAnnotation(bounds: CGRect(x: 50, y: 50, width: 200, height: 200))
        let top = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 100), endPoint: CGPoint(x: 200, y: 200))
        let annotations: [any Annotation] = [bottom, top] // top is last = topmost

        // Point in the overlap area (inside arrow bounding box and rectangle)
        let overlapPoint = CGPoint(x: 150, y: 150)

        let hit = rightClickHitTest(annotations: annotations, at: overlapPoint)
        XCTAssertEqual(hit?.id, top.id, "Should hit topmost annotation (last in array)")
    }

    func testRightClickNearlyHorizontalArrowBoundingBox() {
        // Nearly horizontal arrow — very thin bounding box
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 100, y: 200), endPoint: CGPoint(x: 400, y: 205))

        // Point slightly above the line but within bounding box + 4px inset
        let nearPoint = CGPoint(x: 250, y: 208)

        let hit = rightClickHitTest(annotations: [arrow], at: nearPoint)
        XCTAssertNotNil(hit, "Should hit nearly horizontal arrow in bounding box")
    }

    func testRightClickNearlyVerticalArrowBoundingBox() {
        // Nearly vertical arrow — very narrow bounding box
        let arrow = ArrowAnnotation(startPoint: CGPoint(x: 200, y: 100), endPoint: CGPoint(x: 205, y: 400))

        // Point slightly to the side but within bounding box + 4px inset
        let nearPoint = CGPoint(x: 208, y: 250)

        let hit = rightClickHitTest(annotations: [arrow], at: nearPoint)
        XCTAssertNotNil(hit, "Should hit nearly vertical arrow in bounding box")
    }

    func testRightClickRectangleUsesNormalBounds() {
        let rect = RectangleAnnotation(bounds: CGRect(x: 100, y: 100, width: 200, height: 150))

        // Inside bounds
        let inside = CGPoint(x: 200, y: 175)
        XCTAssertNotNil(rightClickHitTest(annotations: [rect], at: inside))

        // Just outside bounds but within 4px inset tolerance
        let nearEdge = CGPoint(x: 97, y: 175)
        XCTAssertNotNil(rightClickHitTest(annotations: [rect], at: nearEdge),
                        "Should hit within 4px tolerance outside bounds")

        // Well outside
        let outside = CGPoint(x: 50, y: 50)
        XCTAssertNil(rightClickHitTest(annotations: [rect], at: outside))
    }
}
