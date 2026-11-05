import AppKit
import SwiftUI
import Combine

enum PanelKind: Hashable {
    /// One panel per head; a provider may own several.
    case provider(UUID)
    case account(UUID)
}

extension Notification.Name {
    static let bublrBeginDrag = Notification.Name("bublr.beginDrag")
    /// Always posted when the gesture ends (drag or plain click), with `moved` in `userInfo`.
    static let bublrEndDrag = Notification.Name("bublr.endDrag")
}

// MARK: - Floating panel

/// Borderless, transparent, always-on-top panel. It never activates the app on its own, so a
/// bubble can sit in front of the app you are working in without stealing focus.
final class BubblePanel: NSPanel {
    init(kind: PanelKind) {
        self.kind = kind
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
    }

    let kind: PanelKind

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .bublrEscape, object: self)
    }
}

extension Notification.Name {
    static let bublrEscape = Notification.Name("bublr.escape")
}

// MARK: - Drag handle

/// Moves the panel with `performDrag(with:)` — the API that actually drags borderless panels.
/// A press that never moves is reported back as a click.
struct WindowDragHandle: NSViewRepresentable {
    var onClick: (() -> Void)?

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {
        nsView.onClick = onClick
    }
}

final class DragHandleView: NSView {
    var onClick: (() -> Void)?

    private var pressScreen: NSPoint?
    private var pressOrigin: NSPoint?
    private(set) var didDrag = false

    override var acceptsFirstResponder: Bool { false }
    /// A bubble panel is rarely the key window; without this the first click is swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginDrag(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        continueDrag(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        finishDrag(clickCount: event.clickCount)
    }

    // MARK: Drag, in absolute screen coordinates

    /// Starts a drag at `screenPoint`. The window follows the pointer by the delta from this point,
    /// which is why the position is absolute rather than window-relative: a relative delta would be
    /// measured against the window we are moving, and the bubble would stand still.
    func beginDrag(at screenPoint: NSPoint) {
        guard let window else { return }
        pressScreen = screenPoint
        pressOrigin = window.frame.origin
        didDrag = false
        NotificationCenter.default.post(name: .bublrBeginDrag, object: window)
    }

    func continueDrag(to screenPoint: NSPoint) {
        guard let window, let start = pressScreen, let origin = pressOrigin else { return }
        let dx = screenPoint.x - start.x
        let dy = screenPoint.y - start.y
        if !didDrag && abs(dx) < 2 && abs(dy) < 2 { return }
        didDrag = true
        window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    /// Ends the gesture: a real drag is persisted by the overlay, a press without movement is a click.
    func finishDrag(clickCount: Int) {
        defer {
            pressScreen = nil
            pressOrigin = nil
            didDrag = false
        }
        guard let window else { return }
        let moved = didDrag
        // Posted for clicks too: the overlay must stop treating the panel as held even when it never moved.
        NotificationCenter.default.post(name: .bublrEndDrag, object: window, userInfo: ["moved": moved])
        if !moved && clickCount == 1 {
            onClick?()
        }
    }
}

// MARK: - Resize handle

struct WindowResizeHandle: NSViewRepresentable {
    var onResize: (CGSize) -> Void
    var onResizeEnd: (CGSize) -> Void

    func makeNSView(context: Context) -> ResizeHandleView {
        let view = ResizeHandleView()
        view.onResize = onResize
        view.onResizeEnd = onResizeEnd
        return view
    }

    func updateNSView(_ nsView: ResizeHandleView, context: Context) {
        nsView.onResize = onResize
        nsView.onResizeEnd = onResizeEnd
    }
}

final class ResizeHandleView: NSView {
    var onResize: ((CGSize) -> Void)?
    var onResizeEnd: ((CGSize) -> Void)?
    private var startFrame: CGRect = .zero
    private var startPoint: NSPoint = .zero
    private var didResize = false

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startFrame = window.frame
        startPoint = NSEvent.mouseLocation
        didResize = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = NSEvent.mouseLocation
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        let minW: CGFloat = 340
        let minH: CGFloat = 430
        let width = max(minW, min(980, startFrame.width + dx))
        let height = max(minH, min(1500, startFrame.height - dy))
        var frame = startFrame
        frame.origin.x = startFrame.minX
        frame.origin.y = startFrame.maxY - height
        frame.size = CGSize(width: width, height: height)
        window.setFrame(frame, display: true)
        didResize = true
        onResize?(frame.size)
    }

    override func mouseUp(with event: NSEvent) {
        guard let window, didResize else { return }
        onResizeEnd?(window.frame.size)
    }
}

// MARK: - Window accessor

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Overlay controller

final class OverlayController {
    private let workspace: Workspace
    private let sessions: WebSessionStore
    private var panels: [PanelKind: BubblePanel] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var moveObservers: [PanelKind: NSObjectProtocol] = [:]
    /// The top edge each bubble should keep while it grows or shrinks downwards.
    private var topAnchors: [PanelKind: CGFloat] = [:]
    private var snapping: Set<PanelKind> = []
    /// Panels currently under the user's pointer. Layout stays out of their way until the drag ends.
    private var userDragging: Set<PanelKind> = []
    /// A transition in flight: the frame it is growing into, and the moment it should have arrived.
    ///
    /// Neither possible completion signal can be trusted. `NSAnimationContext`'s completion handler never
    /// fires when the app gets no real display link (self-tests, a sleeping display), and `NSWindow`
    /// does not post `didMove` for a frame the animator set without moving the origin. So a transition is
    /// retired by a deadline instead: while `now < deadline`, moves and layout passes that disagree with
    /// `rect` are treated as frames of this animation, not as the user's choices.
    private struct Transition {
        let rect: CGRect
        let deadline: Date
    }
    private var transitions: [PanelKind: Transition] = [:]
    /// Click monitors watching for a click outside every bubble. `addLocalMonitorForEvents` returns nil when
    /// it cannot install, so the array holds optionals.
    private var clickMonitors: [Any?] = []
    private var isStarted = false
    private var isHiddenByUser = false

    init(workspace: Workspace, sessions: WebSessionStore) {
        self.workspace = workspace
        self.sessions = sessions
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        workspace.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.sync() }
            }
            .store(in: &cancellables)

        let dragBegin = NotificationCenter.default.addObserver(
            forName: .bublrBeginDrag, object: nil, queue: .main
        ) { [weak self] note in
            guard let panel = note.object as? BubblePanel else { return }
            self?.userDragging.insert(panel.kind)
        }
        observers.append(dragBegin)

        let dragObserver = NotificationCenter.default.addObserver(
            forName: .bublrEndDrag, object: nil, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow, let self else { return }
            guard let panel = window as? BubblePanel else { return }
            self.userDragging.remove(panel.kind)
            // A click only releases the panel; only a real drag updates and snaps the stored position.
            guard note.userInfo?["moved"] as? Bool == true else {
                self.sync(animated: false)
                return
            }
            self.topAnchors[panel.kind] = window.frame.maxY
            self.persist(window.frame, for: panel.kind)
            self.snapIfNeeded(window)
        }
        observers.append(dragObserver)

        startWatchingForOutsideClicks()
        sync(animated: false)
    }

    /// Collapse everything when the user clicks away from the bubbles.
    ///
    /// A *global* monitor only — deliberately. It receives events that go to another app or to the desktop,
    /// and it observes without consuming, so the click still lands wherever the user aimed it. It never sees
    /// clicks inside Bublr itself, which is the point:
    ///
    /// - clicking a second bubble focuses that one instead of collapsing the overlay out from under it;
    /// - right-clicking an account row opens its context menu without the bubble shrinking to a head first;
    /// - clicking the menu-bar item does not close the menu's own subject.
    ///
    /// A local monitor would need to tell those apart from a genuine click-away, and every rule for doing so
    /// was a guess about private window classes. The cost of leaving it out is that a click inside Bublr's
    /// own non-bubble window — the welcome window — does not collapse anything either.
    private func startWatchingForOutsideClicks() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        clickMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async { self?.collapseAllAfterClickAway() }
        })
    }

    private func collapseAllAfterClickAway() {
        guard workspace.collapseOnOutsideClick, !panels.isEmpty else { return }
        workspace.collapseAll()
    }

    func stop() {
        cancellables.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        clickMonitors.compactMap { $0 }.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
        moveObservers.values.forEach { NotificationCenter.default.removeObserver($0) }
        moveObservers.removeAll()
        panels.values.forEach { $0.close() }
        panels.removeAll()
        transitions.removeAll()
        isStarted = false
    }

    func sync(animated: Bool = true) {
        guard isStarted else { return }
        let kinds = desiredKinds()

        for (kind, panel) in panels where !kinds.contains(kind) {
            if let observer = moveObservers.removeValue(forKey: kind) {
                NotificationCenter.default.removeObserver(observer)
            }
            panel.orderOut(nil)
            panel.close()
            panels.removeValue(forKey: kind)
            topAnchors.removeValue(forKey: kind)
            snapping.remove(kind)
            userDragging.remove(kind)
        }

        for kind in kinds where panels[kind] == nil {
            panels[kind] = makePanel(for: kind)
        }

        for kind in kinds {
            guard let panel = panels[kind] else { continue }
            applyLayout(kind: kind, panel: panel, animated: animated)
        }

        updateVisibility()
    }

    func panel(for kind: PanelKind) -> BubblePanel? { panels[kind] }

    // MARK: Desired panels

    private func desiredKinds() -> Set<PanelKind> {
        var kinds = Set<PanelKind>()
        for bubble in workspace.bubbles { kinds.insert(.provider(bubble.id)) }
        for account in workspace.accounts where account.isFloating {
            kinds.insert(.account(account.id))
        }
        return kinds
    }

    private func makePanel(for kind: PanelKind) -> BubblePanel {
        let panel = BubblePanel(kind: kind)
        let root: AnyView
        switch kind {
        case .provider(let bubbleID):
            guard let state = workspace.bubble(id: bubbleID) else { return panel }
            root = AnyView(ProviderBubbleRoot(providerID: state.provider, bubbleID: bubbleID))
        case .account(let id):
            root = AnyView(FloatingAccountRoot(accountID: id))
        }
        let host = NSHostingView(rootView: root
            .environmentObject(workspace)
            .environmentObject(sessions))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        // Place the fresh panel exactly once, so the always-on-top window never appears at (0,0).
        if let target = targetLayout(for: kind) {
            let rect = clampedRect(CGRect(origin: target.origin, size: target.size), preferred: target.origin)
            panel.setFrame(rect, display: false)
            topAnchors[kind] = rect.maxY
            persist(rect, for: kind)
        }

        NotificationCenter.default.addObserver(
            forName: .bublrEscape, object: panel, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.handleEscape(panel) }
        }

        // A drag ends with the window somewhere new; persist it so the overlay returns there. A transition
        // also moves the window, frame by frame — those intermediate origins are not a user's choice.
        moveObservers[kind] = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            guard let self, let panel else { return }
            if let pending = self.runningTransition(kind) {
                // Only the move that lands on the stored rect ends a transition. Anything in between is a
                // frame the animation produced, and persisting it would store a size nobody chose.
                guard self.sameRect(pending, panel.frame) else { return }
                self.transitions.removeValue(forKey: kind)
            }
            guard !self.snapping.contains(kind), !self.userDragging.contains(kind) else { return }
            self.topAnchors[kind] = panel.frame.maxY
            self.persist(panel.frame, for: kind)
        }
        return panel
    }

    private func handleEscape(_ panel: BubblePanel) {
        switch panel.kind {
        case .provider(let bubbleID):
            guard let bubble = workspace.bubble(id: bubbleID) else { return }
            if bubble.drilledAccountID != nil {
                workspace.setDrill(nil, forBubble: bubbleID)
            } else if !bubble.collapsed {
                workspace.setCollapsed(true, forBubble: bubbleID)
            }
        case .account(let id):
            guard let account = workspace.account(id: id) else { return }
            workspace.setFloatingCollapsed(!account.floatingCollapsed, for: id)
        }
    }

    // MARK: Sizing

    private func targetLayout(for kind: PanelKind) -> (size: CGSize, origin: CGPoint)? {
        switch kind {
        case .provider(let bubbleID):
            guard let state = workspace.bubble(id: bubbleID) else { return nil }
            let count = workspace.accounts(for: state.provider).count
            // Only the head that opened the sign-in grows to the sign-in surface.
            let signingIn = workspace.pendingSignIns.contains {
                $0.account.provider == state.provider && ($0.bubbleID == nil || $0.bubbleID == bubbleID)
            }
            let drilled = state.drilledAccountID != nil
            let size: CGSize
            if state.collapsed {
                size = CGSize(width: Metrics.collapsedSide, height: Metrics.collapsedSide)
            } else if signingIn || drilled {
                size = CGSize(width: max(360, state.chatSize.width), height: max(460, state.chatSize.height))
            } else {
                size = CGSize(width: state.width, height: Metrics.expandedHeight(accountCount: count))
            }
            return (size, state.origin)
        case .account(let id):
            guard let account = workspace.account(id: id) else { return nil }
            let size: CGSize
            if account.floatingCollapsed {
                size = CGSize(width: Metrics.collapsedSide, height: Metrics.collapsedSide)
            } else {
                let stored = account.floatingSize ?? CGSize(width: Metrics.chatWidth, height: Metrics.chatHeight)
                size = CGSize(width: max(340, stored.width), height: max(430, stored.height))
            }
            let origin = account.floatingOrigin ?? CGPoint(x: 200, y: 200)
            return (size, origin)
        }
    }

    private func applyLayout(kind: PanelKind, panel: BubblePanel, animated: Bool) {
        // Never reposition a bubble the user is holding: a programmatic setFrame cancels the drag.
        guard !userDragging.contains(kind) else { return }
        guard let target = targetLayout(for: kind) else { return }
        let current = panel.frame

        // The user can drag a panel at any time; that move becomes the new anchor.
        if !snapping.contains(kind), current.size != .zero,
           let stored = topAnchors[kind], abs(current.maxY - stored) > 0.5 {
            topAnchors[kind] = current.maxY
        }
        let top = topAnchors[kind] ?? (target.origin.y + target.size.height)

        // Keep the top-left corner pinned while the bubble grows or shrinks downwards.
        let origin = CGPoint(x: target.origin.x, y: top - target.size.height)
        let rect = clampedRect(CGRect(origin: origin, size: target.size), preferred: origin)

        // A pass that recomputes the target an in-flight transition is already heading for has nothing to
        // do. Restarting it would cancel the animation and retarget it from a half-sized frame.
        if let pending = runningTransition(kind), sameRect(pending, rect) { return }

        let sizeChanged = abs(current.size.width - rect.size.width) > 0.5 || abs(current.size.height - rect.size.height) > 0.5
        let moved = abs(current.origin.x - rect.origin.x) > 0.5 || abs(current.origin.y - rect.origin.y) > 0.5

        if sizeChanged || moved {
            topAnchors[kind] = rect.maxY
            // Only a size change is worth animating: a clamp or a snap is a correction, not a transition,
            // and dragging must track the pointer with no lag at all.
            let duration = Motion.duration(from: current.size, to: rect.size, reduceMotion: Motion.reduceMotion)
            if animated, sizeChanged, duration > 0 {
                animate(kind: kind, panel: panel, to: rect, over: duration)
            } else {
                panel.setFrame(rect, display: true)
            }
            persist(rect, for: kind)
        }
    }

    private func animate(kind: PanelKind, panel: BubblePanel, to rect: CGRect, over duration: TimeInterval) {
        transitions[kind] = Transition(rect: rect, deadline: Date().addingTimeInterval(duration + 0.05))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(rect, display: true)
        }
    }

    /// The frame a transition is still growing into, or nil once its deadline has passed. Reading it is what
    /// retires an expired transition, so no timer or completion handler is needed anywhere.
    private func runningTransition(_ kind: PanelKind) -> CGRect? {
        guard let transition = transitions[kind] else { return nil }
        guard Date() < transition.deadline else {
            transitions.removeValue(forKey: kind)
            return nil
        }
        return transition.rect
    }

    private func sameRect(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < 0.5 && abs(a.origin.y - b.origin.y) < 0.5
            && abs(a.size.width - b.size.width) < 0.5 && abs(a.size.height - b.size.height) < 0.5
    }

    private func persist(_ rect: CGRect, for kind: PanelKind) {
        switch kind {
        case .provider(let bubbleID):
            guard let state = workspace.bubble(id: bubbleID) else { return }
            if abs(state.origin.x - rect.origin.x) > 0.5 || abs(state.origin.y - rect.origin.y) > 0.5 {
                workspace.setOrigin(rect.origin, forBubble: bubbleID)
            }
        case .account(let id):
            workspace.setFloatingOrigin(rect.origin, for: id)
        }
    }

    private func clampedRect(_ rect: CGRect, preferred: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(preferred) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return rect }
        var result = rect
        result.origin.x = min(max(rect.origin.x, visible.minX + 4), visible.maxX - rect.width - 4)
        result.origin.y = min(max(rect.origin.y, visible.minY + 4), visible.maxY - rect.height - 4)
        return result
    }

    private func snapIfNeeded(_ window: NSWindow) {
        guard let panel = window as? BubblePanel else { return }
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let threshold: CGFloat = 20
        var frame = window.frame
        if abs(frame.minX - visible.minX) < threshold { frame.origin.x = visible.minX }
        if abs(frame.maxX - visible.maxX) < threshold { frame.origin.x = visible.maxX - frame.width }
        if abs(frame.minY - visible.minY) < threshold { frame.origin.y = visible.minY }
        if abs(frame.maxY - visible.maxY) < threshold { frame.origin.y = visible.maxY - frame.height }
        guard frame.origin != window.frame.origin else { return }
        snapping.insert(panel.kind)
        panel.setFrame(frame, display: true)
        topAnchors[panel.kind] = frame.maxY
        persist(frame, for: panel.kind)
        snapping.remove(panel.kind)
    }

    // MARK: Visibility

    func updateVisibility() {
        let shouldShow = workspace.isVisible && !isHiddenByUser
        for panel in panels.values {
            if shouldShow {
                if !panel.isVisible { panel.orderFrontRegardless() }
            } else if panel.isVisible {
                panel.orderOut(nil)
            }
        }
    }

    func setHiddenByUser(_ hidden: Bool) {
        isHiddenByUser = hidden
        updateVisibility()
    }

    /// Focus a panel for typing (sign-in, chat) without activating other windows.
    func focus(_ kind: PanelKind) {
        guard let panel = panels[kind] else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Drag region

/// A draggable area that is allowed to contain only non-interactive content. Interactive controls
/// live next to it, never under it, because the AppKit handle sits above SwiftUI's drawing.
struct DragRegion<Content: View>: View {
    var onClick: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(WindowDragHandle(onClick: onClick))
    }
}
