//
//  SQScanPlugin.h
//  qrtest
//
//  Created by 孙强 on 2021/7/8.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, SQScanCodeState) {
    SQScanCodeOK,
    SQScanCodeDeviceNotSupport,
    SQScanCodeErrorCameraAVAuthorizationStatusNotAuthorized
};
typedef NS_ENUM(NSInteger, SQScanViewTipType) {
    SQScanViewTipTypeVoice,
    SQScanViewTipTypeShake,
    SQScanViewTipTypeNone
};

@class SQScanView;

NS_ASSUME_NONNULL_BEGIN

@protocol SQScanViewPluginDelegate <NSObject>

/// 识别成功
/// @param scanPlugin 扫码插件
/// @param message 扫描结果
- (void)scanView:(SQScanView *)scanPlugin message:(NSString *)message;

@end

@interface SQScanPluginConfigModel : NSObject

///识别成功之后提示类型 默认声音  仅单次扫码设置有效
@property (nonatomic, assign) SQScanViewTipType tipType;
///预览区域
@property (nonatomic, assign) CGRect previewRect;
///识别区域, 识别区域是相对于预览区域计算的
@property (nonatomic, assign) CGRect readerRect;
///识别类型 0 条形码 1二维码 2条形码+二维码 默认条形码 reload会闪屏
@property (nonatomic, assign) NSInteger type;
///识别成功之后是否标记码的位置  仅单次扫码设置有效
@property (nonatomic, assign) BOOL mark;
///是否显示扫码边框以及线
@property (nonatomic, assign) BOOL showReaderBorder;
///识别结果代理
@property (nonatomic, weak) id<SQScanViewPluginDelegate> delegate;
///相机分辨率 默认1920x1080  reload会闪屏
@property (nonatomic, assign) AVCaptureSessionPreset preset;

@end

@interface SQScanView : UIView

///配置model
@property (nonatomic, strong) SQScanPluginConfigModel *configModel;
/// 开始扫描
/// @param onceScan 是否单次扫描
- (void)startScan:(BOOL)onceScan;

/// 暂停扫码
- (void)pauseScan;

/// 关闭并且移除
- (void)dismissDelay;

/// 闪光灯
/// @param light 是否开启
- (void)setFlashlight:(BOOL)light;

/// 添加扫码view
/// @param model 配置model
/// @param result 结果回调 当state != ok的时候  plugin为nil
+ (void)AddScanViewWithModel:(SQScanPluginConfigModel *)model result:(void (^)(SQScanCodeState state, SQScanView *scanView))result;

- (void)reload;
@end

NS_ASSUME_NONNULL_END
