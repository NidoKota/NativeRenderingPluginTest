#pragma once

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <MetalFX/MetalFX.h>
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>

// MetalFXのSpatialScalerを使って、画像のアップスケール処理を専門に行うクラスです。
@interface Upscaler : NSObject

// GPUとのやり取りを行うための主要なオブジェクト(デバイス)。
@property (nonatomic, strong, readonly) id<MTLDevice> device;

/// 指定されたMetalデバイスでUpscalerを初期化します。
/// @param device 使用するMTLDevice
- (instancetype)initWithDevice:(id<MTLDevice>)device;

/// コマンドバッファにアップスケール処理をエンコードし、出力テクスチャを返します。
/// @param commandBuffer 処理をエンコードする先のコマンドバッファ
/// @param inputTexture アップスケールしたい入力テクスチャ
/// @param scale スケール倍率
/// @return アップスケール後のデータが書き込まれる出力テクスチャ
- (id<MTLTexture>)upscaleWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
                              inputTexture:(id<MTLTexture>)inputTexture
                                     scale:(float)scale;

@end

// UIの状態と、Metalを使った画像処理のロジックを管理するクラスです。
@interface ContentViewModel : NSObject

// アップスケール前の元の画像。
@property (nonatomic, strong, readonly) UIImage *original;
// アップスケール後の画像を保持するプロパティ。処理が終わるとここに格納されます。
@property (nonatomic, strong, nullable) UIImage *result;

/// 指定された画像でContentViewModelを初期化します。
/// @param originalImage アップスケールする元の画像
- (instancetype)initWithOriginalImage:(UIImage *)originalImage;

/// 画像をアップスケールするメインの処理です。
- (void)upscale;

@end

// UIImageを便利に扱うためのカテゴリです。
@interface UIImage (MetalTexture)

/// UIImageをMTLTextureに変換します。
/// @param device 使用するMTLDevice
/// @return 変換されたMTLTexture
- (id<MTLTexture>)toTextureWithDevice:(id<MTLDevice>)device;

@end

// MTLTextureを便利に扱うためのカテゴリです。
@interface NSObject (MTLTextureToUIImage)

/// MTLTextureをUIImageに変換します。
/// @return 変換されたUIImage
- (UIImage *)toUIImage;

@end
