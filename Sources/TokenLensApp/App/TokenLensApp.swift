import SwiftUI
import AppKit
import Combine
import QuartzCore

/// Debug logging — search "TokenLens" in Console.app
func tlog(_ msg: String) {
    NSLog("[TokenLens] \(msg)")
}

// Global reference for AppDelegate access
private var globalState: AppState?
var globalAppDelegate: AppDelegate?

@main
struct TokenLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState

    init() {
        tlog("=== TokenLens starting ===")

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("TokenLens")
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbURL = dbDir.appendingPathComponent("tokenlens.sqlite")
        tlog("DB path: \(dbURL.path)")

        let db: DatabaseManager
        do {
            db = try DatabaseManager(kind: .onDisk(dbURL))
            tlog("DB opened OK")
        } catch {
            tlog("DB ERROR: \(error)")
            fatalError("Cannot open database: \(error)")
        }

        let state = AppState(dbManager: db)
        state.refresh()
        tlog("State: \(state.recentUsages.count) recent usages")
        self._appState = StateObject(wrappedValue: state)

        // Expose to AppDelegate via globals (it's a macOS menu bar app, singleton-safe)
        globalState = state

        tlog("=== Init done ===")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        // Status item and popover are managed by AppDelegate via NSStatusItem.
        // Settings are opened manually via AppDelegate.openSettings().
    }
}

private final class MenuBarStatusRollView: NSView {
    private let verticalFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    private let horizontalFont = NSFont.menuBarFont(ofSize: 0)
    private let horizontalPadding: CGFloat = 6
    private var isVerticalLayout = false
    private var contentLayer: CALayer?
    private var rollTimers: [Timer] = []

    private enum TextRole: String {
        case primary
        case inputSymbol
        case outputSymbol
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var font: NSFont {
        isVerticalLayout ? verticalFont : horizontalFont
    }

    private var lineHeight: CGFloat {
        isVerticalLayout ? 10 : ceil(("0" as NSString).size(withAttributes: textAttributes).height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshTextLayerColors(in: contentLayer)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTextLayerColors(in: contentLayer)
    }

    func fittingWidth(for text: String, previousText: String?) -> CGFloat {
        let current = maxLineWidth(for: text, vertical: text.contains("\n"))
        let previous = previousText.map { maxLineWidth(for: $0, vertical: $0.contains("\n")) } ?? 0
        return ceil(max(current, previous) + horizontalPadding * 2)
    }

    func update(text: String, previousText: String?, animated: Bool) {
        guard let rootLayer = layer else { return }

        rollTimers.forEach { $0.invalidate() }
        rollTimers.removeAll()
        isVerticalLayout = text.contains("\n")

        let oldSegments = Dictionary(uniqueKeysWithValues: (previousText.map(parseSegments) ?? []).map { ($0.id, $0) })
        let newSegments = parseSegments(text)
        let lineCount = max((newSegments.map(\.line).max() ?? 0) + 1, 1)
        let totalHeight = CGFloat(lineCount) * lineHeight
        let bottomY = floor((bounds.height - totalHeight) / 2)

        let nextLayer = CALayer()
        nextLayer.frame = bounds
        nextLayer.masksToBounds = true
        rootLayer.addSublayer(nextLayer)

        for line in 0..<lineCount {
            let lineSegments = newSegments.filter { $0.line == line }
            let widths = lineSegments.map { segment in
                let w = ceil(measure(segment.text, fontSize: segment.fontSize))
                let old = oldSegments[segment.id].map { ceil(measure($0.text, fontSize: $0.fontSize)) } ?? 0
                return max(w, old)
            }
            let lineWidth = widths.reduce(0, +)
            var x = floor((bounds.width - lineWidth) / 2)
            let y = bottomY + CGFloat(lineCount - line - 1) * lineHeight

            for (index, segment) in lineSegments.enumerated() {
                let oldSegmentText = oldSegments[segment.id]?.text
                var frame = CGRect(x: x, y: y, width: widths[index], height: lineHeight)

                // Shift cost-sub down like a subscript
                if segment.id == "cost-sub" {
                    frame.origin.y -= lineHeight * 0.35
                }

                switch segment.kind {
                case .symbol:
                    nextLayer.addSublayer(textLayer(segment.text, frame: frame, role: role(for: segment), fontSize: segment.fontSize))
                case .separator:
                    nextLayer.addSublayer(textLayer(segment.text, frame: frame, role: .primary, fontSize: segment.fontSize))
                case .value:
                    renderValue(
                        oldText: oldSegmentText,
                        newText: segment.text,
                        frame: frame,
                        role: role(for: segment),
                        in: nextLayer,
                        animated: animated,
                        fontSize: segment.fontSize
                    )
                }

                x += widths[index]
            }
        }

        contentLayer?.removeFromSuperlayer()
        contentLayer = nextLayer
    }

    private enum SegmentKind {
        case symbol
        case separator
        case value
    }

    private struct Segment {
        let id: String
        let kind: SegmentKind
        let text: String
        let line: Int
        var fontSize: CGFloat? = nil
    }

    private func parseSegments(_ text: String) -> [Segment] {
        guard text.first == "↑" else {
            return [Segment(id: "whole", kind: .value, text: text, line: 0)]
        }

        if text.contains("\n") {
            let lines = text.components(separatedBy: "\n")
            let input = lines.first.map { String($0.dropFirst()) } ?? ""
            let output = lines.dropFirst().first.map { line in
                line.first == "↓" ? String(line.dropFirst()) : line
            } ?? ""
            return [
                Segment(id: "up-symbol", kind: .symbol, text: "↑", line: 0),
                Segment(id: "input", kind: .value, text: input, line: 0),
                Segment(id: "down-symbol", kind: .symbol, text: "↓", line: 1),
                Segment(id: "output", kind: .value, text: output, line: 1)
            ]
        }

        // Cost display: ↑$0.0234 — split into main + smaller sub
        if text.hasPrefix("↑$") {
            let value = String(text.dropFirst())
            let subFontSize = font.pointSize * 0.65
            if value.count >= 3 {
                let mainPart = String(value.dropLast(2))
                let subPart = String(value.suffix(2))
                return [
                    Segment(id: "up-symbol", kind: .symbol, text: "↑", line: 0),
                    Segment(id: "cost-value", kind: .value, text: mainPart, line: 0),
                    Segment(id: "cost-sub", kind: .value, text: subPart, line: 0, fontSize: subFontSize)
                ]
            } else {
                return [
                    Segment(id: "up-symbol", kind: .symbol, text: "↑", line: 0),
                    Segment(id: "cost-value", kind: .value, text: value, line: 0)
                ]
            }
        }

        let rest = text.dropFirst()
        guard let separatorRange = rest.range(of: " ↓") else {
            return [Segment(id: "whole", kind: .value, text: text, line: 0)]
        }

        return [
            Segment(id: "up-symbol", kind: .symbol, text: "↑", line: 0),
            Segment(id: "input", kind: .value, text: String(rest[..<separatorRange.lowerBound]), line: 0),
            Segment(id: "space", kind: .separator, text: " ", line: 0),
            Segment(id: "down-symbol", kind: .symbol, text: "↓", line: 0),
            Segment(id: "output", kind: .value, text: String(rest[separatorRange.upperBound...]), line: 0)
        ]
    }

    private func role(for segment: Segment) -> TextRole {
        switch segment.id {
        case "up-symbol": return .inputSymbol
        case "down-symbol": return .outputSymbol
        default: return .primary
        }
    }

    private func renderValue(oldText: String?, newText: String, frame: CGRect, role: TextRole = .primary, in parent: CALayer, animated: Bool, fontSize: CGFloat? = nil) {
        guard animated else {
            parent.addSublayer(textLayer(newText, frame: frame, role: role, fontSize: fontSize))
            return
        }

        guard let oldText else {
            renderRolling(oldText: "", newText: newText, frame: frame, role: role, in: parent, fontSize: fontSize)
            return
        }

        guard oldText != newText else {
            parent.addSublayer(textLayer(newText, frame: frame, role: role, fontSize: fontSize))
            return
        }

        if canRollPerCharacter(from: oldText, to: newText) {
            renderCharacterDiff(oldText: oldText, newText: newText, frame: frame, role: role, in: parent, fontSize: fontSize)
        } else {
            renderRolling(oldText: oldText, newText: newText, frame: frame, role: role, in: parent, fontSize: fontSize)
        }
    }

    private func canRollPerCharacter(from oldText: String, to newText: String) -> Bool {
        guard oldText.count == newText.count else { return false }
        let changes = zip(oldText, newText).filter { $0 != $1 }
        guard !changes.isEmpty else { return false }
        return changes.allSatisfy { $0.isNumber && $1.isNumber }
    }

    private func renderCharacterDiff(oldText: String, newText: String, frame: CGRect, role: TextRole, in parent: CALayer, fontSize: CGFloat? = nil) {
        let oldCharacters = Array(oldText)
        let newCharacters = Array(newText)
        var x = frame.minX

        for index in newCharacters.indices {
            let oldCharacter = String(oldCharacters[index])
            let newCharacter = String(newCharacters[index])
            let width = ceil(max(measure(oldCharacter, fontSize: fontSize), measure(newCharacter, fontSize: fontSize))) + 1
            let characterFrame = CGRect(x: x, y: frame.minY, width: width, height: frame.height)

            if oldCharacter == newCharacter {
                parent.addSublayer(textLayer(newCharacter, frame: characterFrame, role: role, fontSize: fontSize))
            } else {
                renderRolling(oldText: oldCharacter, newText: newCharacter, frame: characterFrame, role: role, in: parent, fontSize: fontSize)
            }

            x += measure(newCharacter, fontSize: fontSize)
        }
    }

    private func renderRolling(oldText: String, newText: String, frame: CGRect, role: TextRole = .primary, in parent: CALayer, fontSize: CGFloat? = nil) {
        let duration: TimeInterval = 0.28
        let clipLayer = CALayer()
        clipLayer.frame = frame
        clipLayer.masksToBounds = true
        parent.addSublayer(clipLayer)

        let oldLayer = textLayer(oldText, frame: clipLayer.bounds, role: role, fontSize: fontSize)
        let newLayer = textLayer(newText, frame: clipLayer.bounds.offsetBy(dx: 0, dy: -frame.height), role: role, fontSize: fontSize)
        clipLayer.addSublayer(oldLayer)
        clipLayer.addSublayer(newLayer)

        let startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak oldLayer, weak newLayer] timer in
            guard let self, let oldLayer, let newLayer else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(max(elapsed / duration, 0), 1)
            let eased = 0.5 - cos(progress * .pi) / 2
            let offset = frame.height * eased

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            oldLayer.frame = clipLayer.bounds.offsetBy(dx: 0, dy: offset)
            newLayer.frame = clipLayer.bounds.offsetBy(dx: 0, dy: -frame.height + offset)
            CATransaction.commit()

            if progress >= 1 {
                timer.invalidate()
                oldLayer.removeFromSuperlayer()
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                newLayer.frame = clipLayer.bounds
                CATransaction.commit()
                self.rollTimers.removeAll { $0 === timer }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rollTimers.append(timer)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        textAttributes(vertical: isVerticalLayout)
    }

    private func textAttributes(vertical: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: vertical ? verticalFont : horizontalFont,
            .foregroundColor: resolvedColor(for: .primary)
        ]
    }

    private var usesDarkMenuBarText: Bool {
        let darkAppearances: [NSAppearance.Name] = [
            .darkAqua,
            .vibrantDark,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastVibrantDark
        ]
        return effectiveAppearance.bestMatch(from: darkAppearances + [
            .aqua,
            .vibrantLight,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastVibrantLight
        ]).map(darkAppearances.contains) ?? false
    }

    private func resolvedColor(for role: TextRole) -> NSColor {
        switch role {
        case .primary:
            return usesDarkMenuBarText
                ? NSColor.white.withAlphaComponent(0.96)
                : NSColor.labelColor
        case .inputSymbol:
            return NSColor.systemGreen
        case .outputSymbol:
            return NSColor.systemCyan
        }
    }

    private func cgColor(for role: TextRole) -> CGColor {
        let color = resolvedColor(for: role)
        var colorRef = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            colorRef = (color.usingColorSpace(.deviceRGB) ?? color).cgColor
        }
        return colorRef
    }

    private func measure(_ text: String, fontSize: CGFloat? = nil) -> CGFloat {
        measure(text, vertical: isVerticalLayout, fontSize: fontSize)
    }

    private func measure(_ text: String, vertical: Bool, fontSize: CGFloat? = nil) -> CGFloat {
        var attrs = textAttributes(vertical: vertical)
        if let fontSize {
            attrs[.font] = vertical
                ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
                : NSFont.menuBarFont(ofSize: fontSize)
        }
        return (text as NSString).size(withAttributes: attrs).width
    }

    private func maxLineWidth(for text: String, vertical: Bool? = nil) -> CGFloat {
        let segments = parseSegments(text)
        let lineCount = max((segments.map(\.line).max() ?? 0) + 1, 1)
        return (0..<lineCount)
            .map { line in
                segments
                    .filter { $0.line == line }
                    .reduce(CGFloat(0)) { $0 + measure($1.text, vertical: vertical ?? isVerticalLayout) }
            }
            .max() ?? 0
    }

    private func textLayer(_ text: String, frame: CGRect, role: TextRole = .primary, fontSize: CGFloat? = nil) -> CATextLayer {
        let layer = CATextLayer()
        layer.name = role.rawValue
        layer.frame = frame
        layer.string = text
        layer.font = font
        layer.fontSize = fontSize ?? font.pointSize
        layer.foregroundColor = cgColor(for: role)
        layer.alignmentMode = .left
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.allowsFontSubpixelQuantization = true
        if usesDarkMenuBarText {
            layer.shadowColor = NSColor.black.withAlphaComponent(0.65).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 0.6
            layer.shadowOffset = CGSize(width: 0, height: -0.5)
        }
        return layer
    }

    private func refreshTextLayerColors(in layer: CALayer?) {
        guard let layer else { return }
        if let textLayer = layer as? CATextLayer,
           let name = textLayer.name,
           let role = TextRole(rawValue: name) {
            textLayer.foregroundColor = cgColor(for: role)
            textLayer.shadowOpacity = usesDarkMenuBarText ? 1 : 0
        }
        layer.sublayers?.forEach(refreshTextLayerColors)
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var statusTextView: MenuBarStatusRollView?
    private var appStateCancellable: AnyCancellable?
    private var statusItemRecoveryTimer: Timer?
    private var previousLiveState: Bool?
    private var previousStatusText: String?

    override init() {
        super.init()
        globalAppDelegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        tlog("applicationDidFinishLaunching")
        // Menu bar app: no Dock icon, but Settings can still own a key window.
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        setupStatusItem()
        setupStatusItemRecoveryHooks()

        // Auto-open Settings on first launch so users see the scanning progress.
        let hasLaunchedKey = "TokenLens.HasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: hasLaunchedKey) {
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.openSettings()
            }
        }
    }

    private func setupStatusItem() {
        guard let state = globalState else {
            tlog("ERROR: globalState not set for status item")
            return
        }

        appStateCancellable?.cancel()
        if let existing = statusItem {
            NSStatusBar.system.removeStatusItem(existing)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.image = nil
            button.imagePosition = .noImage
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.cell?.wraps = true
            button.cell?.lineBreakMode = .byWordWrapping
            statusTextView = nil
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        statusPopover = popover

        previousLiveState = state.isLiveConsumptionActive
        updateStatusItem(animated: false, force: true)

        appStateCancellable = state.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem(animated: true)
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            openSettings()
            return
        }

        toggleStatusPopover(sender)
    }

    private func toggleStatusPopover(_ sender: NSView) {
        guard let state = globalState, let popover = statusPopover else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.contentViewController = NSHostingController(rootView: MenuBarView(appState: state))
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        Task { @MainActor in
            state.refreshMenuData()
        }
    }

    private func setupStatusItemRecoveryHooks() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(forceRepairStatusItem),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(forceRepairStatusItem),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(forceRepairStatusItem),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(forceRepairStatusItem),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )

        statusItemRecoveryTimer?.invalidate()
        statusItemRecoveryTimer = Timer.scheduledTimer(
            timeInterval: 30,
            target: self,
            selector: #selector(forceRepairStatusItem),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func forceRepairStatusItem() {
        guard statusItem?.button != nil else {
            tlog("status item missing; recreating")
            setupStatusItem()
            return
        }

        updateStatusItem(animated: false, force: true)
    }

    private func updateStatusItem(animated: Bool, force: Bool = false) {
        guard let state = globalState,
              let button = statusItem?.button else { return }

        let isLive = state.isLiveConsumptionActive
        let oldLiveState = previousLiveState
        let oldText = previousStatusText
        let text = state.menuBarDisplayText.isEmpty ? "--" : state.menuBarDisplayText
        let didChangeText = oldText != text
        let didSwitchLiveState = oldLiveState != nil && oldLiveState != isLive

        guard force || didChangeText || didSwitchLiveState else { return }

        let previousLiveText = oldLiveState == true ? oldText : nil
        let enteringLive = !(oldLiveState == true) && isLive
        let liveRollView = isLive ? (statusTextView ?? MenuBarStatusRollView(frame: button.bounds)) : nil
        let width = isLive
            ? max(liveRollView?.fittingWidth(for: text, previousText: previousLiveText) ?? measureStatusTitle(text), 24)
            : max(measureStatusTitle(text), 24)

        previousLiveState = isLive
        previousStatusText = text

        button.title = ""
        if isLive, let rollView = liveRollView {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = nil
            button.imagePosition = .noImage
            statusItem?.length = width
            button.layoutSubtreeIfNeeded()

            if rollView.superview == nil {
                rollView.autoresizingMask = [.width, .height]
                button.addSubview(rollView)
                statusTextView = rollView
                // Fade-in transition from static to live
                if enteringLive {
                    rollView.alphaValue = 0
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.25
                        ctx.allowsImplicitAnimation = true
                        rollView.animator().alphaValue = 1
                    }
                }
            }
            rollView.frame = button.bounds
            rollView.update(text: text, previousText: previousLiveText, animated: animated && previousLiveText != nil)
        } else {
            // Fade-out transition from live to static
            if oldLiveState == true, let rollView = statusTextView {
                statusTextView = nil
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.2
                    rollView.animator().alphaValue = 0
                }, completionHandler: {
                    rollView.removeFromSuperview()
                })
            } else {
                statusTextView?.removeFromSuperview()
                statusTextView = nil
            }
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = attributedStatusTitle(text)
            statusItem?.length = width
            button.layoutSubtreeIfNeeded()
        }
        button.toolTip = "TokenLens — click for usage, right-click for settings"
    }

    private func attributedStatusTitle(_ text: String) -> NSAttributedString {
        let isLiveStack = text.contains("\n")
        let font = isLiveStack
            ? NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            : NSFont.menuBarFont(ofSize: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        if isLiveStack {
            paragraph.minimumLineHeight = 9.5
            paragraph.maximumLineHeight = 9.5
            paragraph.lineSpacing = 0
        }

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )

        if text.first == "↑" {
            let nsText = text as NSString
            attributed.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: NSRange(location: 0, length: 1))

            let downLocation = nsText.range(of: "↓").location
            if downLocation != NSNotFound {
                attributed.addAttribute(.foregroundColor, value: NSColor.systemCyan, range: NSRange(location: downLocation, length: 1))
            }

            // Cost display: last 2 digits in smaller font
            if nsText.hasPrefix("↑$") && nsText.length >= 5 {
                let smallFont = isLiveStack
                    ? NSFont.monospacedDigitSystemFont(ofSize: font.pointSize * 0.65, weight: .regular)
                    : NSFont.menuBarFont(ofSize: font.pointSize * 0.65)
                attributed.addAttribute(.font, value: smallFont, range: NSRange(location: nsText.length - 2, length: 2))
            }
        }

        return attributed
    }

    private func measureStatusTitle(_ text: String) -> CGFloat {
        let font = text.contains("\n")
            ? NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            : NSFont.menuBarFont(ofSize: 0)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let maxLineWidth = text
            .components(separatedBy: "\n")
            .map { ($0 as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        return ceil(maxLineWidth) + 12
    }


    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About TokenLens", action: nil, keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Dashboard", action: #selector(settingsAction), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit TokenLens", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func settingsAction() {
        openSettings()
    }

    public func openSettings() {
        guard let state = globalState else {
            tlog("ERROR: globalState not set")
            return
        }

        DispatchQueue.main.async {
            if let existing = self.settingsWindow {
                existing.contentView = self.makeSettingsHostingView(appState: state)
                NSApp.activate(ignoringOtherApps: true)
                existing.level = .floating
                existing.orderFrontRegardless()
                existing.makeMain()
                existing.makeKeyAndOrderFront(nil)
                return
            }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 760),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "TokenLens Dashboard"
            window.backgroundColor = .textBackgroundColor
            window.contentView = self.makeSettingsHostingView(appState: state)
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.hidesOnDeactivate = false
            window.isMovableByWindowBackground = true

            self.settingsWindow = window
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
            window.makeMain()
            window.makeKeyAndOrderFront(nil)
            tlog("Settings window opened ✅")
        }
    }

    private func makeSettingsHostingView(appState: AppState) -> NSHostingView<SettingsView> {
        let hostingView = NSHostingView(rootView: SettingsView(appState: appState))
        hostingView.frame.size = hostingView.fittingSize
        return hostingView
    }
}
