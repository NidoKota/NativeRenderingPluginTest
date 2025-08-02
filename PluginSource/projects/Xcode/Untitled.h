
import SwiftUI
import Metal
import MetalKit
import MetalFX

// SwiftUIのViewを定義し、UIのレイアウトを行います。
struct ContentView: View {
    // Viewの状態とロジックを管理するViewModelのインスタンス。
    // @Stateでラップすることで、プロパティの変更がUIに自動的に反映されます。
    @State var vm = ContentViewModel()

    // Viewの本体。ここにUI要素を配置します。
    var body: some View {
        VStack {
            // 元の画像を表示します。
            Image(uiImage: vm.original)
                .resizable()
                .scaledToFit()
            
            // アップスケール後の画像(vm.result)が存在する場合にのみ表示します。
            if let result = vm.result {
                Image(uiImage: result)
                    .resizable()
                    .scaledToFit()
            }
        }
        // Viewが画面に表示されたときに一度だけ実行される処理です。
        .onAppear {
            // ViewModelのupscale関数を呼び出して、画像の高解像度化処理を開始します。
            vm.upscale()
        }
    }
}

// UIの状態と、Metalを使った画像処理のロジックを管理するクラスです。
// @Observableマクロにより、プロパティの変更をSwiftUIが検知できるようになります。
@Observable
class ContentViewModel {
    // アップスケール前の元の画像。
    let original = UIImage(resource: .image)
    // アップスケール後の画像を保持するプロパティ。処理が終わるとここに格納されます。
    var result: UIImage?

    // GPUとのやり取りを行うための主要なオブジェクト(デバイス)。
    private let device: any MTLDevice
    // GPUに送るコマンドを生成し、キューに入れるためのオブジェクト。
    private let commandQueue: any MTLCommandQueue
    // MetalFXを使ったアップスケール処理を行うためのカスタムクラスのインスタンス。
    private let upscaler: Upscaler

    // ContentViewModelが初期化されるときに呼ばれます。
    init() {
        // システムのデフォルトGPUデバイスを取得します。
        device = MTLCreateSystemDefaultDevice()!
        // コマンドキューをデバイスから作成します。
        commandQueue = device.makeCommandQueue()!
        // Upscalerクラスを初期化します。
        upscaler = Upscaler(device: device)
    }

    // 画像をアップスケールするメインの処理です。
    func upscale() {
        // 1. UIImageをMetalが扱えるMTLTextureに変換します。
        let inputTexture = original.toTexture(device: device)
        
        // 2. GPUに送る命令(コマンド)を記録するためのバッファを作成します。
        let commandBuffer: any MTLCommandBuffer = commandQueue.makeCommandBuffer()!
        
        // 3. Upscalerを使って、コマンドバッファにアップスケール処理をエンコード(記録)します。
        let outputTexture = upscaler.upscale(commandBuffer: commandBuffer, inputTexture: inputTexture, scale: 2)
        
        // 4. コマンドバッファに記録された命令をGPUに送って実行させます。
        commandBuffer.commit()
        
        // 5. GPUの処理が完了するまで待ちます。
        commandBuffer.waitUntilCompleted()
        
        // 6. 処理結果のMTLTextureを画面に表示できるUIImageに変換します。
        result = outputTexture.toUIImage()
    }
}

// MetalFXのSpatialScalerを使って、画像のアップスケール処理を専門に行うクラスです。
class Upscaler {
    private let device: any MTLDevice
    // MetalFXの空間的スケーリング（アップスケーリング）を行うためのオブジェクト。
    private var mfxSpatialScaler: (any MTLFXSpatialScaler)!
    // アップスケール後の画像データを格納するテクスチャ。
    private var outputTexture: (any MTLTexture)!

    init(device: any MTLDevice) {
        self.device = device
    }

    /// コマンドバッファにアップスケール処理をエンコードし、出力テクスチャを返します。
    /// - Parameters:
    ///   - commandBuffer: 処理をエンコードする先のコマンドバッファ。
    ///   - inputTexture: アップスケールしたい入力テクスチャ。
    ///   - scale: スケール倍率。
    /// - Returns: アップスケール後のデータが書き込まれる出力テクスチャ。
    func upscale(commandBuffer: any MTLCommandBuffer, inputTexture: any MTLTexture, scale: Float) -> any MTLTexture {
        // 初回呼び出し時、または設定が異なる場合にのみScalerと出力テクスチャを生成します。
        // TODO: サイズやpixelFormatが異なる場合も作り直す
        if mfxSpatialScaler == nil {
            // 1. 出力用の空のテクスチャを生成します。
            outputTexture = createEmptyTexture(
                width: Int(Float(inputTexture.width) * scale),
                height: Int(Float(inputTexture.height) * scale),
                pixelFormat: inputTexture.pixelFormat
            )
            
            // 2. SpatialScalerの設定を記述するディスクリプタを生成します。
            let desc = MTLFXSpatialScalerDescriptor()
            desc.inputWidth = inputTexture.width
            desc.inputHeight = inputTexture.height
            desc.outputWidth = outputTexture.width
            desc.outputHeight = outputTexture.height
            desc.colorTextureFormat = inputTexture.pixelFormat
            desc.outputTextureFormat = outputTexture.pixelFormat
            // 知覚的な色空間で処理を行うモード。人間の視覚特性に合わせた高品質なスケーリングになります。
            desc.colorProcessingMode = .perceptual
            
            // 3. ディスクリプタを元に、SpatialScalerのインスタンスを生成します。
            mfxSpatialScaler = desc.makeSpatialScaler(device: device)!
        }

        // 4. Scalerに入力と出力のテクスチャを設定します。
        mfxSpatialScaler.colorTexture = inputTexture
        mfxSpatialScaler.outputTexture = outputTexture
        
        // 5. コマンドバッファにアップスケール処理をエンコード(記録)します。
        mfxSpatialScaler.encode(commandBuffer: commandBuffer)
        
        // 6. 出力テクスチャを返します。
        return outputTexture
    }

    /// 指定された情報で空のMTLTextureを生成します。
    private func createEmptyTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        // .renderTargetは、GPUがこのテクスチャに描画(書き込み)するために必要です。
        // .shaderReadは、このテクスチャを後で読み取ってUIImageに変換するために必要です。
        descriptor.usage = [.renderTarget, .shaderRead]
        // GPUのみがアクセスできるプライベートなメモリに配置します。
        descriptor.storageMode = .private
        descriptor.textureType = .type2D
        descriptor.mipmapLevelCount = 1
        return device.makeTexture(descriptor: descriptor)!
    }
}

// UIImageを便利に扱うための拡張です。
extension UIImage {
    /// UIImageをMTLTextureに変換します。
    func toTexture(device: any MTLDevice) -> any MTLTexture {
        let loader = MTKTextureLoader(device: device)
        // MTKTextureLoaderを使ってCGImageからMTLTextureを生成します。
        return try! loader.newTexture(cgImage: cgImage!, options: [:])
    }
}

// MTLTextureを便利に扱うための拡張です。
extension MTLTexture {
    /// MTLTextureをUIImageに変換します。
    func toUIImage() -> UIImage {
        // 1. MTLTextureからCIImage(Core Imageの画像オブジェクト)を生成します。
        let ci = CIImage(mtlTexture: self, options: [:])!
        
        // 2. 座標系の違いを補正するためのアフィン変換行列を作成します。
        // Metalのテクスチャ座標系は左上が(0,0)でY軸が下向きですが、
        // UIKitの座標系は左下(または左上)が原点でY軸が上向きのため、画像を垂直方向に反転させる必要があります。
        let mat = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: ci.extent.height)
        
        // 3. Core Imageのコンテキスト(描画環境)を生成します。
        let context = CIContext()
        
        // 4. CIImageにアフィン変換を適用し、その結果からCGImage(Core Graphicsの画像オブジェクト)を生成します。
        let cg = context.createCGImage(ci.transformed(by: mat), from: ci.extent)!
        
        // 5. 最終的にCGImageからUIImageを生成して返します。
        return UIImage(cgImage: cg)
    }
}
