import AppKit
import SwiftUI

enum SettingsAppearance {
    static let accentNSColor = NSColor(srgbRed: 0.96, green: 0.28, blue: 0.62, alpha: 1)
    static let accent = Color(nsColor: accentNSColor)
    static let cardRadius: CGFloat = 20
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SettingsAppearance.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: SettingsAppearance.cardRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

struct SettingsSmallButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(prominent ? SettingsAppearance.accent.opacity(configuration.isPressed ? 0.8 : 1)
                        : Color.primary.opacity(hovered ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
    }
}

struct SettingsSegmentButtonStyle: ButtonStyle {
    let selected: Bool
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(selected ? SettingsAppearance.accent.opacity(configuration.isPressed ? 0.8 : 1)
                        : Color.primary.opacity(hovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

final class SettingsCardSurface: NSView {
    private let effect = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        effect.material = .popover
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = SettingsAppearance.cardRadius
        effect.layer?.borderWidth = 0.5
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)
        layer?.cornerRadius = SettingsAppearance.cardRadius
        layer?.borderWidth = 0.5
        layer?.shadowRadius = 12
        layer?.shadowOpacity = 0.06
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("SettingsCardSurface does not use a storyboard") }
    override func layout() {
        super.layout()
        effect.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: SettingsAppearance.cardRadius,
                                   cornerHeight: SettingsAppearance.cardRadius, transform: nil)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshAppearance()
    }
    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
            effect.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
            layer?.shadowColor = NSColor.black.cgColor
        }
    }
}

final class SettingsSearchSurface: NSView {
    let field = NSTextField()
    private let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
    private let clear = NSButton()
    private var editing = false
    var onClear: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        icon.contentTintColor = .secondaryLabelColor
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        (field.cell as! NSTextFieldCell).usesSingleLineMode = true
        (field.cell as! NSTextFieldCell).isScrollable = true
        clear.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "검색 지우기")!
        clear.isBordered = false
        clear.contentTintColor = .secondaryLabelColor
        clear.target = self
        clear.action = #selector(clearSearch)
        clear.setAccessibilityLabel("검색 지우기")
        addSubview(icon)
        addSubview(field)
        addSubview(clear)
        updateClearButton()
        refreshAppearance()
    }
    required init?(coder: NSCoder) { fatalError("SettingsSearchSurface does not use a storyboard") }
    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 12, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let textHeight = ceil(field.cell!.cellSize.height)
        field.frame = NSRect(x: 34, y: (bounds.height - textHeight) / 2,
                             width: bounds.width - 66, height: textHeight)
        clear.frame = NSRect(x: bounds.width - 28, y: (bounds.height - 18) / 2, width: 18, height: 18)
    }
    func updateClearButton() { clear.isHidden = field.stringValue.isEmpty }
    @objc private func clearSearch() {
        field.stringValue = ""
        updateClearButton()
        window?.makeFirstResponder(field)
        onClear?()
    }
    func setEditing(_ editing: Bool) { self.editing = editing; refreshAppearance() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshAppearance()
    }
    private func refreshAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            layer?.borderColor = (editing ? SettingsAppearance.accentNSColor : NSColor.separatorColor).cgColor
            layer?.borderWidth = editing ? 2 : 1
        }
    }
}

final class SettingsActionButton: NSButton {
    let destructive: Bool
    private var hovered = false
    private var hoverArea: NSTrackingArea?

    init(title: String, destructive: Bool = false) {
        self.destructive = destructive
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        font = .systemFont(ofSize: 13, weight: .medium)
    }
    required init?(coder: NSCoder) { fatalError("SettingsActionButton does not use a storyboard") }
    override var intrinsicContentSize: NSSize {
        NSSize(width: (title as NSString).size(withAttributes: [.font: font!]).width + 24, height: 30)
    }
    override var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let active = hovered || cell!.isHighlighted
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        let base = destructive ? SettingsAppearance.accentNSColor : NSColor.labelColor
        base.withAlphaComponent(isEnabled && active ? 0.13 : 0.055).setFill()
        shape.fill()
        base.withAlphaComponent(0.09).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let color = destructive ? SettingsAppearance.accentNSColor : NSColor.labelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font!, .foregroundColor: color.withAlphaComponent(isEnabled ? 1 : 0.35),
            .paragraphStyle: paragraph
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(in: NSRect(x: 8, y: (bounds.height - size.height) / 2,
                                           width: bounds.width - 16, height: size.height), withAttributes: attributes)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
}
