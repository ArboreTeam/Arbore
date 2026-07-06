import Foundation
import UserNotifications
import UniformTypeIdentifiers

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var downloadTask: URLSessionDownloadTask?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        guard let imageURL = imageURL(from: request.content.userInfo) else {
            contentHandler(bestAttemptContent)
            return
        }

        downloadAttachment(from: imageURL) { [weak self] attachment in
            guard let self else { return }
            if let attachment {
                bestAttemptContent.attachments = [attachment]
            }
            contentHandler(bestAttemptContent)
            self.contentHandler = nil
        }
    }

    override func serviceExtensionTimeWillExpire() {
        downloadTask?.cancel()

        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }

        contentHandler = nil
    }

    private func imageURL(from userInfo: [AnyHashable: Any]) -> URL? {
        let keys = ["image_url", "image-url", "imageURL", "media-url", "media_url"]

        for key in keys {
            guard let rawValue = userInfo[key] as? String,
                  let url = URL(string: rawValue),
                  url.scheme?.lowercased() == "https" else { continue }
            return url
        }

        return nil
    }

    private func downloadAttachment(from url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12

        let session = URLSession(configuration: configuration)
        downloadTask = session.downloadTask(with: url) { temporaryURL, response, error in
            defer {
                session.finishTasksAndInvalidate()
            }

            guard error == nil,
                  let temporaryURL,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                completion(nil)
                return
            }

            do {
                let attachmentURL = try self.copyAttachmentToTemporaryDirectory(
                    downloadedURL: temporaryURL,
                    response: httpResponse,
                    sourceURL: url
                )
                let attachment = try UNNotificationAttachment(
                    identifier: "arbore-rich-image",
                    url: attachmentURL,
                    options: nil
                )
                completion(attachment)
            } catch {
                completion(nil)
            }
        }

        downloadTask?.resume()
    }

    private func copyAttachmentToTemporaryDirectory(
        downloadedURL: URL,
        response: HTTPURLResponse,
        sourceURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileExtension = response.suggestedFilename
            .flatMap { URL(fileURLWithPath: $0).pathExtension.nilIfEmpty }
            ?? sourceURL.pathExtension.nilIfEmpty
            ?? fileExtensionFromMimeType(response.mimeType)
            ?? "jpg"

        let destination = directory.appendingPathComponent("image.\(fileExtension)")
        try fileManager.moveItem(at: downloadedURL, to: destination)
        return destination
    }

    private func fileExtensionFromMimeType(_ mimeType: String?) -> String? {
        guard let mimeType,
              let type = UTType(mimeType: mimeType),
              let preferred = type.preferredFilenameExtension else { return nil }
        return preferred
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
