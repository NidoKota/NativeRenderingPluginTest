#import "MetalUpscaler.h"

@interface Upscaler ()
// MetalFXの空間的スケーリング（アップスケーリング）を行うためのオブジェクト。
@property (nonatomic, strong) id<MTLFXSpatialScaler> mfxSpatialScaler;
// アップスケール後の画像データを格納するテクスチャ。
@property (nonatomic, strong) id<MTLTexture> outputTexture;
@end

@implementation Upscaler

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
    }
    return self;
}

- (id<MTLTexture>)upscaleWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                              inputTexture:(id<MTLTexture>)inputTexture
                                     scale:(float)scale {
    // 初回呼び出し時、または設定が異なる場合にのみScalerと出力テクスチャを生成します。
    // TODO: サイズやpixelFormatが異なる場合も作り直す
    if (self.mfxSpatialScaler == nil) {
        // 1. 出力用の空のテクスチャを生成します。
        self.outputTexture = [self createEmptyTextureWithWidth:(NSUInteger)(inputTexture.width * scale)
                                                        height:(NSUInteger)(inputTexture.height * scale)
                                                   pixelFormat:inputTexture.pixelFormat];
        
        // 2. SpatialScalerの設定を記述するディスクリプタを生成します。
        MTLFXSpatialScalerDescriptor *desc = [[MTLFXSpatialScalerDescriptor alloc] init];
        desc.inputWidth = inputTexture.width;
        desc.inputHeight = inputTexture.height;
        desc.outputWidth = self.outputTexture.width;
        desc.outputHeight = self.outputTexture.height;
        desc.colorTextureFormat = inputTexture.pixelFormat;
        desc.outputTextureFormat = self.outputTexture.pixelFormat;
        // 知覚的な色空間で処理を行うモード。人間の視覚特性に合わせた高品質なスケーリングになります。
        desc.colorProcessingMode = MTLFXColorProcessingModePerceptual;
        
        // 3. ディスクリプタを元に、SpatialScalerのインスタンスを生成します。
        self.mfxSpatialScaler = [desc newSpatialScalerWithDevice:self.device];
        if (self.mfxSpatialScaler == nil) {
            NSLog(@"Failed to create MTLFXSpatialScaler");
            return nil;
        }
    }

    // 4. Scalerに入力と出力のテクスチャを設定します。
    self.mfxSpatialScaler.colorTexture = inputTexture;
    self.mfxSpatialScaler.outputTexture = self.outputTexture;
    
    // 5. コマンドバッファにアップスケール処理をエンコード(記録)します。
    [self.mfxSpatialScaler encodeToCommandBuffer:commandBuffer];
    
    // 6. 出力テクスチャを返します。
    return self.outputTexture;
}

/// 指定された情報で空のMTLTextureを生成します。
- (id<MTLTexture>)createEmptyTextureWithWidth:(NSUInteger)width
                                       height:(NSUInteger)height
                                  pixelFormat:(MTLPixelFormat)pixelFormat {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor new];
    descriptor.pixelFormat = pixelFormat;
    descriptor.width = width;
    descriptor.height = height;
    // .renderTargetは、GPUがこのテクスチャに描画(書き込み)するために必要です。
    // .shaderReadは、このテクスチャを後で読み取ってUIImageに変換するために必要です。
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    // GPUのみがアクセスできるプライベートなメモリに配置します。
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.textureType = MTLTextureType2D;
    descriptor.mipmapLevelCount = 1;
    return [self.device newTextureWithDescriptor:descriptor];
}

@end

@interface ContentViewModel ()
// GPUとのやり取りを行うための主要なオブジェクト(デバイス)。
@property (nonatomic, strong) id<MTLDevice> device;
// GPUに送るコマンドを生成し、キューに入れるためのオブジェクト。
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
// MetalFXを使ったアップスケール処理を行うためのカスタムクラスのインスタンス。
@property (nonatomic, strong) Upscaler *upscaler;
@end

@implementation ContentViewModel

- (instancetype)initWithOriginalImage:(UIImage *)originalImage {
    self = [super init];
    if (self) {
        _original = originalImage;
        
        // システムのデフォルトGPUデバイスを取得します。
        _device = MTLCreateSystemDefaultDevice();
        if (_device == nil) {
            NSLog(@"Failed to create Metal device");
            return nil;
        }
        
        // コマンドキューをデバイスから作成します。
        _commandQueue = [_device newCommandQueue];
        if (_commandQueue == nil) {
            NSLog(@"Failed to create command queue");
            return nil;
        }
        
        // Upscalerクラスを初期化します。
        _upscaler = [[Upscaler alloc] initWithDevice:_device];
    }
    return self;
}

- (void)upscale {
    // 1. UIImageをMetalが扱えるMTLTextureに変換します。
    id<MTLTexture> inputTexture = [self.original toTextureWithDevice:self.device];
    if (inputTexture == nil) {
        NSLog(@"Failed to convert UIImage to MTLTexture");
        return;
    }
    
    // 2. GPUに送る命令(コマンド)を記録するためのバッファを作成します。
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    if (commandBuffer == nil) {
        NSLog(@"Failed to create command buffer");
        return;
    }
    
    // 3. Upscalerを使って、コマンドバッファにアップスケール処理をエンコード(記録)します。
    id<MTLTexture> outputTexture = [self.upscaler upscaleWithCommandBuffer:commandBuffer
                                                              inputTexture:inputTexture
                                                                     scale:2.0f];
    if (outputTexture == nil) {
        NSLog(@"Failed to upscale texture");
        return;
    }
    
    // 4. コマンドバッファに記録された命令をGPUに送って実行させます。
    [commandBuffer commit];
    
    // 5. GPUの処理が完了するまで待ちます。
    [commandBuffer waitUntilCompleted];
    
    // 6. 処理結果のMTLTextureを画面に表示できるUIImageに変換します。
    self.result = [outputTexture toUIImage];
}

@end

@implementation UIImage (MetalTexture)

- (id<MTLTexture>)toTextureWithDevice:(id<MTLDevice>)device {
    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:device];
    NSError *error = nil;
    // MTKTextureLoaderを使ってCGImageからMTLTextureを生成します。
    id<MTLTexture> texture = [loader newTextureWithCGImage:self.CGImage options:nil error:&error];
    if (error != nil) {
        NSLog(@"Failed to create texture from UIImage: %@", error.localizedDescription);
        return nil;
    }
    return texture;
}

@end

@implementation NSObject (MTLTextureToUIImage)

- (UIImage *)toUIImage {
    if (![self conformsToProtocol:@protocol(MTLTexture)]) {
        NSLog(@"Object does not conform to MTLTexture protocol");
        return nil;
    }
    
    id<MTLTexture> texture = (id<MTLTexture>)self;
    
    // 1. MTLTextureからCIImage(Core Imageの画像オブジェクト)を生成します。
    CIImage *ci = [CIImage imageWithMTLTexture:texture options:nil];
    if (ci == nil) {
        NSLog(@"Failed to create CIImage from MTLTexture");
        return nil;
    }
    
    // 2. 座標系の違いを補正するためのアフィン変換行列を作成します。
    // Metalのテクスチャ座標系は左上が(0,0)でY軸が下向きですが、
    // UIKitの座標系は左下(または左上)が原点でY軸が上向きのため、画像を垂直方向に反転させる必要があります。
    CGAffineTransform mat = CGAffineTransformMake(1, 0, 0, -1, 0, ci.extent.size.height);
    
    // 3. Core Imageのコンテキスト(描画環境)を生成します。
    CIContext *context = [CIContext context];
    
    // 4. CIImageにアフィン変換を適用し、その結果からCGImage(Core Graphicsの画像オブジェクト)を生成します。
    CIImage *transformedImage = [ci imageByApplyingTransform:mat];
    CGImageRef cg = [context createCGImage:transformedImage fromRect:ci.extent];
    if (cg == NULL) {
        NSLog(@"Failed to create CGImage from CIImage");
        return nil;
    }
    
    // 5. 最終的にCGImageからUIImageを生成して返します。
    UIImage *result = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    
    return result;
}

@end
