import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    if let url = URLContexts.first?.url {
      (UIApplication.shared.delegate as? AppDelegate)?.handleDeepLink(url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
