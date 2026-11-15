import AVFoundation
import DSLink
import SwiftUI

struct PairView: View {
    @ObservedObject var model: AppModel

    @State private var busy = false
    @State private var problem: String?
    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Haptics.light()
                    model.go(.welcome)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("返回")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 16)

            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color.black)
                QRScanner { text in scanned(text) }
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .opacity(busy ? 0.35 : 1)
                Corners()
                    .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .padding(34)
                    .scaleEffect(busy ? 0.9 : 1)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: busy)
                if busy {
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
            .frame(width: 290, height: 290)
            .shadow(color: Color(hex: 0x141432).opacity(0.22), radius: 28, y: 22)
            .rotationEffect(.degrees(shown ? -2 : -8))
            .scaleEffect(shown ? 1 : 0.86)
            .opacity(shown ? 1 : 0)

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Text(busy ? "正在握手" : "扫一下电脑上的码")
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color(hex: 0x0B0B0F))
                    .contentTransition(.opacity)
                Text(problem ?? "在电脑的 DS Bot 里打开 设置 → 手机。")
                    .font(.system(size: 17))
                    .foregroundStyle(problem == nil ? Color(hex: 0x2A2A33) : Color(hex: 0xA3212C))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .frame(minHeight: 46, alignment: .top)
                Button {
                    Haptics.light()
                    if let text = UIPasteboard.general.string { scanned(text) } else { fail("剪贴板里没有配对码。") }
                } label: {
                    Text("粘贴配对码")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(busy)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .onAppear {
            Haptics.prepare()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { shown = true }
        }
    }

    private func scanned(_ text: String) {
        guard !busy else { return }
        let offer: PairingOffer
        do {
            offer = try PairingOffer.parse(text)
        } catch {
            fail("这不是 DS Bot 的配对码。")
            return
        }
        Haptics.lock()
        withAnimation(.smooth) {
            busy = true
            problem = nil
        }
        Task {
            do {
                try await model.pair(offer)
                Haptics.thud()
            } catch let error as LinkError {
                fail(Self.explain(error))
            } catch {
                fail("没连上，再试一次。")
            }
        }
    }

    private func fail(_ message: String) {
        Haptics.tick(1)
        withAnimation(.smooth) {
            busy = false
            problem = message
        }
    }

    private static func explain(_ error: LinkError) -> String {
        switch error.code {
        case "NOT_PAIRED", "PAIRING_REJECTED": return "这个码已经用过或过期了，在电脑上换一个新的。"
        case "SERVER_UNREACHABLE": return "连不上中继服务器，检查一下手机网络。"
        case "PEER_IDENTITY_MISMATCH": return "电脑的身份对不上，在电脑上重新出码。"
        default: return "没连上（\(error.code)），再试一次。"
        }
    }
}

/// The four corner marks of the viewfinder.
private struct Corners: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let arm: CGFloat = 30
        let r: CGFloat = 12
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (rect.minX, rect.minY, 1, 1), (rect.maxX, rect.minY, -1, 1),
            (rect.maxX, rect.maxY, -1, -1), (rect.minX, rect.maxY, 1, -1),
        ]
        for (x, y, dx, dy) in corners {
            p.move(to: CGPoint(x: x, y: y + dy * arm))
            p.addLine(to: CGPoint(x: x, y: y + dy * r))
            p.addQuadCurve(to: CGPoint(x: x + dx * r, y: y), control: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + dx * arm, y: y))
        }
        return p
    }
}

struct QRScanner: UIViewRepresentable {
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.backgroundColor = .black
        context.coordinator.start(on: view)
        return view
    }

    func updateUIView(_ view: Preview, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIView(_ view: Preview, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: (String) -> Void
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "qr.session")
        private var lastText = ""
        private var lastAt = Date.distantPast

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func start(on view: Preview) {
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted, let self else { return }
                self.queue.async { self.configure() }
            }
        }

        private func configure() {
            guard session.inputs.isEmpty,
                  let camera = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else { return }
            session.beginConfiguration()
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
            }
            session.commitConfiguration()
            session.startRunning()
        }

        func stop() {
            queue.async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let text = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            // The same code stays in view for many frames: report it once every few seconds.
            let now = Date()
            if text == lastText, now.timeIntervalSince(lastAt) < 3 { return }
            lastText = text
            lastAt = now
            onCode(text)
        }
    }
}
