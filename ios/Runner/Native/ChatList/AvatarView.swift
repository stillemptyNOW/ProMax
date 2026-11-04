import SwiftUI
import UIKit

@available(iOS 15.0, *)
final class AvatarLoader: ObservableObject {
  private static let cache = NSCache<NSString, UIImage>()

  @Published private(set) var image: UIImage?
  private var task: URLSessionDataTask?
  private var loadedUrl: String?

  func load(_ urlString: String) {
    guard urlString != loadedUrl else { return }
    loadedUrl = urlString
    task?.cancel()
    image = nil
    guard !urlString.isEmpty, let url = URL(string: urlString) else { return }
    if let cached = Self.cache.object(forKey: urlString as NSString) {
      image = cached
      return
    }
    task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data = data, let decoded = UIImage(data: data) else { return }
      Self.cache.setObject(decoded, forKey: urlString as NSString)
      DispatchQueue.main.async {
        guard let self = self, self.loadedUrl == urlString else { return }
        self.image = decoded
      }
    }
    task?.resume()
  }

  deinit {
    task?.cancel()
  }
}

@available(iOS 15.0, *)
struct AvatarView: View {
  let url: String
  let title: String
  let size: CGFloat

  @StateObject private var loader = AvatarLoader()

  private var initial: String {
    String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
  }

  private var tint: Color {
    let sum = title.unicodeScalars.reduce(7) { ($0 &* 31) &+ Int($1.value) }
    let hue = Double(abs(sum % 360))
    return Color(hue: hue / 360.0, saturation: 0.45, brightness: 0.75)
  }

  var body: some View {
    ZStack {
      if let image = loader.image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        tint
        Text(initial)
          .font(.system(size: size * 0.4, weight: .semibold))
          .foregroundColor(.white)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .onAppear { loader.load(url) }
    .onChange(of: url) { loader.load($0) }
  }
}
