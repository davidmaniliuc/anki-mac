import AppKit

/// Desktop's url_schemes.py: a link opens in its app when its scheme is
/// http, https or one the profile allows (Settings > Review > URL Schemes);
/// any other asks first, since a card from a shared deck could open anything.
enum CardLinks {
    static func open(_ url: URL, from window: NSWindow?) {
        let scheme = url.scheme?.lowercased() ?? ""
        let allowed = SettingsScope.open?.strings("allowedUrlSchemes") ?? []
        if ["http", "https"].contains(scheme) || allowed.contains(scheme) {
            NSWorkspace.shared.open(url)
            return
        }
        // Upstream's message is Markdown: the blocked link, then what to do.
        let text = Tr.preferencesUrlSchemeWarning(link: url.absoluteString, scheme: scheme)
            .replacingOccurrences(of: "`", with: "")
        let paragraphs = text.components(separatedBy: "\n\n")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = paragraphs.first ?? text
        alert.informativeText = paragraphs.dropFirst().joined(separator: "\n\n")
        // Cancel is the default, as desktop's.
        alert.addButton(withTitle: Tr.actionsCancel)
        alert.addButton(withTitle: Tr.preferencesUrlSchemeAllowOnce)
        alert.addButton(withTitle: Tr.preferencesUrlSchemeAlwaysAllow)
        let respond = { (response: NSApplication.ModalResponse) in
            switch response {
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(url)
            case .alertThirdButtonReturn:
                if let scope = SettingsScope.open {
                    scope.set(allowed + [scheme], for: "allowedUrlSchemes")
                }
                NSWorkspace.shared.open(url)
            default:
                break
            }
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }
}
