import SwiftUI
import WebKit

struct TermsOfServiceView: View {
    var body: some View {
        WebView(fileName: "terms_of_service")
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct WebView: UIViewRepresentable {
    let fileName: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        if let url = Bundle.main.url(forResource: fileName, withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
