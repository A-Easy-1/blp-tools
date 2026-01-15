#import "CameraManager.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

NSString * const CameraManagerNewFrameNotification = @"CameraManagerNewFrameNotification";

@interface CameraManager ()

@property (nonatomic, assign) BOOL isProcessingFrame;
@property (nonatomic, assign) NSTimeInterval lastFrameTime;

@property (nonatomic, strong, readwrite) AVCaptureSession *captureSession;
@property (nonatomic, strong, readwrite) AVCaptureVideoDataOutput *videoOutput;

@property (nonatomic, strong) dispatch_queue_t cameraQueue;
@property (nonatomic, assign) BOOL cameraIsRunning;

@end

@implementation CameraManager

+ (instancetype)shared {
    static CameraManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CameraManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cameraQueue = dispatch_queue_create("com.yourapp.CameraQueue", DISPATCH_QUEUE_SERIAL);
        _cameraIsRunning = NO;
    }
    return self;
}

#pragma mark - Public Methods

- (void)startCamera {
    if (self.cameraIsRunning) return;
    self.cameraIsRunning = YES;
    
    // 1. Start listening for rotation (Critical for iPad)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(orientationChanged:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    
    dispatch_async(self.cameraQueue, ^{
        [self setupCaptureSession];
    });
}

- (void)stopCamera {
    if (!self.cameraIsRunning) return;
    self.cameraIsRunning = NO;
    
    // Stop listening for rotation
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    dispatch_async(self.cameraQueue, ^{
        [self.captureSession stopRunning];
        self.captureSession = nil;
        self.videoOutput = nil;
    });
}

#pragma mark - Setup Capture Session

- (void)setupCaptureSession {
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetHigh;
    
    AVCaptureDevice *camera = [self getUltraWideCameraIfAvailable];
    if (!camera) camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    if (error || ![session canAddInput:input]) return;
    
    [session addInput:input];
    
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    dispatch_queue_t sampleBufferQueue = dispatch_queue_create("VideoOutputQueue", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:sampleBufferQueue];
    output.videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    
    if ([session canAddOutput:output]) {
        [session addOutput:output];
    }
    
    // --- ROTATION FIX START ---
    // We check if the 'videoOrientation' property exists (it always does on iOS)
    // and silence the deprecation warning for this specific block.
    AVCaptureConnection *conn = [output connectionWithMediaType:AVMediaTypeVideo];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (conn.isVideoOrientationSupported) {
        conn.videoOrientation = [self currentVideoOrientation];
    }
    #pragma clang diagnostic pop
    // --- ROTATION FIX END ---
    
    // Exposure Settings
    if ([camera lockForConfiguration:&error]) {
        if ([camera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            camera.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        }
        [camera setExposureTargetBias:-3.0f completionHandler:nil];
        [camera unlockForConfiguration];
    }
    
    self.captureSession = session;
    self.videoOutput = output;
    [session startRunning];
}

#pragma mark - Rotation Helpers

- (void)orientationChanged:(NSNotification *)notification {
    // When device rotates, update camera connection
    AVCaptureConnection *conn = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (conn.isVideoOrientationSupported) {
        conn.videoOrientation = [self currentVideoOrientation];
    }
    #pragma clang diagnostic pop
}

- (AVCaptureVideoOrientation)currentVideoOrientation {
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    switch (orientation) {
        case UIDeviceOrientationPortrait: return AVCaptureVideoOrientationPortrait;
        case UIDeviceOrientationLandscapeLeft: return AVCaptureVideoOrientationLandscapeRight; // Mirrored for back camera
        case UIDeviceOrientationLandscapeRight: return AVCaptureVideoOrientationLandscapeLeft;
        case UIDeviceOrientationPortraitUpsideDown: return AVCaptureVideoOrientationPortraitUpsideDown;
        default: return AVCaptureVideoOrientationPortrait;
    }
}

- (AVCaptureDevice *)getUltraWideCameraIfAvailable {
    AVCaptureDeviceDiscoverySession *discovery =
    [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInUltraWideCamera]
                                                           mediaType:AVMediaTypeVideo
                                                            position:AVCaptureDevicePositionBack];
    return discovery.devices.firstObject;
}

#pragma mark - Output Delegate

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    // FPS Throttling
    float targetFPS = [[NSUserDefaults standardUserDefaults] floatForKey:@"camera_fps"];
    if (targetFPS < 2.0) targetFPS = 15.0; // Default safety
    
    NSTimeInterval minInterval = 1.0 / targetFPS;
    NSTimeInterval now = CACurrentMediaTime();
    if ((now - self.lastFrameTime) < minInterval) return;
    self.lastFrameTime = now;
    
    if (self.isProcessingFrame) return;
    self.isProcessingFrame = YES;
    
    @autoreleasepool {
        UIImage *frame = [self imageFromSampleBuffer:sampleBuffer];
        if (frame) {
            [[NSNotificationCenter defaultCenter] postNotificationName:CameraManagerNewFrameNotification
                                                                object:nil
                                                              userInfo:@{@"frame": frame}];
        }
        self.isProcessingFrame = NO;
    }
}

- (UIImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    
    // CHANGED: Use "Up" because we are now rotating the hardware stream correctly.
    // If we used "Down" here while rotating hardware, the image would be upside down.
    UIImage *image = [UIImage imageWithCGImage:quartzImage
                                         scale:1.0
                                   orientation:UIImageOrientationUp];
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(quartzImage);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    return image;
}

@end
