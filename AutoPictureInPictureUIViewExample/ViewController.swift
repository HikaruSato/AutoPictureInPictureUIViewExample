import AsyncAlgorithms
import AVKit
import UIKit

class ViewController: UIViewController {
    private var pipView: UIView!
    private let pipBufferDisplayLayer = AVSampleBufferDisplayLayer()
    private var pipLabel: UILabel!
    private var pipController: AVPictureInPictureController!
    private var timerTask: Task<(), any Error>?

    private lazy var formatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .positional
        f.zeroFormattingBehavior = [.pad]
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        let label = UILabel()
        label.text = "バックグラウンドに遷移するとピクチャーインピクチャーが開始します"
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -40),
        ])

        pipView = UIView()
        pipView.backgroundColor = .white
        pipView.translatesAutoresizingMaskIntoConstraints = false

        let videoLayerView = UIView()
        videoLayerView.translatesAutoresizingMaskIntoConstraints = false
        videoLayerView.layer.addSublayer(pipBufferDisplayLayer)
        // pipBufferDisplayLayerを持つViewはin picture in pictureのような文字列が自動で入ってきてしまうのでそれを見えないようにするため
        // UIViewでラップして透明にする必要がある
        videoLayerView.alpha = 0

        pipView.addSubview(videoLayerView)
        NSLayoutConstraint.activate([
            videoLayerView.topAnchor.constraint(equalTo: pipView.topAnchor),
            videoLayerView.leadingAnchor.constraint(equalTo: pipView.leadingAnchor),
            videoLayerView.trailingAnchor.constraint(equalTo: pipView.trailingAnchor),
            videoLayerView.bottomAnchor.constraint(equalTo: pipView.bottomAnchor),
        ])

        pipLabel = UILabel()
        pipLabel.numberOfLines = 0
        pipLabel.translatesAutoresizingMaskIntoConstraints = false
        pipLabel.textAlignment = .center
        pipView.addSubview(pipLabel)
        NSLayoutConstraint.activate([
            pipLabel.topAnchor.constraint(equalTo: pipView.topAnchor),
            pipLabel.leadingAnchor.constraint(equalTo: pipView.leadingAnchor, constant: 16),
            pipLabel.trailingAnchor.constraint(equalTo: pipView.trailingAnchor, constant: -16),
            pipLabel.bottomAnchor.constraint(equalTo: pipView.bottomAnchor),
        ])

        let window = (UIApplication.shared.connectedScenes.first as! UIWindowScene).windows.first!
        window.addSubview(pipView)
        window.sendSubviewToBack(pipView)
        NSLayoutConstraint.activate([
            pipView.topAnchor.constraint(equalTo: window.topAnchor, constant: 60),
            pipView.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 20),
            pipView.trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -20),
            pipView.heightAnchor.constraint(equalToConstant: 60)
        ])
        // AVSampleBufferDisplayLayerのサイズを設定して描画しておかないとPicture in Pictureが開始できないため設定
        pipView.layoutIfNeeded()
        renderPiPView()

        // これをやらないとPicture in Pictureが開始されない
        try! AVAudioSession.sharedInstance().setCategory(.playback)

        pipController = AVPictureInPictureController(
            contentSource: .init(
                sampleBufferDisplayLayer: pipBufferDisplayLayer,
                playbackDelegate: self
            )
        )
        pipController.delegate = self
        // バックグラウンド遷移時に自動的にPiP開始
        pipController.canStartPictureInPictureAutomaticallyFromInline = true
        // skipボタン消去
        pipController.requiresLinearPlayback = true

        timerTask = Task {
            // 計測開始
            let clock = ContinuousClock()
            let start = clock.now
            while true {
                try await Task.sleep(for: .seconds(1))

                let dur = start.duration(to: clock.now)
                let sec = Double(dur.components.seconds) + Double(dur.components.attoseconds) / 1e18 //(10^18) 秒化
                pipLabel.text = formatter.string(from: sec)
                renderPiPView()
            }
        }
    }

    deinit {
        timerTask?.cancel()
    }

    private func renderPiPView() {
        guard let buffer = pipView.makeCMSampleBuffer() else {
            return
        }

        if pipBufferDisplayLayer.status == .failed {
            pipBufferDisplayLayer.flush()
        }

        pipBufferDisplayLayer.bounds = pipView.bounds

        pipBufferDisplayLayer.enqueue(buffer)
    }
}

extension ViewController: AVPictureInPictureControllerDelegate {
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: any Error) {
        print("\(error.localizedDescription)")
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("did stop picture in picture")
    }
}

extension ViewController: AVPictureInPictureSampleBufferPlaybackDelegate {
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}

    public func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        .init(
            start: .indefinite,
            // progressを非表示にできないため長い時間として30日分にセット
            duration: .init(seconds: 60 * 60 * 24 * 30, preferredTimescale: .init(1))
        )
    }

    public func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        // 再生中を表し⏸️ボタンを表示
        // falseじゃないとcanStartPictureInPictureAutomaticallyFromInline = trueでバックグラウンド遷移時にPicture in Pictureが開始しない
        false
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime) async {}
}

private extension UIView {
    func makeCMSampleBuffer() -> CMSampleBuffer? {
        let scale: CGFloat = UIScreen.main.scale
        let size: CGSize = .init(width: bounds.width * scale, height: bounds.height * scale)

        guard let pixelBuffer = makeCVPicelBuffer(scale: scale, size: size) else {
            return nil
        }

        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])

        guard let context = makeCGContext(scale: scale, size: size, pixelBuffer: pixelBuffer) else {
            return nil
        }
        layer.render(in: context)

        guard let formatDescription = makeCMFormatDescription(pixelBuffer: pixelBuffer) else {
            return nil
        }

        do {
            return try CMSampleBuffer(
                imageBuffer: pixelBuffer,
                formatDescription: formatDescription,
                sampleTiming: getCMSampleTimingInfo()
            )
        } catch {
            assertionFailure("Failed to create CMSampleBuffer: \(error)")
            return nil
        }
    }

    func makeCVPicelBuffer(scale: CGFloat, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let createPixelBufferResult: CVReturn = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
            ] as CFDictionary,
            &pixelBuffer
        )

        guard createPixelBufferResult == kCVReturnSuccess else {
            assertionFailure("Failed to create CVPixelBuffer: \(createPixelBufferResult)")
            return nil
        }

        return pixelBuffer
    }

    func makeCGContext(scale: CGFloat, size: CGSize, pixelBuffer: CVPixelBuffer) -> CGContext? {
        guard let context: CGContext = .init(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: scale, y: -scale)
        return context
    }

    func makeCMFormatDescription(pixelBuffer: CVPixelBuffer) -> CMFormatDescription? {
        var formatDescription: CMFormatDescription?
        let createImageBufferResult: CVReturn = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )

        guard createImageBufferResult == kCVReturnSuccess else {
            assertionFailure("Failed to create CMFormatDescription: \(createImageBufferResult)")
            return nil
        }

        return formatDescription
    }

    func getCMSampleTimingInfo() -> CMSampleTimingInfo {
        let currentTime: CMTime = .init(
            seconds: CACurrentMediaTime(),
            preferredTimescale: 60
        )

        let timingInfo: CMSampleTimingInfo = .init(
            duration: .init(seconds: 1, preferredTimescale: 60),
            presentationTimeStamp: currentTime,
            decodeTimeStamp: currentTime
        )

        return timingInfo
    }
}

