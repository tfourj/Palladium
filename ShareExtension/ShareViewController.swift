import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    
    // In viewDidLoad we simply do setup.
    override func viewDidLoad() {
        super.viewDidLoad()
        print("viewDidLoad")
    }
    
    // Process the shared content in viewDidAppear.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedURL()
    }
    
    private func handleSharedURL() {
        print("checking url")
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            dismissExtension()
            return
        }
        
        // Iterate over all attachments to try different type identifiers.
        for itemProvider in attachments {
            // First try the URL type.
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (loadedItem, error) in
                    if let url = loadedItem as? URL {
                        print("Shared URL: \(url)")
                        self?.sendURLToMainApp(url: url)
                    } else {
                        self?.dismissExtension()
                    }
                }
                return
            }
            // If no URL, check for plain text.
            else if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (loadedItem, error) in
                    if let text = loadedItem as? String, let url = URL(string: text) {
                        print("Converted text to URL: \(url)")
                        self?.sendURLToMainApp(url: url)
                    } else {
                        self?.dismissExtension()
                    }
                }
                return
            }
        }
        
        // If none of the expected types are found, dismiss the extension.
        dismissExtension()
    }
    
    private func sendURLToMainApp(url: URL) {
        // Encode the URL so that it can be safely passed as a query parameter
        let encodedURL = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Construct the URL that should open your main app, embedding the shared URL as a parameter
        guard let appURL = URL(string: "palladium://download?url=\(encodedURL)") else {
            dismissExtension()
            return
        }
        
        // Grab the window scene from our view so we have a reference
        guard let windowScene = self.view.window?.windowScene else {
            dismissExtension()
            return
        }
        
        // Dismiss the share extension and then, after a short delay, open the main app.
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: { _ in
            // Delay to ensure the extension UI is fully dismissed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                windowScene.open(appURL, options: UIScene.OpenExternalURLOptions(), completionHandler: { success in
                    if success {
                        print("✅ Main app opened with URL: \(appURL.absoluteString)")
                    } else {
                        print("❌ Failed to open main app")
                    }
                })
            }
        })
    }
    
    private func dismissExtension() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}