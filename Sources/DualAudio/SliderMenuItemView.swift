import AppKit

final class SliderMenuItemView: NSView {
    let slider: NSSlider

    init(title: String, value: Float, tag: Int, target: AnyObject?, action: Selector) {
        slider = NSSlider(value: Double(value), minValue: 0, maxValue: 1, target: target, action: action)
        super.init(frame: NSRect(x: 0, y: 0, width: 230, height: 38))

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 16, y: 20, width: 200, height: 14)
        addSubview(label)

        slider.tag = tag
        slider.isContinuous = true
        slider.frame = NSRect(x: 16, y: 2, width: 200, height: 18)
        addSubview(slider)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
