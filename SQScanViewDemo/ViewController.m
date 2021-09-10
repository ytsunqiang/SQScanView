//
//  ViewController.m
//  SQScanViewDemo
//
//  Created by 孙强 on 2021/9/9.
//

#import "ViewController.h"
#import "SQScanView.h"
@interface ViewController ()<SQScanViewPluginDelegate>


@property (nonatomic, strong) SQScanPluginConfigModel *model;

@property (nonatomic, strong) SQScanView *scanView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    SQScanPluginConfigModel *model = [[SQScanPluginConfigModel alloc] init];
    self.model = model;
    model.previewRect = CGRectMake(50, 00, 300, 400);
    model.readerRect = CGRectMake(50, 50, 200, 300);
    model.tipType = SQScanViewTipTypeShake;
    model.mark = YES;
    model.showReaderBorder = YES;
    model.delegate = self;
    model.type = 2;
    [SQScanView AddScanViewWithModel:model result:^(SQScanCodeState state, SQScanView * _Nonnull scanView) {

        [self.view addSubview:scanView];
        [scanView startScan:YES];
        self.scanView = scanView;
    }];
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(100, 600, 200, 50)];
    label.textColor = UIColor.blackColor;
    [self.view addSubview:label];
    label.tag = 100;
    
    UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(100, 550, 160, 50)];
    [btn addTarget:self action:@selector(changeReader) forControlEvents:UIControlEventTouchUpInside];
    btn.backgroundColor = UIColor.orangeColor;
    [btn setTitle:@"改变区域" forState:UIControlStateNormal];
    [self.view addSubview:btn];
}

- (void)changeReader {
    self.model.previewRect = CGRectMake(0, 100, 300, 400);
    [self.scanView reload];
}

- (void)scanView:(SQScanView *)scanPlugin message:(NSString *)message {
    UILabel *result = [self.view viewWithTag:100];
    result.text = message;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.scanView startScan:YES];
    });
}


@end
