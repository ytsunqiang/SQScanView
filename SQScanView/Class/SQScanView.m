//
//  SQScanPlugin.m
//  qrtest
//
//  Created by 孙强 on 2021/7/8.
//

#import "SQScanView.h"
#import <AudioToolbox/AudioToolbox.h>

@implementation SQScanPluginConfigModel

- (instancetype)init {
    if (self = [super init]) {
        self.tipType = SQScanViewTipTypeVoice;
        self.previewRect = [UIScreen mainScreen].bounds;
        CGSize size = [UIScreen mainScreen].bounds.size;
        self.readerRect = CGRectMake((size.width - 220) * 0.5, (size.height - 220) * 0.5, 220, 220);
        self.preset = AVCaptureSessionPresetHigh;
    }
    return self;
}

@end


@interface SQScanView ()<AVCaptureMetadataOutputObjectsDelegate>

@property (nonatomic, assign) BOOL started;
///是否是单次扫描
@property (nonatomic, assign) BOOL onceScan;
/// 做动画的线
@property (nonatomic, strong) UIImageView *readLineView;

/// 识别区域类型
@property (nonatomic, copy) NSArray *outputTypes;


@property (nonatomic, strong) AVCaptureVideoPreviewLayer *qrVideoPreviewLayer;
@property (nonatomic, strong) AVCaptureSession *qrSession;
@property (nonatomic, strong) AVCaptureDeviceInput *input;
@property (nonatomic, strong) AVCaptureDevice *device;


@property (nonatomic, strong) NSArray *locationLayers;
///播放提示音
@property(nonatomic, assign) SystemSoundID soundID;


@property (nonatomic, strong) AVCaptureMetadataOutput *output;

///遮罩layer
@property (nonatomic, strong) CAShapeLayer *recLayer;

@property (nonatomic, strong) UIImageView *hbImageView;
///
@property (nonatomic, assign) CGRect previewRect;

@property (nonatomic, assign) CGRect recRect;

@property (nonatomic, assign) CGRect readerRect;
@end

@implementation SQScanView

- (void)setFlashlight:(BOOL)light {
    if (light) {
        if ([_device isTorchModeSupported:AVCaptureTorchModeOn]) {
            [self setTorchMode:AVCaptureTorchModeOn];
        }
    } else {
        if ([_device isTorchModeSupported:AVCaptureTorchModeOff]) {
            [self setTorchMode:AVCaptureTorchModeOff];
        }
    }
}

- (void)setTorchMode:(AVCaptureTorchMode)torchMode {
    if (_device && _qrSession) {
        [_device lockForConfiguration:nil];

        [_device setTorchMode:torchMode];

        [_device unlockForConfiguration];
        [_qrSession commitConfiguration];
    }
}

- (void)pauseScan {
    [_readLineView.layer removeAllAnimations];
    _readLineView.hidden = YES;
    [_qrSession stopRunning];
}

- (void)startScan:(BOOL)onceScan {
    
    self.onceScan = onceScan;
    self.started = YES;
    [self setLocationLayersHidden:YES];
    if (!self.qrSession.running) {
        [_qrSession startRunning];
        if (self.configModel.showReaderBorder) {
            self.readLineView.hidden = NO;
            [self startAnimation];
        }
    }
}

- (void)dismissDelay {
    [self pauseScan];
    _qrSession = nil;
    _device = nil;
    [_readLineView stopAnimating];
    [_readLineView removeFromSuperview];
    
    [self removeFromSuperview];
}



+ (void)createScanViewWithModel:(SQScanPluginConfigModel *)model result:(void (^)(SQScanCodeState state, SQScanView *scanView))result {
    
    SQScanView *plugin = [[SQScanView alloc] initWithFrame:model.previewRect];
    [plugin initPropertyWithModel:model result:^(SQScanCodeState state, SQScanView *view) {
        if (state == SQScanCodeOK) {
            [view loopDrawLine];
//            [view crop];
        }
        result(state, state == SQScanCodeOK ? view : nil);
    }];
    
}


- (AVCaptureSession *)createSession {
    
    //拍摄会话
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    
    //读取质量，质量越高，可读取小尺寸的二维码
    if ([session canSetSessionPreset:self.configModel.preset]) {
        [session setSessionPreset:self.configModel.preset];
    } else if ([session canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
        [session setSessionPreset:AVCaptureSessionPreset1920x1080];
    } else if ([session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        [session setSessionPreset:AVCaptureSessionPreset1280x720];
    } else {
        [session setSessionPreset:AVCaptureSessionPresetPhoto];
    }
    
    if ([session canAddInput:self.input]) {
        [session addInput:self.input];
    }
    
    if ([session canAddOutput:self.output]) {
        [session addOutput:self.output];
    }
    
    //设备实际支持的类型
    NSArray *validTypes = [self readerType];
    if (validTypes != nil && validTypes.count > 0) {
        //设置输出的格式
        //一定要先设置会话的输出为output之后，再指定输出的元数据类型
        [self.output setMetadataObjectTypes:validTypes];
    } else {
        return nil;
    }
    
    return session;
}
- (NSArray *)readerType {
    ///当前设备支持的类型
    NSArray *availableTypes = self.output.availableMetadataObjectTypes;
    
    //设备实际支持的类型
    NSArray *validTypes = nil;
    
    if (availableTypes != nil && availableTypes.count > 0) {
        NSPredicate *filterPredicate = [NSPredicate predicateWithFormat:@"SELF IN %@", availableTypes];
        
        //返回设备实际支持的类型
        validTypes = [self.outputTypes filteredArrayUsingPredicate:filterPredicate];
    }
    return validTypes;
}

///初始化soundID
- (void)initSoundID {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"ScanCodeComplete.mp3" ofType:nil];
    NSURL *fileUrl = [NSURL fileURLWithPath:path];
    if (fileUrl) {
        SystemSoundID soundID = 0;
        OSStatus osStatus = AudioServicesCreateSystemSoundID((__bridge CFURLRef) (fileUrl), &soundID);
        if (osStatus == kAudioServicesNoError) {
            _soundID = soundID;
            AudioServicesAddSystemSoundCompletion(soundID, NULL, NULL, soundCompleteCallback, NULL);
        }
    }
}


static void soundCompleteCallback(SystemSoundID soundID, void *clientData) {}

- (void)initPropertyWithModel:(SQScanPluginConfigModel *)model result:(void (^)(SQScanCodeState state, SQScanView *scanView))result {
    self.configModel = model;
    [self checkCameraAvailable:^(SQScanCodeState state) {
        
        if (state == SQScanCodeOK) {//可用
            [self initSoundID];
            
            AVCaptureSession *session = [self createSession];
            
            if (session) {
                //设置预览图层
                AVCaptureVideoPreviewLayer *preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
                
                //设置preview图层的属性
                [preview setVideoGravity:AVLayerVideoGravityResizeAspectFill];
                preview.frame = self.bounds;
                [self.layer addSublayer:preview];
                self.qrVideoPreviewLayer = preview;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.readerRect = [self getReaderViewBounds];
                });
                self.qrSession = session;
                if (result) {
                    result(SQScanCodeOK, self);
                }
            } else {//session初始化失败
                if (result) {
                    result(SQScanCodeDeviceNotSupport, nil);
                }
            }
            
            
        } else {//不可用
            if (result) {
                result(state, self);
            }
        }
        
    }];
}
///检查相机是否可用 包含是否有摄像头 是否有摄像头权限
- (void)checkCameraAvailable:(void(^)(SQScanCodeState state))block {
    if (self.input == nil) {//没有摄像头
        
        if (block) {
            block(SQScanCodeDeviceNotSupport);
        }
    }
    
    [self authCameraWithBlock:^(BOOL auth) {
        if (block) {
            if (auth) {
                block(SQScanCodeOK);
            } else {
                block(SQScanCodeErrorCameraAVAuthorizationStatusNotAuthorized);
            }
        };
    }];
}

- (UIView *)boundsViewWithFrame:(CGRect)frame {
    UIView *view = [[UIView alloc] initWithFrame:frame];
    view.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.5];
    [self addSubview:view];
    return view;
}
///创建扫码背景,非识别区域添加黑色半透明view
- (void)loopDrawLine {
    if (self.configModel.showReaderBorder) {
        self.hbImageView.frame = self.configModel.readerRect;
        if (self.started) {
            [_readLineView.layer removeAllAnimations];
        }
        self.readLineView.frame = CGRectMake(self.configModel.readerRect.origin.x, self.configModel.readerRect.origin.y, self.configModel.readerRect.size.width, 7);
        if (self.started) {
            [self startAnimation];
        }
    } else {
        _hbImageView.hidden = YES;
        [_readLineView.layer removeAllAnimations];
        _readLineView.hidden = YES;
    }
    [self addRec];
}

- (void)setReaderRect:(CGRect)readerRect {
    if (!CGRectEqualToRect(_readerRect, readerRect)) {
        _readerRect = readerRect;
        [_output setRectOfInterest:readerRect];
    }
}

- (void)reload {
//    [self crop];
    if (!CGRectEqualToRect(self.frame, self.configModel.previewRect)) {    
        self.frame = self.configModel.previewRect;
    }
    [self loopDrawLine];
    self.readerRect = [self getReaderViewBounds];
    
    if (self.configModel.preset != self.qrSession.sessionPreset) {
        if ([self.qrSession canSetSessionPreset:self.configModel.preset]) {
            [self.qrSession setSessionPreset:self.configModel.preset];
        }
    }
    NSArray *readerType = [self readerType];
    if ((![self.output.metadataObjectTypes isEqualToArray:readerType]) && readerType.count) {
        [self.output setMetadataObjectTypes:readerType];
    }
}

///执行扫描动画
- (void)startAnimation {
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        CGFloat c_width = self.configModel.readerRect.size.height - 7;
        CABasicAnimation *scanNetAnimation = [CABasicAnimation animation];
        scanNetAnimation.keyPath = @"transform.translation.y";
        scanNetAnimation.byValue = @(c_width);
        scanNetAnimation.duration = 2.0;
        scanNetAnimation.repeatCount = MAXFLOAT;
        [self.readLineView.layer addAnimation:scanNetAnimation forKey:@"translationAnimation"];
    });
}
///添加遮罩
- (void)addRec {
    //中间镂空的矩形框
    CGRect myRect = self.configModel.readerRect;
    if (!CGRectEqualToRect(myRect, self.recRect)) {
        self.recRect = myRect;
        //背景
        UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.bounds];
        //镂空
        UIBezierPath *recPath = [UIBezierPath  bezierPathWithRect:myRect];
        [path appendPath:recPath];
        [path setUsesEvenOddFillRule:YES];
        self.recLayer.path = path.CGPath;
    }
}
//获取识别区域
- (CGRect)getReaderViewBounds {
    return [self.qrVideoPreviewLayer metadataOutputRectOfInterestForRect:self.configModel.readerRect];
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

//此方法是在识别到QRCode，并且完成转换
//如果QRCode的内容越大，转换需要的时间就越长
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
    if (!self.started) {
        return;
    }
    //扫描结果
    if (metadataObjects.count > 0) {
        if (self.onceScan) {
            [self pauseScan];
            if (self.configModel.tipType == SQScanViewTipTypeShake) {
                AudioServicesPlaySystemSound(1520);
            } else if (self.configModel.tipType == SQScanViewTipTypeVoice) {
                //播放音效
                AudioServicesPlaySystemSound(self.soundID);
            }
            if (self.configModel.mark) {//标记码的位置
                AVMetadataMachineReadableCodeObject *obj1 = [self transformedCodeFromCode:metadataObjects[0]];
                [self didDetectCodes:obj1.bounds corner:obj1.corners];
            }
        }
        AVMetadataMachineReadableCodeObject *obj = metadataObjects[0];
        NSString *codeString = obj.stringValue;
        
        if (codeString && ![codeString isEqualToString:@""] && codeString.length > 0) {
            if ([obj.type isEqualToString:AVMetadataObjectTypeEAN13Code]) {
                // UPC-A 格式 条码前面会多一个 0
                if ([codeString hasPrefix:@"0"] && [codeString length] > 1) {
                    codeString = [codeString substringFromIndex:1];
                }
            }
            
            [self parseQRResult:codeString];
        }
    }
}

- (void)parseQRResult:(NSString *)result {
    
    if (self.configModel.delegate && [self.configModel.delegate respondsToSelector:@selector(scanView:message:)]) {
        [self.configModel.delegate scanView:self message:result];
    }
}

#pragma mark ---------- 获取图片 -----------

- (UIImage *)imageWithName:(NSString *)name {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    return [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
}

#pragma mark ---- 懒加载 ---

- (UIImageView *)hbImageView {
    if (!_hbImageView) {
        _hbImageView = [[UIImageView alloc] init];
        _hbImageView.image = [self imageWithName:@"sqscanview_recView"];
        [self addSubview:_hbImageView];
    }
    return _hbImageView;
}

- (CALayer *)recLayer {
    if (!_recLayer) {
        CAShapeLayer *fillLayer = [CAShapeLayer layer];
        fillLayer.fillRule = kCAFillRuleEvenOdd;
        fillLayer.fillColor = [UIColor blackColor].CGColor;
        fillLayer.opacity = 0.4;
        [self.layer insertSublayer:fillLayer above:self.qrVideoPreviewLayer];
        _recLayer = fillLayer;
    }
    return _recLayer;
}

- (UIImageView *)readLineView {
    if (!_readLineView) {
        _readLineView = [[UIImageView alloc] init];
        
        _readLineView.image = [self imageWithName:@"sqscanview_lineview"];
        [self addSubview: _readLineView];
    }
    return _readLineView;
}

- (AVCaptureDevice *)device {
    if (!_device) {
        _device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    return _device;
}

- (AVCaptureDeviceInput *)input {
    if (!_input) {
        NSError *error = nil;
        _input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:&error];
        if (error) {
            return nil;
        }
    }
    return _input;
}

- (AVCaptureMetadataOutput *)output {
    if (!_output) {
        //设置输出(Metadata元数据)
        AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
        _output = output;
        //设置输出的代理
        //使用主线程队列，相应比较同步，使用其他队列，相应不同步，容易让用户产生不好的体验
        [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        self.readerRect = [self getReaderViewBounds];
    }
    return _output;
}

- (NSArray *)outputTypes {
        NSInteger type = self.configModel.type;
        if (type == 1) {//二维码
            _outputTypes = @[
                AVMetadataObjectTypeQRCode
            ];
        } else if (type == 2) {//条形码+二维码
            _outputTypes = @[
                AVMetadataObjectTypeQRCode,
                AVMetadataObjectTypeUPCECode,
                AVMetadataObjectTypeITF14Code,
                AVMetadataObjectTypeEAN13Code,
                AVMetadataObjectTypeEAN8Code,
                AVMetadataObjectTypeCode39Code,
                AVMetadataObjectTypeCode93Code,
                AVMetadataObjectTypeCode39Mod43Code,
                AVMetadataObjectTypeCode128Code
            ];
        } else {//默认条形码
            _outputTypes = @[
                AVMetadataObjectTypeUPCECode,
                AVMetadataObjectTypeITF14Code,
                AVMetadataObjectTypeEAN13Code,
                AVMetadataObjectTypeEAN8Code,
                AVMetadataObjectTypeCode39Code,
                AVMetadataObjectTypeCode93Code,
                AVMetadataObjectTypeCode39Mod43Code,
                AVMetadataObjectTypeCode128Code
            ];
        }
    
    return _outputTypes;
}

#pragma mark ----- 获取摄像头权限 -----
- (void)authCameraWithBlock:(void(^)(BOOL auth))complete {
    
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    
    switch (authStatus) {
            //第一次使用，用户还没有对当前应用程序调用相机的权限做出设置
        case AVAuthorizationStatusNotDetermined: {
            //请求权限
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (complete) {
                        complete(granted);
                    }
                });
            }];
        }
            break;
            
            // 用户授权此应用程序访问相机
        case AVAuthorizationStatusAuthorized: {
            if (complete) {
                complete(YES);
            }
        }
            break;
            
            //用户已经明确否认了这个应用程序访问相机
        case AVAuthorizationStatusDenied:
            //当前应用程序未被授权访问相机。用户不能更改该应用程序的状态,可能是由于活动的限制,如家长控制到位。
        case AVAuthorizationStatusRestricted: {
            if (complete) {
                complete(NO);
            }
        }
            break;
    }
}



- (void)dealloc {
//    NSLog(@"--------==========");
    [self setFlashlight:NO];
}

#pragma mark ---------------- 扫码之后 定位二维码在图片中位置相关的代码 ---------------
- (NSArray *)transformedCodesFromCodes:(NSArray *)codes {
    NSMutableArray *transformedCodes = [NSMutableArray array];
    [codes enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        AVMetadataObject *transformedCode = [_qrVideoPreviewLayer  transformedMetadataObjectForMetadataObject:obj];
        [transformedCodes addObject:transformedCode];
    }];
    return [transformedCodes copy];
}

- (AVMetadataMachineReadableCodeObject *)transformedCodeFromCode:(AVMetadataMachineReadableCodeObject *)code {
    
    AVMetadataMachineReadableCodeObject *transformedCode = (AVMetadataMachineReadableCodeObject *)[_qrVideoPreviewLayer  transformedMetadataObjectForMetadataObject:code];
    return transformedCode;
}

- (CGPoint)pointForCorner:(NSDictionary *)corner {
    CGPoint point;
    CGPointMakeWithDictionaryRepresentation((CFDictionaryRef)corner, &point);
    return point;
}
///添加二维码中间button
- (void)addCenterButton:(AVMetadataMachineReadableCodeObject *)obj {
    
    
    CGFloat totalX = 0;
    CGFloat totalY = 0;
    
    for (NSDictionary *dic in obj.corners) {
        CGPoint pt = [self pointForCorner:dic];
        totalX += pt.x;
        totalY += pt.y;
    }
    
    CGFloat averX = totalX / obj.corners.count;
    CGFloat averY = totalY / obj.corners.count;
    
//    CGFloat minSize = MIN(obj.bounds.size.width , obj.bounds.size.height);

    NSString *codeString = obj.stringValue;

    if (codeString && ![codeString isEqualToString:@""] && codeString.length > 0) {
        if ([obj.type isEqualToString:AVMetadataObjectTypeEAN13Code]) {
            // UPC-A 格式 条码前面会多一个 0
            if ([codeString hasPrefix:@"0"] && [codeString length] > 1) {
                codeString = [codeString substringFromIndex:1];
            }
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
             
        [self signCodeWithCenterX:averX centerY:averY result:codeString];
    });
    
    

}
- (void)handCorners:(NSArray<NSDictionary *> *)corners bounds:(CGRect)bounds result:(NSString *)result
{
    CGFloat totalX = 0;
    CGFloat totalY = 0;
    
    for (NSDictionary *dic in corners) {
        CGPoint pt = [self pointForCorner:dic];
        totalX += pt.x;
        totalY += pt.y;
    }
    
    CGFloat averX = totalX / corners.count;
    CGFloat averY = totalY / corners.count;

    dispatch_async(dispatch_get_main_queue(), ^{
             
        [self signCodeWithCenterX:averX centerY:averY result:result];
    });
}

- (void)signCodeWithCenterX:(CGFloat)centerX centerY:(CGFloat)centerY result:(NSString *)result
{
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = [UIColor greenColor];
    view.frame = CGRectMake(centerX - 22, centerY - 22, 44, 44);
    [self addSubview:view];
}
#pragma mark- 绘制二维码区域标志

- (void)setLocationLayersHidden:(BOOL)hidden {
    for (CALayer *layer in self.locationLayers) {
        layer.hidden = hidden;
    }
}

- (void)didDetectCodes:(CGRect)bounds corner:(NSArray<NSDictionary*>*)corners
{
    AVCaptureVideoPreviewLayer * preview = _qrVideoPreviewLayer;
    
    if (self.locationLayers == nil) {
        self.locationLayers = @[[self makeBoundsLayer],[self makeCornersLayer]];
        [preview addSublayer:self.locationLayers[0]];
        [preview addSublayer:self.locationLayers[1]];
    } else {
        [self setLocationLayersHidden:NO];
    }
    NSArray *layers = self.locationLayers;
    
    CAShapeLayer *boundsLayer = layers[0];
    boundsLayer.path = [self bezierPathForBounds:bounds].CGPath;
    //得到一个CGPathRef赋给图层的path属性
    
    if (corners) {
        CAShapeLayer *cornersLayer = layers[1];
        cornersLayer.path = [self bezierPathForCorners:corners].CGPath;
        //对于cornersLayer，基于元数据对象创建一个CGPath
    }
}

- (UIBezierPath *)bezierPathForBounds:(CGRect)bounds {
    // 图层边界，创建一个和对象的bounds关联的UIBezierPath
    return [UIBezierPath bezierPathWithRect:bounds];
}

- (CAShapeLayer *)makeBoundsLayer {
    //CAShapeLayer 是具体化的CALayer子类，用于绘制Bezier路径
    CAShapeLayer *shapeLayer = [CAShapeLayer layer];
    shapeLayer.strokeColor = [UIColor colorWithRed:0.96f green:0.75f blue:0.06f alpha:1.0f].CGColor;
    shapeLayer.fillColor = nil;
    shapeLayer.lineWidth = 4.0f;
    
    return shapeLayer;
}

- (CAShapeLayer *)makeCornersLayer {
    
    CAShapeLayer *cornersLayer = [CAShapeLayer layer];
    cornersLayer.lineWidth = 2.0f;
    cornersLayer.strokeColor = [UIColor colorWithRed:0.172 green:0.671 blue:0.428 alpha:1.0].CGColor;
    cornersLayer.fillColor = [UIColor colorWithRed:0.190 green:0.753 blue:0.489 alpha:0.5].CGColor;
    
    return cornersLayer;
}

- (UIBezierPath *)bezierPathForCorners:(NSArray *)corners {
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (int i = 0; i < corners.count; i ++) {
        CGPoint point = [self pointForCorner:corners[i]];
        //遍历每个条目，为每个条目创建一个CGPoint
        if (i == 0) {
            [path moveToPoint:point];
        } else {
            [path addLineToPoint:point];
        }
    }
    [path closePath];
    return path;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    
    return CGRectContainsPoint(self.configModel.previewRect, point);
}

@end
