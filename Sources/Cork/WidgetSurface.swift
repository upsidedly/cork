import AppKit
import WebKit
import CorkCore
import SwiftUI

@MainActor final class WidgetSurface: NSView, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private let web: WKWebView
    private let root: URL
    private var loading: Task<Void, Never>?
    private var state: JSONValue
    private var loaded = false
    private var stopped = false
    private var lastFeedback = 0.0
    var onState: ((JSONValue) -> Void)?
    init(entry: URL, widgetID: String, state: JSONValue) {
        self.root = entry.deletingLastPathComponent(); self.state = state
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let policy = "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; media-src 'self' blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
        let quoted = (try? JSONEncoder().encode(policy)).map { String(decoding: $0, as: UTF8.self) } ?? "\"default-src 'none'\""
        let script = "(()=>{const h=document.head||document.documentElement.insertBefore(document.createElement('head'),document.documentElement.firstChild);const m=document.createElement('meta');m.httpEquiv='Content-Security-Policy';m.content=\(quoted);h.appendChild(m);})()"
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        web.navigationDelegate = self; web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        configuration.userContentController.add(self, name: "cork")
        addSubview(web)
        var components = URLComponents(url: entry, resolvingAgainstBaseURL: false); components?.fragment = widgetID
        let page = components?.url ?? entry
        loading = Task { [weak self] in
            guard let self else { return }
            do {
                // WebKit's content-rule regex grammar does not support disjunctions.
                let rules = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "CorkLocalWidgets-v2", encodedContentRuleList: "[{\"trigger\":{\"url-filter\":\"^https?:\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^wss?:\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\"^ftp:\"},\"action\":{\"type\":\"block\"}}]")
                try Task.checkCancellation()
                guard let rules else { throw CorkError("Widget network protection is unavailable.") }
                self.web.configuration.userContentController.add(rules)
                self.web.loadFileURL(page, allowingReadAccessTo: self.root)
            } catch { self.showError("Widget could not be loaded.") }
        }
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); web.frame = bounds }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func updateState(_ value: JSONValue) {
        guard value != state else { return }; state = value; restore()
    }
    private func restore() {
        guard loaded, !stopped, let data = try? state.data() else { return }
        web.evaluateJavaScript("window.corkWidget?.restore(\(String(decoding: data, as: UTF8.self)))", completionHandler: nil)
    }
    func setPaused(_ value: Bool) { web.evaluateJavaScript("window.corkWidget?.pause(\(value ? "true" : "false"))", completionHandler: nil) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; restore() }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let local = url?.resolvingSymlinksInPath()
        decisionHandler(local?.isFileURL == true && local?.pathComponents.starts(with: root.pathComponents) == true ? .allow : .cancel)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "feedback" {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastFeedback > 0.025 { lastFeedback = now; NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            return
        }
        guard type == "state", let value = body["state"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: value), data.count <= 64_000,
              let next = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
        state = next; onState?(next)
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) { completionHandler(nil) }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showError("Widget stopped. Reopen Cork to reload it.") }
    private func showError(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message); label.frame = bounds.insetBy(dx: 16, dy: 16); label.autoresizingMask = [.width, .height]; addSubview(label)
    }
    func stop() {
        stopped = true; loading?.cancel(); loading = nil; web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "cork")
        web.navigationDelegate = nil; web.uiDelegate = nil
    }
}

@MainActor private final class WidgetEditView: PrintView {
    override func draw(_ dirtyRect: NSRect) {
        guard editing else { return }
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 4), xRadius: 12, yRadius: 12)
        outline.lineWidth = selected ? 2 : 1; outline.stroke()
        NSColor.controlAccentColor.setFill(); NSBezierPath(ovalIn: CGRect(x: bounds.maxX - 14, y: bounds.maxY - 14, width: 10, height: 10)).fill()
    }
}
@MainActor final class WidgetPaperView: NSView {
    let surface: WidgetSurface?
    let editor: PrintView
    init(item: PrintItem, registry: WidgetRegistry, root: URL) {
        editor = WidgetEditView(item: item, image: nil)
        if let reference = item.widget, let entry = registry.entryURL(reference, root: root) {
            surface = WidgetSurface(entry: entry, widgetID: reference.widget, state: item.widgetState ?? .object([:]))
        } else { surface = nil }
        super.init(frame: .zero)
        if let surface { addSubview(surface) }
        else { let text = NSTextField(wrappingLabelWithString: "Register this widget provider again to restore it."); text.frame = CGRect(x: 12, y: 12, width: 220, height: 80); addSubview(text) }
        addSubview(editor)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); surface?.frame = bounds; editor.frame = bounds }
    func stop() { surface?.stop() }
}

struct WidgetInspectorPreview: NSViewRepresentable {
    let model: CorkController
    let item: PrintItem
    func makeNSView(context: Context) -> WidgetPaperView {
        let view = WidgetPaperView(item: item, registry: model.widgets, root: CorkPaths.dataDirectory)
        view.surface?.onState = { [weak model] state in model?.persistWidgetState(item.id, state: state) }
        return view
    }
    func updateNSView(_ view: WidgetPaperView, context: Context) { view.surface?.updateState(item.widgetState ?? .object([:])) }
    static func dismantleNSView(_ view: WidgetPaperView, coordinator: ()) { view.stop() }
}

struct WidgetSettings: View {
    @Bindable var model: CorkController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Widgets").font(.headline)
            Text("Add interactive desktop widgets from Swingset and other apps.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Register Widget Provider…") { model.chooseWidgetProvider() }.disabled(model.busy)
                if !model.widgets.providers.isEmpty {
                    Menu("Add Widget") {
                        ForEach(model.widgets.providers) { provider in
                            Menu(provider.manifest.name) {
                                ForEach(provider.manifest.widgets) { widget in
                                    Button(widget.name) { model.run { try await model.addWidget(WidgetReference(provider: provider.id, widget: widget.id)) } }
                                }
                            }
                        }
                    }.disabled(model.busy)
                }
            }
        }
    }
}
