import CoreFoundation
import SwiftUI
import UIKit

struct HTMLAppNativeControl: Identifiable {
    enum Value {
        case toggle(Bool)
        case slider(Double, ClosedRange<Double>, Double?)
        case choice(String, [Option])
        case text(String)

        var bridgeValue: Any {
            switch self {
            case .toggle(let value): return value
            case .slider(let value, _, _): return value
            case .choice(let value, _), .text(let value): return value
            }
        }
    }

    struct Option: Identifiable {
        let id: String
        let title: String
    }

    let id: String
    let title: String
    let disabled: Bool
    var value: Value

    static func parse(_ input: Any?) -> [Self]? {
        guard let fields = input as? [[String: Any]], (1...16).contains(fields.count) else { return nil }
        let controls = fields.compactMap(Self.init)
        guard controls.count == fields.count,
              Set(controls.map(\.id)).count == controls.count else { return nil }
        return controls
    }

    private init?(_ object: [String: Any]) {
        guard let id = Self.string(object["id"], limit: 64),
              id.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]*$"#, options: .regularExpression) != nil,
              let title = Self.string(object["title"], limit: 100),
              let type = object["type"] as? String else { return nil }
        self.id = id
        self.title = title
        if let input = object["disabled"] {
            guard let flag = Self.boolean(input) else { return nil }
            disabled = flag
        } else { disabled = false }

        switch type {
        case "toggle":
            guard let flag = Self.boolean(object["value"]) else { return nil }
            value = .toggle(flag)
        case "slider":
            guard let min = Self.number(object["min"]), let max = Self.number(object["max"]),
                  min < max, let current = Self.number(object["value"]),
                  (min...max).contains(current) else { return nil }
            var step: Double?
            if let raw = object["step"] {
                guard let size = Self.number(raw), size > 0, size <= max - min,
                      (max - min) / size <= 100_000 else { return nil }
                step = size
            }
            value = .slider(current, min...max, step)
        case "choice":
            guard let raw = object["options"] as? [[String: Any]], (2...12).contains(raw.count),
                  let current = object["value"] as? String else { return nil }
            let options = raw.compactMap { item -> Option? in
                guard let id = Self.string(item["id"], limit: 64),
                      let title = Self.string(item["title"], limit: 100) else { return nil }
                return Option(id: id, title: title)
            }
            let ids = Set(options.map(\.id))
            guard ids.count == raw.count, ids.contains(current) else { return nil }
            value = .choice(current, options)
        case "text":
            guard let current = object["value"] as? String, current.count <= 240 else { return nil }
            value = .text(current)
        default: return nil
        }
    }

    private static func string(_ value: Any?, limit: Int) -> String? {
        guard let value = value as? String, value.count <= limit,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, abs(number.doubleValue) <= 1_000_000 else { return nil }
        return number.doubleValue
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

@MainActor
final class HTMLAppNativeControlsSession: NSObject, UIAdaptivePresentationControllerDelegate {
    let requestID: String
    private var completion: (([String: Any]) -> Void)?
    private weak var controller: UIViewController?

    init(requestID: String, completion: @escaping ([String: Any]) -> Void) {
        self.requestID = requestID
        self.completion = completion
    }

    func present(from presenter: UIViewController, title: String, fields: [HTMLAppNativeControl]) {
        let form = HTMLAppNativeControlsForm(title: title, fields: fields) { [weak self] values in
            self?.finish(values: values)
        }
        let hosting = UIHostingController(rootView: form)
        hosting.modalPresentationStyle = .pageSheet
        hosting.sheetPresentationController?.detents = [.large()]
        hosting.sheetPresentationController?.prefersGrabberVisible = true
        hosting.presentationController?.delegate = self
        controller = hosting
        presenter.present(hosting, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(dismiss: false)
    }

    func finish(values: [String: Any]? = nil, dismiss: Bool = true, animated: Bool = true) {
        guard let completion else { return }
        self.completion = nil
        let response: [String: Any]
        if let values { response = ["cancelled": false, "values": values] }
        else { response = ["cancelled": true] }
        if dismiss, let controller, controller.presentingViewController != nil {
            // Retain this session in the bridge until dismissal completes so a
            // follow-up request cannot present over a sheet that's closing.
            controller.dismiss(animated: animated) { completion(response) }
        } else {
            completion(response)
        }
    }
}

private struct HTMLAppNativeControlsForm: View {
    let title: String
    @State var fields: [HTMLAppNativeControl]
    let finish: ([String: Any]?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach($fields) { field in
                        control(field)
                            .disabled(field.wrappedValue.disabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .modifier(ControlSurface())
                    }
                }
                .frame(maxWidth: 600)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                    VStack(spacing: 8) { actions }
                }
                .frame(maxWidth: 600)
                .padding()
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if #available(iOS 26.0, *) {
            cancel.buttonStyle(.glass)
            apply.buttonStyle(.glassProminent)
        } else {
            cancel.buttonStyle(.bordered)
            apply.buttonStyle(.borderedProminent)
        }
    }

    private var cancel: some View {
        Button(role: .cancel) { finish(nil) } label: {
            Text("Cancel").frame(maxWidth: .infinity, minHeight: 34)
        }
    }

    private var apply: some View {
        Button {
            finish(Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.value.bridgeValue) }))
        } label: {
            Text("Apply").frame(maxWidth: .infinity, minHeight: 34)
        }
    }

    @ViewBuilder private func control(_ field: Binding<HTMLAppNativeControl>) -> some View {
        let title = field.wrappedValue.title
        switch field.wrappedValue.value {
        case .toggle(let current):
            Toggle(title, isOn: binding(field, fallback: current, wrap: HTMLAppNativeControl.Value.toggle) {
                if case .toggle(let value) = $0 { return value }
                return nil
            })
        case .slider(let current, let range, let step):
            let value = binding(field, fallback: current, wrap: { .slider($0, range, step) }) {
                if case .slider(let value, _, _) = $0 { return value }
                return nil
            }
            VStack(alignment: .leading) {
                Text(title)
                if let step {
                    Slider(value: value, in: range, step: step) { Text(title) }
                } else {
                    Slider(value: value, in: range) { Text(title) }
                }
            }
        case .choice(let current, let options):
            let value = binding(field, fallback: current, wrap: { .choice($0, options) }) {
                if case .choice(let value, _) = $0 { return value }
                return nil
            }
            Picker(title, selection: value) {
                ForEach(options) { option in Text(option.title).tag(option.id) }
            }
            .pickerStyle(.menu)
        case .text(let current):
            let value = binding(field, fallback: current, wrap: { .text(String($0.prefix(240))) }) {
                if case .text(let value) = $0 { return value }
                return nil
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                TextField(title, text: value)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func binding<Value>(
        _ field: Binding<HTMLAppNativeControl>, fallback: Value,
        wrap: @escaping (Value) -> HTMLAppNativeControl.Value,
        read: @escaping (HTMLAppNativeControl.Value) -> Value?
    ) -> Binding<Value> {
        Binding(get: { read(field.wrappedValue.value) ?? fallback },
                set: { field.wrappedValue.value = wrap($0) })
    }

    private struct ControlSurface: ViewModifier {
        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: 18)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
            }
        }
    }
}
