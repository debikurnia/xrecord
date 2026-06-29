import Foundation
import CoreGraphics
import ProjectModel

public extension ZoomState {
    /// The affine transform that zooms a source image so the focal `center`
    /// fills the middle of the output at `scale`, producing a full-screen frame.
    ///
    /// Built for Core Image's coordinate space, whose origin is bottom-left,
    /// while screen/metadata coordinates are top-left. The y axis is therefore
    /// flipped using the screen height.
    ///
    /// The chained builder applies operations to a point in reverse order:
    /// first move the focal point to the origin, then scale, then move it to
    /// the output center.
    func ciTransform(screen: ScreenSize) -> CGAffineTransform {
        let cx = center.x
        let cyFlipped = screen.height - center.y
        return CGAffineTransform(translationX: screen.width / 2, y: screen.height / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -cx, y: -cyFlipped)
    }
}
